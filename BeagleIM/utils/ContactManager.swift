//
// ContactManager.swift
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

import Foundation
import TigaseSwift
import AppKit
import Combine

public class Contact: DisplayableIdProtocol {

    public let key: Key;
    
    @Published
    public var displayName: String;
    public var displayNamePublisher: Published<String>.Publisher {
        return $displayName;
    }
    
    @Published
    public var status: Presence.Show?;
    public var statusPublisher: Published<Presence.Show?>.Publisher {
        return $status;
    }
    
    @Published
    public var description: String?;
    public var descriptionPublisher: Published<String?>.Publisher {
        return $description;
    }
    
    public let avatar: Avatar;
    public var avatarPublisher: AnyPublisher<NSImage?, Never> {
        return avatar.$avatar.eraseToAnyPublisher();
    }

    public init(key: Key, displayName: String, status: Presence.Show?) {
        self.key = key;
        self.displayName = displayName;
        self.status = status;
        self.avatar = AvatarManager.instance.avatarPublisher(for: .init(account: key.account, jid: key.jid, mucNickname: nil));
    }
    
    deinit {
        ContactManager.instance.release(key);
    }
    
    public struct Key: Hashable, Equatable {
        public let account: BareJID;
        public let jid: BareJID;
        public let type: KeyType
    }

    public enum KeyType: Hashable, Equatable {
        case buddy
        case occupant(nickname: String)
        case participant(id: String)
    }
    
    public struct Weak {
        weak var contact: Contact?;
    }
    
}

public class ContactManager {
    
    public let dispatcher = QueueDispatcher(label: "contactManager");
    public static let instance = ContactManager();
    
    private var items: [Contact.Key: Contact.Weak] = [:];
    private var cancellables: Set<AnyCancellable> = [];
    
    public init() {
        PresenceStore.instance.bestPresenceEvents.receive(on: dispatcher.queue).sink(receiveValue: { [weak self] event in
            self?.update(presence: event.presence, for: .init(account: event.account, jid: event.jid, type: .buddy));
        }).store(in: &cancellables);
    }
    
    public func contact(for key: Contact.Key) -> Contact {
        return dispatcher.sync(execute: {
            if let contact = self.items[key]?.contact {
                return contact;
            } else {
                let contact = Contact(key: key, displayName: self.name(for: key), status: self.status(for: key));
                self.items[key] = Contact.Weak(contact: contact);
                return contact;
            }
        });
    }
    
    public func existingContact(for key: Contact.Key) -> Contact? {
        return dispatcher.sync(execute: {
            return self.items[key]?.contact;
        })
    }
    
    public func update(name: String?, for key: Contact.Key) {
        guard let contact = existingContact(for: key) else {
            return;
        }
        
        DispatchQueue.main.async {
            contact.displayName = name ?? key.jid.stringValue;
        }
    }
    
    public func update(presence: Presence?, for key: Contact.Key) {
        guard let contact = existingContact(for: key) else {
            return;
        }
        
        DispatchQueue.main.async {
            contact.status = presence?.show;
            contact.description = presence?.status;
        }
    }
    
    private func status(for key: Contact.Key) -> Presence.Show? {
        switch key.type {
        case .buddy:
            return PresenceStore.instance.bestPresence(for: key.jid, on: key.account)?.show;
        case .participant(let id):
            return PresenceStore.instance.bestPresence(for: BareJID(localPart: "\(id)#\(key.jid.localPart ?? "")", domain: key.jid.domain), on: key.account)?.show;
        case .occupant(let nickname):
            return (DBChatStore.instance.conversation(for: key.account, with: key.jid) as? Room)?.occupant(nickname: nickname)?.presence.show;
        }
    }

    private func name(for key: Contact.Key) -> String {
        switch key.type {
        case .buddy:
            return DBRosterStore.instance.item(for: key.account, jid: JID(key.jid))?.name ?? key.jid.stringValue;
        case .participant(let id):
            return (DBChatStore.instance.conversation(for: key.account, with: key.jid) as? Channel)?.participant(withId: id)?.nickname ?? id;
        case .occupant(let nickname):
            return nickname;
        }
    }
    
    fileprivate func release(_ key: Contact.Key) {
        dispatcher.async {
            if let weak = self.items[key], weak.contact == nil {
                self.items.removeValue(forKey: key);
            }
        }
    }
    
}
