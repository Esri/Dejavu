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

public protocol DejavuSession {
    var configuration: DejavuConfiguration { get }
    
    func clearCache()
}

internal protocol SessionInternal: DejavuSession {
    init(configuration: DejavuConfiguration)
    
    func register(request: Request) -> Int
    @discardableResult
    func unregister(request: Request) -> Int
    
    func record(request: Request, instanceCount: Int, response: HTTPURLResponse?, data: Data?, error: NSError?)
    func fetch(request: Request, completion: @escaping (URLResponse?, Data?, Error?) -> Void )
    
    func end()
}
