//
//  StatusHelper.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 08.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class StatusHelper {
    
    public static func imageFor(status: Presence.Show?) -> NSImage {
        return NSImage(named: StatusHelper.imageNameFor(status: status))!;
    }
    
    fileprivate static func imageNameFor(status: Presence.Show?) -> NSImage.Name {
        if status == nil {
            return NSImage.statusNoneName;
        } else {
            switch status! {
            case .online, .chat:
                return NSImage.statusAvailableName;
            case .away, .xa:
                return NSImage.statusPartiallyAvailableName;
            case .dnd:
                return NSImage.statusUnavailableName;
            }
        }
    }
    
}
