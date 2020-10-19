//
// ChatLinkPreviewCellView.swift
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
import LinkPresentation

class ChatLinkPreviewCellView: NSTableCellView {
    
    var linkView: NSView? {
        didSet {
            if #available(macOS 10.15, *) {
                if let value = oldValue as? LPLinkViewPool.PoolableLPLinkView {
                    LPLinkViewPool.instance.release(linkView: value);
                    value.removeFromSuperview();
                }
                if let value = linkView {
                    self.addSubview(value);
                    NSLayoutConstraint.activate([
                        value.topAnchor.constraint(equalTo: self.topAnchor, constant: 0),
                        value.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -4),
                        value.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 40),
                        value.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: -26)
                    ]);
                }
            }
        }
    }
    
    deinit {
        if #available(macOS 10.15, *) {
            if let linkView = self.linkView as? LPLinkViewPool.PoolableLPLinkView {
                LPLinkViewPool.instance.release(linkView: linkView);
            }
        }
    }

    func set(item: ChatLinkPreview, fetchPreviewIfNeeded: Bool) {
        self.linkView = nil;
        if #available(macOS 10.15, *) {
            var metadata = MetadataCache.instance.metadata(for: "\(item.id)");
            var isNew = false;
            let url = URL(string: item.url)!;

            if (metadata == nil) {
                metadata = LPLinkMetadata();
                metadata!.originalURL = url;
                isNew = true;
            }
            let linkView = LPLinkViewPool.instance.acquire(url: url);
            linkView.translatesAutoresizingMaskIntoConstraints = false;
            linkView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
            linkView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
            
            linkView.metadata = metadata!;

            self.linkView = linkView;

            if isNew && fetchPreviewIfNeeded {
                MetadataCache.instance.generateMetadata(for: url, withId: "\(item.id)", completionHandler: { [weak linkView] meta1 in
                    guard let meta = meta1 else {
                        return;
                    }
                    DispatchQueue.main.async {
                        guard let linkView = linkView, linkView.metadata.originalURL == url else {
                            return;
                        }
                        linkView.metadata = meta;
                    }
                })
            }
        }
    }

}

/// Custom class for delaying release/deinit of LPLinkView to deal with crashes when LPLinkView with a movie is being released too soon.
@available(macOS 10.15, *)
class LPLinkViewPool {
    
    class Item {
        let linkView: LPLinkView;
        var isInUse: Bool;
        
        init(linkView: LPLinkView) {
            self.linkView = linkView;
            self.isInUse = true;
        }
    }
    
    static let instance = LPLinkViewPool();
    
    private var pool: [PoolableLPLinkView] = [];
    
    func acquire(url: URL) -> PoolableLPLinkView {
        return acquire({ PoolableLPLinkView(url: url) });
    }
    
    func acquire(metadata: LPLinkMetadata) -> PoolableLPLinkView {
        return acquire({ PoolableLPLinkView(metadata: metadata) });
    }
    
    private func acquire(_ supplier: ()-> PoolableLPLinkView) -> PoolableLPLinkView {
        if let item = pool.first(where: { !$0.isInUse }) {
            item.isInUse = true;
            return item;
        } else {
            let item = supplier();
            pool.append(item);
            return item;
        }
    }
    
    func release(linkView: PoolableLPLinkView) {
        linkView.metadata = LPLinkMetadata();
        linkView.isInUse = false;
    }

    private func remove(linkView: PoolableLPLinkView) {
        self.pool.removeAll(where: { $0 === linkView });
    }
    
    class PoolableLPLinkView: LPLinkView {
        
        private var timer: Timer?;
        
        var isInUse: Bool = true {
            didSet {
                if isInUse {
                    timer?.invalidate();
                    timer = nil;
                } else {
                    timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false, block: { _ in
                        LPLinkViewPool.instance.remove(linkView: self);
                    });
                }
            }
        }
        
        override init(url: URL) {
            super.init(url: url);
        }

        override init(metadata: LPLinkMetadata) {
            super.init(metadata: metadata);
        }
    }
}
