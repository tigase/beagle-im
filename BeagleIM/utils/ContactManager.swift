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

extension Publishers {
    
    
}

public struct KeepRefPublisher<Output>: Publisher {
        
    public typealias Failure = Never
    
    public weak var ref: AnyObject?;
    private let parent: AnyPublisher<Output,Never>;
    
    public init(ref: AnyObject?, parent: AnyPublisher<Output, Never>) {
        self.ref = ref;
        self.parent = parent;
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
        guard let ref = self.ref else {
            return;
        }
        parent.receive(subscriber: Inner(ref: ref, downstream: subscriber));
    }

    private class Inner<Input, Downstream: Subscriber>: Subscriber where Downstream.Failure == Never, Downstream.Input == Input {
        
        public typealias Failure = Never;
        
        private let ref: AnyObject;
        private let downstream: Downstream;
        
        init(ref: AnyObject, downstream: Downstream) {
            self.ref = ref
            self.downstream = downstream;
        }
        
        func receive(subscription: Subscription) {
            downstream.receive(subscription: subscription);
        }
        
        func receive(_ input: Input) -> Subscribers.Demand {
            downstream.receive(input);
        }
        
        func receive(completion: Subscribers.Completion<Never>) {
            downstream.receive(completion: completion);
        }
    }
}

public class Contact: DisplayableIdProtocol {

    public let key: Key;
    
    @TigaseSwift.Published
    public var displayName: String;
    private var _displayNamePublisher: AnyPublisher<String, Never>!;
    public var displayNamePublisher: AnyPublisher<String, Never> {
        return _displayNamePublisher;
    }
    
    @TigaseSwift.Published
    public var status: Presence.Show?;
    private var _statusPublisher: AnyPublisher<Presence.Show?, Never>!;
    public var statusPublisher: AnyPublisher<Presence.Show?, Never> {
        return _statusPublisher;
    }
    
    @TigaseSwift.Published
    public var description: String?;
    private var _descriptionPublisher: AnyPublisher<String?,Never>!;
    public var descriptionPublisher: AnyPublisher<String?,Never> {
        return _descriptionPublisher;
    }
    
    public var avatar: AnyPublisher<NSImage?,Never> {
        return AvatarManager.instance.avatarPublisher(for: key).eraseToAnyPublisher();
    }

    public init(key: Key, displayName: String, status: Presence.Show?) {
        self.key = key;
        self.displayName = displayName;
        self.status = status;
        self._displayNamePublisher = KeepRefPublisher(ref: self, parent: $displayName.eraseToAnyPublisher()).eraseToAnyPublisher();
        self._statusPublisher = KeepRefPublisher(ref: self, parent: $status.eraseToAnyPublisher()).eraseToAnyPublisher();
        self._descriptionPublisher = KeepRefPublisher(ref: self, parent: $description.eraseToAnyPublisher()).eraseToAnyPublisher();
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
            return XmppService.instance.getClient(for: key.account)?.presenceStore?.getBestPresence(for: key.jid)?.show
        case .participant(let id):
            return XmppService.instance.getClient(for: key.account)?.presenceStore?.getBestPresence(for: BareJID(localPart: "\(id)#\(key.jid.localPart ?? "")", domain: key.jid.domain))?.show;
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
