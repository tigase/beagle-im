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
import Martin

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

public actor KeyedTasksQueue {
    typealias Job = @Sendable () async throws -> Void
    
    private var queues: [BareJID: Task<Void,Error>] = [:]
    
    func schedule(for key: BareJID, operation: @escaping Job) async throws {
        if let prevTask = queues[key] {
            try? await prevTask.value
        }
        let task = Task(operation: operation);
        queues[key] = task;
        defer {
            if queues[key] == task {
                queues.removeValue(forKey: key);
            }
        }
        try await task.value;
    }
    
}

