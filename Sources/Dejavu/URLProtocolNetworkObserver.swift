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

public import Foundation

import os

public final class URLProtocolNetworkObserver: Sendable {
    public static let shared = URLProtocolNetworkObserver()
    public static let protocolClass: URLProtocol.Type = ObserverProtocol.self
    
    private init() {}
    
    private struct State: Sendable {
        var handler: (any DejavuNetworkObservationHandler)?
        var urlProtocolRegistrationHandler: (@Sendable (AnyClass) -> Void)?
        var urlProtocolUnregistrationHandler: (@Sendable (AnyClass) -> Void)?
    }
    
    private let state = OSAllocatedUnfairLock(initialState: State())
    
    var handler: (any DejavuNetworkObservationHandler)? { state.withLock(\.handler) }
    
    func setURLProtocolRegistrationHandler(_ handler: @escaping @Sendable (AnyClass) -> Void) {
        state.withLock { $0.urlProtocolRegistrationHandler = handler }
    }
    
    func setURLProtocolUnregistrationHandler(_ handler: @escaping @Sendable (AnyClass) -> Void) {
        state.withLock { $0.urlProtocolUnregistrationHandler = handler }
    }
}

extension URLProtocolNetworkObserver: DejavuNetworkObserver {
    public func startObserving(handler: any DejavuNetworkObservationHandler) {
        let urlProtocolRegistrationHandler = state.withLock { state in
            state.handler = handler
            return state.urlProtocolRegistrationHandler
        }
        let `class` = ObserverProtocol.self
        URLProtocol.registerClass(`class`)
        urlProtocolRegistrationHandler?(`class`)
    }
    
    public func stopObserving() {
        let urlProtocolUnregistrationHandler = state.withLock { state in
            state.handler = nil
            return state.urlProtocolUnregistrationHandler
        }
        let `class` = ObserverProtocol.self
        URLProtocol.unregisterClass(`class`)
        urlProtocolUnregistrationHandler?(`class`)
    }
}

final class ObserverProtocol: URLProtocol, @unchecked Sendable {
    static let session = URLSession(configuration: .ephemeral)
    private struct State {
        var dataTask: URLSessionDataTask?
    }
    
    private let state = OSAllocatedUnfairLock(initialState: State())
    
    override class func canInit(with request: URLRequest) -> Bool {
        let hasHandler = URLProtocolNetworkObserver.shared.handler != nil
        if !hasHandler {
            log("canInit called with no handler", type: .error)
        }
        return hasHandler
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = URLProtocolNetworkObserver.shared.handler else {
            log("startLoading called with no handler", type: .error)
            return
        }
        let request = self.request
        guard let client = self.client else { return }
        
        let identifier = UUID().uuidString
        handler.requestWillBeSent(identifier: identifier, request: request)
        
        let dataTask = Self.session.dataTask(with: request) { [handler] data, response, error in
            if let error {
                client.urlProtocol(self, didFailWithError: error)
                handler.requestFinished(identifier: identifier, result: .failure(error))
                return
            }
            
            guard let response else {
                let error = URLError(.badServerResponse)
                client.urlProtocol(self, didFailWithError: error)
                handler.requestFinished(identifier: identifier, result: .failure(error))
                return
            }
            
            let data = data ?? Data()
            handler.responseReceived(identifier: identifier, response: response)
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: data)
            client.urlProtocolDidFinishLoading(self)
            handler.requestFinished(identifier: identifier, result: .success(data))
        }
        state.withLock { $0.dataTask = dataTask }
        dataTask.resume()
    }
    
    override func stopLoading() {
        guard let dataTask = state.withLock({ $0.dataTask.take() }) else {
            return
        }
        dataTask.cancel()
    }
}
