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
import OSLog

private let loggingIncludes: LoggingCategory = [.level2]

struct LoggingCategory: OptionSet, CustomDebugStringConvertible {
    let rawValue: Int
    
    static let info = LoggingCategory(rawValue: 1 << 0)
    static let warning = LoggingCategory(rawValue: 1 << 1)
    static let error = LoggingCategory(rawValue: 1 << 2)
    
    // for matching requests in the db
    static let matchingRequests = LoggingCategory(rawValue: 1 << 3)
    
    // fine grained recording information
    static let recording = LoggingCategory(rawValue: 1 << 4)
    
    static let beginEndSession = LoggingCategory(rawValue: 1 << 5)
    
    // for printing out the requests as they go out (both playback/record modes)
    static let requesting = LoggingCategory(rawValue: 1 << 6)
    
    var debugDescription: String {
        var arr = [String]()
        
        if self.contains(.info) {
            arr.append("[info]")
        }
        if self.contains(.warning) {
            arr.append("[warning]")
        }
        if self.contains(.error) {
            arr.append("[error]")
        }
        if self.contains(.matchingRequests) {
            arr.append("[matchingRequests]")
        }
        if self.contains(.recording) {
            arr.append("[recording]")
        }
        if self.contains(.beginEndSession) {
            arr.append("[beginEndSession]")
        }
        if self.contains(.requesting) {
            arr.append("[requesting]")
        }
        
        return arr.joined(separator: " ")
    }
    
    static let all: LoggingCategory = [.info, .warning, .error, .matchingRequests, .recording, .beginEndSession, .requesting]
    static let level1: LoggingCategory = [.warning, .error, .matchingRequests, .recording, .beginEndSession]
    static let level2: LoggingCategory = [.warning, .error]
}

internal func log(_ s: String, _ category: LoggingCategory, _ file: String = #file) {
    if !loggingIncludes.isDisjoint(with: category) {
        // The name of the file where the log originated.
        let caller = file.components(separatedBy: "/").last!.components(separatedBy: ".").first!
        let logger = Logger(subsystem: Bundle.dejavuIdentifier, category: caller)
        
        let level = category.intersection([.info, .warning, .error])
        let messageType = category.subtracting(level).debugDescription
        
        switch level {
        case .info:
            logger.info("\(messageType) - \(s)")
        case .warning:
            logger.warning("\(messageType) - \(s)")
        case .error:
            logger.error("\(messageType) - \(s)")
        default:
            logger.notice("\(messageType) - \(s)")
        }
    }
}
