//
//  ServerCertificateInfo.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 25/09/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class ServerCertificateInfo: SslCertificateInfo {
    
    var accepted: Bool;
    
    override init(trust: SecTrust) {
        self.accepted = false;
        super.init(trust: trust);
    }
    
    required init?(coder aDecoder: NSCoder) {
        accepted = aDecoder.decodeBool(forKey: "accepted");
        super.init(coder: aDecoder);
    }
    
    override func encode(with aCoder: NSCoder) {
        aCoder.encode(accepted, forKey: "accepted");
        super.encode(with: aCoder);
    }
    
}
