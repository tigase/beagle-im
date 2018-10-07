//
//  Alert.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 07/10/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import AVFoundation

class Alert {
    
    var icon: NSImage?;
    var messageText: String?;
    var informativeText: String?;
    
    var buttons: [NSButton] = [];
    
    @discardableResult
    func addButton(withTitle title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil);
        buttons.append(button);
        return button;
    }
    
    func run(completionHandler handler: @escaping (NSApplication.ModalResponse)->Void) {
        
        let windowController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "AlertWindowController") as! NSWindowController;
        let controller = windowController.contentViewController as! AlertViewController;
        controller.view.setFrameSize(NSSize(width: 420, height: 60.0));
        
        controller.iconView.image = icon ?? NSImage(named: NSImage.applicationIconName);
        controller.messageTextField.stringValue = messageText ?? "";
        controller.informativeTextField.stringValue = informativeText ?? "";
        if informativeText == nil {
            controller.informativeTextField.heightAnchor.constraint(equalToConstant: 0).isActive = true;
        }
        
        buttons.reversed().forEach { button in
            controller.buttonsStack.addView(button, in: .leading);
            button.target = controller;
            button.action = #selector(AlertViewController.buttonClicked);
        }
        for i in 1..<buttons.count {
            buttons[i].widthAnchor.constraint(equalTo: buttons[i-1].widthAnchor).isActive = true;
        }
        
        controller.completionHandler = handler;
        
        if let window = windowController.window {
            window.styleMask = NSWindow.StyleMask(rawValue: window.styleMask.rawValue |  NSWindow.StyleMask.nonactivatingPanel.rawValue | NSWindow.StyleMask.utilityWindow.rawValue)
            window.level = .modalPanel;
        }
        
        windowController.showWindow(self);
        windowController.window?.makeKeyAndOrderFront(nil);
        
        NSSpeechSynthesizer().startSpeaking(messageText ?? "");
    }

    
}

class AlertViewController: NSViewController {
    
    @IBOutlet var iconView: NSImageView!;
    @IBOutlet var messageTextField: NSTextField!;
    @IBOutlet var informativeTextField: NSTextField!;
    @IBOutlet var contentView: NSView!;
    @IBOutlet var buttonsStack: NSStackView!;
    
    var completionHandler: ((NSApplication.ModalResponse)->Void)?
    
    @objc func buttonClicked(_ sender: NSButton) {
        for i in 0..<buttonsStack.views.count {
            if buttonsStack.views[i] == sender {
                var result = NSApplication.ModalResponse.OK;
                switch (buttonsStack.views.count - 1) - i {
                case 0:
                    result = NSApplication.ModalResponse.alertFirstButtonReturn;
                case 1:
                    result = NSApplication.ModalResponse.alertSecondButtonReturn;
                case 2:
                    result = NSApplication.ModalResponse.alertThirdButtonReturn;
                default:
                    break;
                }
                
                callResult(result);
            }
        }
        callResult(NSApplication.ModalResponse.OK);
    }
    
    func callResult(_ result: NSApplication.ModalResponse) {
        guard let tmp = completionHandler else {
            return;
        }
        completionHandler = nil;
        
        self.view.window?.close();
        tmp(result);
    }
}
