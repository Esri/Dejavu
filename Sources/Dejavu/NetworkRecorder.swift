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

/// A type that allows observing the network.
public protocol DejavuNetworkObserver {
    func startObserving(handler: DejavuNetworkObservationHandler)
    func stopObserving()
}

/// A type that handles network observation events.
public protocol DejavuNetworkObservationHandler {
    func requestWillBeSent(identifier: String, request: URLRequest)
    func responseReceived(identifier: String, response: URLResponse)
    func requestFinished(identifier: String, result: Result<Data, Error>)
}

/// An object that records network traffic.
class NetworkRecorder {
    private struct Transaction {
        var request: URLRequest
        var dejavuRequest: Request
        var instanceCount: Int
        var response: URLResponse?
        var data: Data?
        var error: Error?
    }
    
    private let serialQueue = DispatchQueue(label: "DejavuNetworkRecorder", qos: .utility)
    
    private var transactions = [String: Transaction]()
    
    private(set) var session: SessionInternal?
    private(set) var networkObserver: DejavuNetworkObserver?
    
    static let shared = NetworkRecorder()
    
    private init() {}
    
    func enable(session: SessionInternal, networkObserver: DejavuNetworkObserver) {
        serialQueue.sync {
            self.session = session
            self.networkObserver = networkObserver
            self.networkObserver?.startObserving(handler: self)
        }
    }
    
    func disable() {
        serialQueue.sync {
            guard let session = session, let networkObserver = networkObserver else { return }
            networkObserver.stopObserving()
            
            if !transactions.isEmpty {
                log("disabled recorder while waiting on requests to finish...", [.recording, .warning])
                
                // If here, then the network recorder was disabled before all requests had the
                // chance to finish.
                // During recording, sometimes an object will fail to load as soon as an http
                // response is received with an error code, and the test will then end before
                // the request has a chance to finish loading with an error.
                // In this case, record what's been observed so far, which is most likely
                // just the response.
                while let (_, transaction) = transactions.popFirst() {
                    session.record(
                        request: transaction.dejavuRequest,
                        instanceCount: transaction.instanceCount,
                        response: transaction.response as? HTTPURLResponse,
                        data: transaction.data,
                        error: transaction.error as NSError?
                    )
                }
            }
            
            self.session = nil
            self.networkObserver = nil
        }
    }
}

extension NetworkRecorder: DejavuNetworkObservationHandler {
    func requestWillBeSent(identifier: String, request: URLRequest) {
        serialQueue.sync {
            log("requesting: \(request.url?.absoluteString ?? "")", [.info, .requesting])
            log("requestWillBeSent: \(identifier): \(request.url?.absoluteString ?? "")", .recording)
            
            guard let session = self.session else {
                return
            }
            
            guard let dejavuRequest = try? Request(request: request, configuration: session.configuration) else {
                return
            }
            
            let instance = session.register(request: dejavuRequest)
            transactions[identifier] = Transaction(request: request, dejavuRequest: dejavuRequest, instanceCount: instance)
        }
    }
    
    func responseReceived(identifier: String, response: URLResponse) {
        serialQueue.sync {
            log("responseReceived: \(identifier)", .recording)
            guard var t = transactions[identifier] else {
                return
            }
            t.response = response
            transactions[identifier] = t
        }
    }
    
    func requestFinished(identifier: String, result: Result<Data, Error>) {
        serialQueue.sync {
            defer {
                transactions[identifier] = nil
            }
            
            guard let session = self.session else {
                return
            }
            
            guard var t = transactions[identifier] else {
                return
            }
            
            switch result {
            case .success(let responseBody):
                log("loadingFinished: \(identifier)", .recording)
                // normalize the response
                t.data = session.configuration.normalizeJsonData(data: responseBody, mode: .response) ?? responseBody
                // record the response
                let response = t.response as? HTTPURLResponse
                session.record(request: t.dejavuRequest, instanceCount: t.instanceCount, response: response, data: t.data, error: nil)
            case .failure(let error):
                log("loadingFailed: \(identifier)", .recording)
                t.error = error
                let response = t.response as? HTTPURLResponse
                session.record(request: t.dejavuRequest, instanceCount: t.instanceCount, response: response, data: nil, error: error as NSError)
            }
        }
    }
}
