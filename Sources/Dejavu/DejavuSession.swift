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

public enum DejavuSessionNotifications {
    public static let didFailToFindRequestInCache = Notification.Name("DejavuSessionNotifications.didFailToFindRequestInCache")
}

@preconcurrency
public protocol DejavuSession: Sendable {
    typealias Configuration = DejavuSessionConfiguration
    
    var configuration: Configuration { get }
}

struct DejavuNullSession: DejavuSession {
    let configuration: Configuration
    
    func clearCache() {}
}
