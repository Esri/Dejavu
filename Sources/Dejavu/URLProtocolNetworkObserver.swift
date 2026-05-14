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
        URLProtocol.registerClass(`class`)
        urlProtocolUnregistrationHandler?(`class`)
    }
}

final class ObserverProtocol: URLProtocol, @unchecked Sendable {
    static let session = URLSession(configuration: .ephemeral)

    private var dataTask: URLSessionDataTask?

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
            log("canInit called with no handler", type: .error)
            return
        }

        guard let client else { return }

        let identifier = UUID().uuidString
        let clientBridge = ClientBridge(client: client, urlProtocol: self)

        handler.requestWillBeSent(identifier: identifier, request: request)

        let dataTask = Self.session.dataTask(with: request) { [clientBridge, handler, identifier] data, response, error in
            if let response {
                handler.responseReceived(identifier: identifier, response: response)
                clientBridge.didReceive(response)
            }

            if let error {
                clientBridge.didFail(with: error)
                handler.requestFinished(identifier: identifier, result: .failure(error))
            } else if let data {
                clientBridge.didLoad(data)
                clientBridge.didFinishLoading()
                handler.requestFinished(identifier: identifier, result: .success(data))
            } else {
                let error = URLError(.badServerResponse)
                clientBridge.didFail(with: error)
                handler.requestFinished(identifier: identifier, result: .failure(error))
            }
        }

        self.dataTask = dataTask
        dataTask.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }
}

private struct ClientBridge: @unchecked Sendable {
    let client: any URLProtocolClient
    let urlProtocol: ObserverProtocol

    func didReceive(_ response: URLResponse) {
        client.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func didLoad(_ data: Data) {
        client.urlProtocol(urlProtocol, didLoad: data)
    }

    func didFinishLoading() {
        client.urlProtocolDidFinishLoading(urlProtocol)
    }

    func didFail(with error: any Error) {
        client.urlProtocol(urlProtocol, didFailWithError: error)
    }
}
