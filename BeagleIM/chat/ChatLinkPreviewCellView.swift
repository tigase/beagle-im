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
            if let value = oldValue {
                if #available(macOS 10.15, *) {
                    (value as! LPLinkView).metadata = LPLinkMetadata();
                }
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
    
    func set(item: ChatLinkPreview) {
        if #available(macOS 10.15, *) {
            var metadata = MetadataCache.instance.metadata(for: "\(item.id)");
            var isNew = false;
            let url = URL(string: item.url)!;

            if (metadata == nil) {
                metadata = LPLinkMetadata();
                metadata!.originalURL = url;
                isNew = true;
            }
            if self.linkView == nil {
                self.linkView = CustomLPLinkView(url: url);
                linkView?.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
                linkView?.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
                linkView?.translatesAutoresizingMaskIntoConstraints = false;
            };
            
            let linkView = self.linkView as! LPLinkView;
            linkView.metadata = metadata!;


            if isNew {
                MetadataCache.instance.generateMetadata(for: url, withId: "\(item.id)", completionHandler: { [weak linkView] meta1 in
                    guard let meta = meta1 else {
                        return;
                    }
                    linkView?.metadata = meta;
                })
            }
        }
    }
    
}

@available(macOS 10.15, *)
class CustomLPLinkView: LPLinkView {
    
    override var metadata: LPLinkMetadata {
        didSet {
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1.0, execute: {
                print("linkView:", self);
            })
        }
    }
}
