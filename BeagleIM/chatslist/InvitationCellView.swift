//
//  InvitationCellView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 17/02/2020.
//  Copyright © 2020 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class InvitationCellView: NSTableCellView {
    
    @IBOutlet weak var avatar: AvatarView! {
           didSet {
               self.avatar?.appearance = NSAppearance(named: .darkAqua);
           }
       }
    @IBOutlet weak var label: NSTextField!;
    @IBOutlet weak var message: ChatCellViewMessage!;

}
