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

public class URLProtocolNetworkObserver: DejavuNetworkObserver {
    public static let shared = URLProtocolNetworkObserver()
    public static let protocolClass: URLProtocol.Type = ObserverProtocol.self
    
    private init() {}
    
    private(set) var handler: DejavuNetworkObservationHandler?
    
    public func startObserving(handler: DejavuNetworkObservationHandler) {
        self.handler = handler
        registerURLProtocolClass(ObserverProtocol.self)
    }
    
    public func stopObserving() {
        handler = nil
        unregisterURLProtocolClass(ObserverProtocol.self)
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

class ObserverProtocol: URLProtocol {
    static let session = URLSession(configuration: .ephemeral)
    
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
        
        guard let client = self.client else { return }
        
        Task.detached { [self] in
            let identifier = UUID().uuidString
            handler.requestWillBeSent(identifier: identifier, request: request)
            
            do {
                let (data, response) = try await Self.session.data(for: request)
                handler.responseReceived(identifier: identifier, response: response)
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: URLCache.StoragePolicy.notAllowed)
                client.urlProtocol(self, didLoad: data)
                client.urlProtocolDidFinishLoading(self)
                handler.requestFinished(identifier: identifier, result: .success(data))
            } catch {
                client.urlProtocol(self, didFailWithError: error)
                handler.requestFinished(identifier: identifier, result: .failure(error))
            }
        }
    }
    
    override func stopLoading() {}
}
