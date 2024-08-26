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

/// A type that allows observing the network.
@preconcurrency
public protocol DejavuNetworkObserver: Sendable {
    func startObserving(handler: DejavuNetworkObservationHandler)
    func stopObserving()
}

/// A type that handles network observation events.
@preconcurrency
public protocol DejavuNetworkObservationHandler: Sendable {
    func requestWillBeSent(identifier: String, request: URLRequest)
    func responseReceived(identifier: String, response: URLResponse)
    func requestFinished(identifier: String, result: Result<Data, Error>)
}
