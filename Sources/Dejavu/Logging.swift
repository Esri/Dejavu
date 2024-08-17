// Copyright 2023 Esri
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

internal import os

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

/// Writes a message to the log.
/// - Parameters:
///   - message: The message to write to the log.
///   - category: The category the message belongs to.
///   - type: The log level to use in the unified logging system.
///   - file: The file containing the source that invoked the log.
func log(
    _ message: String,
    category: LoggingCategory? = nil,
    type: OSLogType = .debug,
    _ file: String = #file
) {
    let caller = file.components(separatedBy: "/").last!.components(separatedBy: ".").first!
    let logger = Logger(subsystem: Bundle.dejavuIdentifier, category: caller)
    
    let category = category.map { "[\($0)] - " } ?? ""
    
    switch type {
    case .debug:
        logger.debug("\(category)\(message)")
    case .error:
        logger.error("\(category)\(message)")
    case .fault:
        logger.fault("\(category)\(message)")
    case .info:
        logger.info("\(category)\(message)")
    default:
        logger.notice("\(category)\(message)")
    }
}
