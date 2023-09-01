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

enum LoggingCategory: String {
    /// Matching requests in the database.
    case matchingRequests
    /// Fine grained recording information.
    case recording
    /// Session begin.
    case beginSession
    /// Session end.
    case endSession
    /// Requests as they go out (both playback/record modes).
    case requesting
}

func log(_ s: String, category: LoggingCategory? = nil, type: OSLogType = .debug, _ file: String = #file) {
    // The name of the file where the log originated.
    let caller = file.components(separatedBy: "/").last!.components(separatedBy: ".").first!
    let logger = Logger(subsystem: Bundle.dejavuIdentifier, category: caller)
    
    let category = category != nil ? "[\(category!)] - " : ""
    
    switch type {
    case .debug:
        logger.debug("\(category)\(s)")
    case .error:
        logger.error("\(category)\(s)")
    case .fault:
        logger.fault("\(category)\(s)")
    case .info:
        logger.info("\(category)\(s)")
    default:
        logger.notice("\(category)\(s)")
    }
}
