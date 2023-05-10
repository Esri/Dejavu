// Copyright 2023 Esri.

// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import CommonCrypto

internal extension Data {
    func hashSHA256() -> Data {
        let data = self
        var hashData = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        hashData.withUnsafeMutableBytes { (digestBytes: UnsafeMutableRawBufferPointer) in
            data.withUnsafeBytes { (messageBytes: UnsafeRawBufferPointer) in
                _ = CC_SHA256(messageBytes.baseAddress, CC_LONG(data.count), digestBytes.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return hashData
    }
    
    func hexString() -> String {
        return self.map { String(format: "%02hhx", $0) }.joined()
    }
    
    func hashSHA256String() -> String {
        return hashSHA256().hexString()
    }
}

internal extension String {
    func hashSHA256() -> String {
        return data(using: .utf8)!.hashSHA256String()
    }
}

internal extension URL {
    func removingQuery() -> URL {
        var urlComponents = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        urlComponents.query = nil
        return urlComponents.url!
    }
    
    var query: String? {
        if let urlComponents = URLComponents(url: self, resolvingAgainstBaseURL: false) {
            return urlComponents.query
        }
        return nil
    }
}

internal extension Dictionary where Key == String, Value == String {
    func toJSONData() throws -> Data {
        return try JSONSerialization.data(withJSONObject: self, options: [.sortedKeys])
    }
}

internal extension Dictionary where Key == String, Value == Any {
    func toJSONData() throws -> Data {
        return try JSONSerialization.data(withJSONObject: self, options: [.sortedKeys])
    }
}

internal extension Data {
    init(reading input: InputStream) {
        self.init()
        input.open()
        
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        while input.hasBytesAvailable {
            let read = input.read(buffer, maxLength: bufferSize)
            self.append(buffer, count: read)
        }
        buffer.deallocate()
        
        input.close()
    }
}

internal extension String {
    func replacingRegexMatches(pattern: String, substitutionTemplate: String = "") throws -> String {
        let regex = try NSRegularExpression(pattern: pattern, options: NSRegularExpression.Options.caseInsensitive)
        let range = NSRange(location: 0, length: self.count)
        let s = regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: substitutionTemplate)
        return s
    }
}
