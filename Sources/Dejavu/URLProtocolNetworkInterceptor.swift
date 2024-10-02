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

/// A network interceptor that uses URLProtocol registration for network interception.
public final class URLProtocolNetworkInterceptor: Sendable {
    public static let shared = URLProtocolNetworkInterceptor()
    public static let protocolClass: URLProtocol.Type = InterceptorURLProtocol.self
    
    private init() {}
    
    private struct State: Sendable {
        var handler: DejavuNetworkInterceptionHandler?
        var urlProtocolRegistrationHandler: (@Sendable (AnyClass) -> Void)?
        var urlProtocolUnregistrationHandler: (@Sendable (AnyClass) -> Void)?
    }
    
    private let state = OSAllocatedUnfairLock(initialState: State())
    
    var handler: DejavuNetworkInterceptionHandler? { state.withLock(\.handler) }
    
    func setURLProtocolRegistrationHandler(_ handler: @escaping @Sendable (AnyClass) -> Void) {
        state.withLock { $0.urlProtocolRegistrationHandler = handler }
    }
    
    func setURLProtocolUnregistrationHandler(_ handler: @escaping @Sendable (AnyClass) -> Void) {
        state.withLock { $0.urlProtocolUnregistrationHandler = handler }
    }
}

extension URLProtocolNetworkInterceptor: DejavuNetworkInterceptor {
    public func startIntercepting(handler: DejavuNetworkInterceptionHandler) {
        let urlProtocolRegistrationHandler = state.withLock { state in
            state.handler = handler
            return state.urlProtocolRegistrationHandler
        }
        let `class` = InterceptorURLProtocol.self
        URLProtocol.registerClass(`class`)
        urlProtocolRegistrationHandler?(`class`)
    }
    
    public func stopIntercepting() {
        let urlProtocolUnregistrationHandler = state.withLock { state in
            state.handler = nil
            return state.urlProtocolUnregistrationHandler
        }
        let `class` = InterceptorURLProtocol.self
        URLProtocol.unregisterClass(`class`)
        urlProtocolUnregistrationHandler?(`class`)
    }
}

final class InterceptorURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        let hasHandler = URLProtocolNetworkInterceptor.shared.handler != nil
        if !hasHandler {
            log("canInit called with no handler", type: .error)
        }
        return hasHandler
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = URLProtocolNetworkInterceptor.shared.handler else {
            log("canInit called with no handler", type: .error)
            return
        }
        Task.detached { [request, weak self] in
            let result = await Task { try await handler.interceptRequest(request) }.result
            
            guard let self,
                  let client else {
                return
            }
            
            switch result {
            case .success(let (data, response)):
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(self, didLoad: data)
                client.urlProtocolDidFinishLoading(self)
            case .failure(let error):
                client.urlProtocol(self, didFailWithError: error)
            }
        }
    }
    
    override func stopLoading() {}
}
