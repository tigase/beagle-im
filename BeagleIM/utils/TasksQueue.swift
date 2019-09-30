//
// TasksQueue.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift

//class TasksQueue {
//
//    private let dispatcher = QueueDispatcher(label: "TasksQueue");
//    private var queue: [(()->Void)->Void] = [];
//    private var inProgress: Bool = false;
//
//    func schedule(task: @escaping (@escaping ()->Void)->Void) {
//        dispatcher.async {
//            self.queue.append(task);
//            self.execute();
//        }
//    }
//
//    private func execute() {
//        dispatcher.async {
//            guard !self.inProgress else {
//                return;
//            }
//            self.inProgress = true;
//            if !self.queue.isEmpty {
//                let task = self.queue.removeFirst();
//                task(self.executed);
//            }
//        }
//    }
//
//    private func executed() {
//        dispatcher.async {
//            self.inProgress = false;
//            self.execute();
//        }
//    }
//
//}

class KeyedTasksQueue {
    
    private let dispatcher = QueueDispatcher(label: "TasksQueue");
    private var queues: [BareJID:[Task]] = [:];
    private var inProgress: [BareJID] = [];
    
    func schedule(for key: BareJID, task: @escaping Task) {
        dispatcher.async {
            var queue = self.queues[key] ?? [];
            queue.append(task);
            self.queues[key] = queue;
            self.execute(for: key);
        }
    }
    
    private func execute(for key: BareJID) {
        dispatcher.async {
            guard !self.inProgress.contains(key) else {
                return;
            }
            if var queue = self.queues[key], !queue.isEmpty {
                self.inProgress.append(key);
                let task = queue.removeFirst();
                if queue.isEmpty {
                    self.queues.removeValue(forKey: key);
                } else {
                    self.queues[key] = queue;
                }
                task({
                    self.executed(for: key);
                })
            }
        }
    }
    
    private func executed(for key: BareJID) {
        dispatcher.async {
            self.inProgress = self.inProgress.filter({ (k) -> Bool in
                return k != key;
            });
            self.execute(for: key);
        }
    }
    
    typealias Task = (@escaping ()->Void) -> Void;
}
