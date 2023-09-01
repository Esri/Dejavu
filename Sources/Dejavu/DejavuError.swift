// Copyright 2023 Esri.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

public enum DejavuError: Error {
    case internalError(String)
    case cacheDoesNotExist(fileURL: URL)
    case noMatchingRequestFoundInCache(requestUrl: URL) // code 2
    case noMatchingResponseFoundInCache(requestUrl: URL)
    case failedToFetchResponseInCache(Error)
    
    public var message: String {
        switch self {
        case .internalError(let message):
            return message
        case .noMatchingRequestFoundInCache(let requestUrl):
            return "No matching request found in the cache: \(requestUrl)"
        case .noMatchingResponseFoundInCache(let requestUrl):
            return "No matching response found in the cache for request \(requestUrl)"
        case .failedToFetchResponseInCache(let error):
            if let failureReason = (error as NSError).localizedFailureReason {
                return "Failed to fetch response in cache - " + error.localizedDescription + ": " + failureReason
            } else {
                return "Failed to fetch response in cache - " + error.localizedDescription
            }
        case .cacheDoesNotExist(let fileURL):
            return "Response cache does not exist at specified path: " + fileURL.path
        }
    }
}

extension DejavuError: CustomNSError {
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: message] }
}
