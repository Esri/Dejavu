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

/// A type that is able to intercept network requests and send back a programmed response.
public protocol DejavuNetworkInterceptor {
    func startIntercepting(handler: DejavuNetworkInterceptionHandler)
    func stopIntercepting()
}

/// A type that can act as a delegate to a network interceptor.
public protocol DejavuNetworkInterceptionHandler {
    func interceptRequest(request: URLRequest, completion: @escaping (Result<(data: Data, response: URLResponse), Error>) -> Void)
}

/// A class that plays back responses for requests in the Dejavu environment.
class Player: DejavuNetworkInterceptionHandler {
    static let shared = Player()
    
    private init() {}
    
    private(set) var session: SessionInternal?
    private(set) var networkInterceptor: DejavuNetworkInterceptor?
    
    private let serialQueue = DispatchQueue(label: "DejavuPlayer", qos: .utility)
    
    func enable(session: SessionInternal, networkInterceptor: DejavuNetworkInterceptor) {
        serialQueue.sync {
            self.session = session
            self.networkInterceptor = networkInterceptor
            self.networkInterceptor?.startIntercepting(handler: self)
        }
    }
    
    func disable() {
        serialQueue.sync {
            self.session = nil
            self.networkInterceptor?.stopIntercepting()
        }
    }
    
    func interceptRequest(
        request: URLRequest,
        completion: @escaping (Result<(data: Data, response: URLResponse), Error>) -> Void
    ) {
        serialQueue.async {
            guard let session = Dejavu.currentSession as? SessionInternal else {
                log("startLoading called with no session", type: .error)
                return
            }
            
            guard let dejavuRequest = try? Request(request: request, configuration: session.configuration) else {
                return
            }
            
            session.fetch(request: dejavuRequest) { response, data, error in
                if let error = error {
                    completion(.failure(error))
                } else if let response = response {
                    let data = data ?? Data()
                    completion(.success((data: data, response: response)))
                } else {
                    completion(.failure(DejavuError.internalError("No response or error was found for request")))
                }
            }
        }
    }
}
