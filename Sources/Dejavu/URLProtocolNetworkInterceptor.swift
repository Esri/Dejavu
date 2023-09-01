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

/// A network interceptor that uses URLProtocol registration for network interception.
public class URLProtocolNetworkInterceptor: DejavuNetworkInterceptor {
    public static let shared = URLProtocolNetworkInterceptor()
    public static let protocolClass: URLProtocol.Type = InterceptorURLProtocol.self
    
    private init() {}
    
    private(set) var handler: DejavuNetworkInterceptionHandler?
    
    public func startIntercepting(handler: DejavuNetworkInterceptionHandler) {
        self.handler = handler
        registerURLProtocolClass(InterceptorURLProtocol.self)
    }
    
    public func stopIntercepting() {
        handler = nil
        unregisterURLProtocolClass(InterceptorURLProtocol.self)
    }
    
    private func registerURLProtocolClass(_ cls: AnyClass) {
        URLProtocol.registerClass(cls)
        urlProtocolRegistrationHandler?(cls)
    }
    
    private func unregisterURLProtocolClass(_ cls: AnyClass) {
        URLProtocol.unregisterClass(cls)
        urlProtocolUnregistrationHandler?(cls)
    }
    
    var urlProtocolRegistrationHandler: ((AnyClass) -> Void)?
    var urlProtocolUnregistrationHandler: ((AnyClass) -> Void)?
}

class InterceptorURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        let hasHandler = URLProtocolNetworkInterceptor.shared.handler != nil
        if !hasHandler {
            log("canInit called with no handler", .warning)
        }
        return hasHandler
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = URLProtocolNetworkInterceptor.shared.handler else {
            log("canInit called with no handler", .warning)
            return
        }
        
        handler.interceptRequest(request: request) { [weak self] result in
            guard let self = self,
                  let client = self.client else {
                return
            }
            switch result {
            case .success(let (data, response)):
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: URLCache.StoragePolicy.notAllowed)
                client.urlProtocol(self, didLoad: data)
                client.urlProtocolDidFinishLoading(self)
            case .failure(let error):
                client.urlProtocol(self, didFailWithError: error)
            }
        }
    }
    
    override func stopLoading() {}
}
