//
// OpenSSL_AES_GCM_Engine.swift
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

import Foundation
import OpenSSL
import TigaseSwiftOMEMO

class OpenSSL_AES_GCM_Engine: AES_GCM_Engine {
    
    func encrypt(iv: Data, key: Data, message data: Data, output: UnsafeMutablePointer<Data>?, tag: UnsafeMutablePointer<Data>?) -> Bool {
        
        let ctx = EVP_CIPHER_CTX_new();
        
        EVP_EncryptInit_ex(ctx, key.count == 32 ? EVP_aes_256_gcm() : EVP_aes_128_gcm(), nil, nil, nil);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, Int32(iv.count), nil);
        iv.withUnsafeBytes({ (ivBytes: UnsafeRawBufferPointer) -> Void in
            key.withUnsafeBytes({ (keyBytes: UnsafeRawBufferPointer) -> Void in
                EVP_EncryptInit_ex(ctx, nil, nil, keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), ivBytes.baseAddress!.assumingMemoryBound(to: UInt8.self));
            })
        });
        EVP_CIPHER_CTX_set_padding(ctx, 1);
        
        var outbuf = Array(repeating: UInt8(0), count: data.count);
        var outbufLen: Int32 = 0;
        
        let encryptedBody = data.withUnsafeBytes { ( bytes) -> Data in
            EVP_EncryptUpdate(ctx, &outbuf, &outbufLen, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), Int32(data.count));
            return Data(bytes: &outbuf, count: Int(outbufLen));
        }
        
        EVP_EncryptFinal_ex(ctx, &outbuf, &outbufLen);
        
        var tagData = Data(count: 16);
        tagData.withUnsafeMutableBytes({ (bytes) -> Void in
            EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self));
        });
        
        EVP_CIPHER_CTX_free(ctx);
        
        tag?.initialize(to: tagData);
        output?.initialize(to: encryptedBody);
        return true;
    }
    
    func decrypt(iv: Data, key: Data, encoded payload: Data, auth tag: Data?, output: UnsafeMutablePointer<Data>?) -> Bool {
        
        let ctx = EVP_CIPHER_CTX_new();
        EVP_DecryptInit_ex(ctx, key.count == 32 ? EVP_aes_256_gcm() : EVP_aes_128_gcm(), nil, nil, nil);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, Int32(iv.count), nil);
        key.withUnsafeBytes({ (keyBytes) -> Void in
            iv.withUnsafeBytes({ (ivBytes) -> Void in
                EVP_DecryptInit_ex(ctx, nil, nil, keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), ivBytes.baseAddress!.assumingMemoryBound(to: UInt8.self));
            })
        })
        EVP_CIPHER_CTX_set_padding(ctx, 1);
        
        var auth = tag;
        var encoded = payload;
        if auth == nil {
            auth = payload.subdata(in: (payload.count - 16)..<payload.count);
            encoded = payload.subdata(in: 0..<(payload.count-16));
        }
        
        var outbuf = Array(repeating: UInt8(0), count: encoded.count);
        var outbufLen: Int32 = 0;
        let decoded = encoded.withUnsafeBytes({ (bytes) -> Data in
            EVP_DecryptUpdate(ctx, &outbuf, &outbufLen, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), Int32(encoded.count));
            return Data(bytes: &outbuf, count: Int(outbufLen));
        });
        
        if auth != nil {
            auth!.withUnsafeMutableBytes({ [count = auth!.count] (bytes: UnsafeMutableRawBufferPointer) -> Void in
                EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_CCM_SET_TAG, Int32(count), bytes.baseAddress!.assumingMemoryBound(to: UInt8.self));
            });
        }
        
        let ret = EVP_DecryptFinal_ex(ctx, &outbuf, &outbufLen);
        EVP_CIPHER_CTX_free(ctx);
        guard ret >= 0 else {
            print("authentication of encrypted message failed:", ret);
            return false;
        }
        
        output?.initialize(to: decoded);
        return true;
    }
    
}
