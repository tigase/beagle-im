//
// ConfigureRoomViewController.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//

import AppKit
import Martin
import Quartz

class ConfigureRoomViewController: NSViewController {
 
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    var account: BareJID!;
    var mucComponent: BareJID!;
    var roomJid: BareJID!;
    var nickname: String?;
    
    private var room: Room?;
    
    @IBOutlet var avatarView: AvatarChangeButton!;
    @IBOutlet var roomNameField: NSTextField!;
    @IBOutlet var subjectField: NSTextField!;
    
    @IBOutlet var formView: JabberDataFormView!;
    @IBOutlet var scrollView: NSScrollView!;

    var form: RoomConfig? {
        didSet {
            if let roomJid = self.roomJid, let account = self.account {
                avatarView.avatar = AvatarManager.instance.avatar(for: roomJid, on: account)
                roomNameField.stringValue = form?.name ?? "";
                subjectField.stringValue = room?.subject ?? "";
            }
            formView.form = form?.form;
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        
        room = DBChatStore.instance.conversation(for: account, with: roomJid) as? Room;
        
        self.avatarView.isEnabled = false;
        self.avatarView.changeLabel.isEnabled = false;
        self.avatarView.changeLabel.isHidden = true;
        
        formView.hideFields = ["muc#roomconfig_roomname"];
        formView.isHidden = true;
        
        guard let mucModule: MucModule = room?.context?.module(.muc) else {
            return;
        }
        
        progressIndicator.startAnimation(nil);
        var tasks: [Task<Void,Error>] = [
            Task {
                do {
                    let config = try await mucModule.roomConfiguration(of:  JID(roomJid == nil ? mucComponent : roomJid!));
                    await MainActor.run(body: {
                        self.form = config;
                    })
                } catch {
                    await MainActor.run(body: {
                        let alert = NSAlert();
                        alert.messageText = NSLocalizedString("Error occurred", comment: "alert window title");
                        alert.icon = NSImage(named: NSImage.cautionName);
                        alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("Could not retrieve room configuration from the server. Got following error: %@", comment: "alert window message"), error.localizedDescription);
                        _ = alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                        alert.beginSheetModal(for: self.view.window!, completionHandler: { result in
                            self.close(result: .cancel);
                        });
                    })
                }
            }
        ];
        if let client = room?.context {
            tasks.append(Task {
                do {
                    try await checkVCardSupport(vCardTempModule: client.module(.vcardTemp));
                    await MainActor.run(body: {
                        self.avatarView.isEnabled = true;
                    })
                } catch {
                    if (error as? XMPPError)?.condition == .item_not_found {
                        do {
                            let result = try await checkVCardSupport(discoModule: client.module(.disco));
                            await MainActor.run(body: {
                                self.avatarView.isEnabled = result;
                            })
                        } catch {
                            await MainActor.run(body: {
                                self.avatarView.isEnabled = false;
                            })
                        }
                    } else {
                        await MainActor.run(body: {
                            self.avatarView.isEnabled = false;
                        })
                    }
                }
            });
        }
        
        Task {
            for task in tasks {
                _ = await task.result
            }
            await MainActor.run(body: {
                self.progressIndicator.stopAnimation(nil)
            })
        }
    }
    
    private func checkVCardSupport(vCardTempModule: VCardTempModule) async throws {
        _ = try await vCardTempModule.retrieveVCard(from: JID(roomJid!));
    }
    
    private func checkVCardSupport(discoModule: DiscoveryModule) async throws -> Bool {
        let info = try await discoModule.info(for: JID(self.mucComponent!));
        return info.features.contains(VCardTempModule.ID);
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        self.close(result: .cancel);
    }
    
    @IBAction func acceptClicked(_ sender: NSButton) {
        guard form != nil else {
            return;
        }
        
        formView.synchronize();
        
        let name = roomNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines);
        form?.name = name.isEmpty ? nil : name;
        
        guard let client = room?.context, room?.state == .joined else {
            return;
        }
        
        progressIndicator.startAnimation(nil);

        var tasks: [Task<Void,Error>] = [];
                
        let roomJid = self.roomJid!;
        
        if avatarView.isEnabled && avatarView.avatar != AvatarManager.instance.avatar(for: roomJid, on: account) {
            var vcard = VCard();
            if let binval = avatarView.avatar?.scaled(maxWidthOrHeight: 512.0).jpegData(compressionQuality: 0.8)?.base64EncodedString(options: []) {
                vcard.photos = [VCard.Photo(uri: nil, type: "image/jpeg", binval: binval, types: [.home])];
            }
            
            tasks.append(Task {
                try await client.module(.vcardTemp).publish(vcard: vcard, to: roomJid);
            })
        }
        
        if subjectField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) != room?.subject ?? "" {
            let newSubject = subjectField.stringValue.isEmpty ? nil : subjectField.stringValue;
            tasks.append(Task {
                try await client.module(.muc).setRoomSubject(roomJid: roomJid, newSubject: newSubject);
            })
        }
        
        let room = self.room;
        let password = form!.secret;
        
        let mucModule = client.module(.muc);
        tasks.append(Task {
            do {
                try await mucModule.roomConfiguration(form!, of: JID(roomJid));
                room?.updateOptions({ options in
                    options.password = password;
                })
                if let bookmark = client.module(.pepBookmarks).currentBookmarks.conference(for: JID(roomJid)) {
                    try? await client.module(.pepBookmarks).addOrUpdate(bookmark: bookmark.with(password: password));
                }
            } catch {
                await MainActor.run(body: {
                    guard let window = self.view.window else {
                        return;
                    }
                    let alert = NSAlert();
                    alert.messageText = NSLocalizedString("Error occurred", comment: "alert window title");
                    alert.icon = NSImage(named: NSImage.cautionName);
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("Could not apply room configuration on the server. Got following error: %@", comment: "alert window message"), error.localizedDescription);
                    _ = alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                    alert.beginSheetModal(for: window, completionHandler: { result in
                        self.close();
                    });
                })
            }
        })
        
        Task {
            if (await tasks.asyncMap({ r in
                switch await r.result {
                case .failure(_):
                    return true;
                case .success(_):
                    return true;
                }
            })).filter({ $0 }).isEmpty {
                await MainActor.run(body: {
                    self.close();
                })
            }
            await MainActor.run(body: {
                self.progressIndicator.stopAnimation(nil);
            })
        }
    }
        
    @IBAction func disclosureClicked(_ sender: NSButton) {
        formView.isHidden = sender.state == .off;
    }
    
    fileprivate func close(result: NSApplication.ModalResponse = .OK) {
        self.view.window?.sheetParent?.endSheet(self.view.window!, returnCode: result);
    }
    
    @IBAction func avatarClicked(_ sender: Any) {
        let taker = IKPictureTaker.pictureTaker();
        if let image = avatarView.image {
            taker?.setInputImage(image);
        }
        taker?.setValue(true, forKey: IKPictureTakerShowAddressBookPictureKey)
        taker?.setValue(true, forKey: IKPictureTakerShowEmptyPictureKey);
        taker?.beginSheet(for: self.view.window!, withDelegate: self, didEnd: #selector(avatarSelected), contextInfo: nil);
    }
    
    @objc func avatarSelected(_ pictureTaker: IKPictureTaker, code: Int, context: Any?) {
        guard code == NSApplication.ModalResponse.OK.rawValue  else {
            return;
        }
        avatarView.image = pictureTaker.outputImage();
    }
}

class AvatarChangeButton: AvatarView {
    
    @IBOutlet var changeLabel: NSTextField!;

    private var trackingArea: NSTrackingArea?;
        
    override func updateTrackingAreas() {
        super.updateTrackingAreas();
        
        if let trackingArea = self.trackingArea {
            self.removeTrackingArea(trackingArea);
        }
        
        trackingArea = NSTrackingArea(rect: self.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil);
        self.addTrackingArea(trackingArea!);
    }
    
    override func mouseEntered(with event: NSEvent) {
        self.changeLabel.isHidden = (!isEnabled) || false;
    }
    
    override func mouseExited(with event: NSEvent) {
        self.changeLabel.isHidden = true;
    }
    
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 1 && isEnabled else {
            return;
        }
        self.target?.performSelector(onMainThread: self.action!, with: self, waitUntilDone: false);
    }
}

class NSTextFieldNoClick: NSTextField {
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil;
    }
    
}
