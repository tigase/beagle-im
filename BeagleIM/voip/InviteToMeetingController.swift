//
//  InviteToMeetingController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 20/07/2021.
//  Copyright © 2021 HI-LOW. All rights reserved.
//

import AppKit
import Combine
import TigaseSwift

class InviteToMeetingController: NSViewController {
    
    @IBOutlet var contactSelectionView: MultiContactSelectionView!;
    @IBOutlet var inviteButton: NSButton!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    private var cancellables: Set<AnyCancellable> = [];

    var meet: Meet?;
    
    @Published
    private var operationInProgress: Bool = false;
    
    override func viewWillAppear() {
        super.viewWillAppear();
                        
        contactSelectionView.$items.combineLatest($operationInProgress).map({ (items, inProgress) in !(items.isEmpty || inProgress) }).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] available in
            self?.inviteButton.isEnabled = available;
        }).store(in: &cancellables);
        
        $operationInProgress.removeDuplicates().receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] inProgress in
            if inProgress {
                self?.progressIndicator.startAnimation(nil);
            } else {
                self?.progressIndicator.stopAnimation(nil);
            }
        }).store(in: &cancellables);
    }
    
    @IBAction func inviteClicked(_ sender: NSButton) {
        guard let meet = self.meet else {
            return;
        }
        
        self.operationInProgress = true;
        meet.allow(jids: self.contactSelectionView.items.map({ $0.jid }), completionHandler: { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let jids):
                    for jid in jids {
                        meet.client.module(.meet).sendMessageInitiation(action: .propose(id: UUID().uuidString, meetJid: meet.jid, media: [.audio, .video]), to: JID(jid));
                    }
                    self.close();
                case .failure(let error):
                    let alert = NSAlert();
                    alert.alertStyle = .warning;
                    alert.messageText = NSLocalizedString("Allowing access to meeting failed", comment: "invite to meeting controller");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to grant selected users access to the meeting. Received an error: %@", comment: "invite to meeting controller"), error.description);
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
                        // nothing to do except closing..
                        self.close();
                    });
                }
            }
            self.operationInProgress = false;
        });
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        close();
    }
 
    fileprivate func close() {
        self.view.window?.orderOut(self);
    }

}
