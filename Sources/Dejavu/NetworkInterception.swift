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

/// A type that is able to intercept network requests and send back a programmed response.
@preconcurrency
public protocol DejavuNetworkInterceptor: Sendable {
    func startIntercepting(handler: DejavuNetworkInterceptionHandler)
    func stopIntercepting()
}

/// A type that can act as a delegate to a network interceptor.
@preconcurrency
public protocol DejavuNetworkInterceptionHandler: Sendable {
    func interceptRequest(_ request: URLRequest) async throws -> (data: Data, response: URLResponse)
}

extension GRDBSession: DejavuNetworkInterceptionHandler {
    func interceptRequest(_ request: URLRequest) async throws -> (data: Data, response: URLResponse) {
        let request = try Request(request: request, configuration: configuration)
        
        log("requesting: \(request.url)", category: .requesting, type: .info)
        
        let instanceCount = register(request)
        
        return try await withCheckedThrowingContinuation { continuation in
            dbQueue.asyncWriteWithoutTransaction { [configuration] db in
                do {
                    var foundRecord = try db.record(for: request, instanceCount: instanceCount, instanceCountBehavior: .strict)
                    
                    if foundRecord == nil {
                        // If can't find, then search for same authenticated request, but look for
                        // one in the cache that is authenticated in a different way.
                        foundRecord = try db.otherAuthenticatedRecord(for: request, instanceCount: instanceCount, configuration: configuration)
                        if foundRecord != nil {
                            log("could only find version of this request that was authenticated as well, but in a different way: \(request.originalUrl)", category: .matchingRequests, type: .error)
                        }
                    }
                    
                    if foundRecord == nil {
                        // If still can't find, then search for un-authenticated version of the request.
                        foundRecord = try db.unauthenticatedRecord(for: request, instanceCount: instanceCount, configuration: configuration)
                        if foundRecord != nil {
                            log("could only find unauthenticated version of this request: \(request.originalUrl)", category: .matchingRequests, type: .error)
                        }
                    }
                    
                    if foundRecord == nil {
                        // If still can't find, then check to see if it is a URL where the instanceCount can be ignored.
                        if self.configuration.urlsToIgnoreInstanceCount.contains(where: { request.url.absoluteString.contains($0.absoluteString) }) {
                            foundRecord = try db.record(for: request, instanceCount: instanceCount, instanceCountBehavior: .fallBackTo(.last))
                            log("could only find version of this request with a different instance count: \(request.originalUrl), requestedInstanceCount: \(instanceCount)", category: .matchingRequests, type: .error)
                        } else {
                            switch self.configuration.instanceCountBehavior {
                            case .strict:
                                log("could not find response, consider ignoring the instance count for: \(request.url), or changing 'instanceCountBehavior' to 'fallBackTo'")
                            case .fallBackTo(.last), .fallBackTo(.first):
                                foundRecord = try db.record(for: request, instanceCount: instanceCount, instanceCountBehavior: self.configuration.instanceCountBehavior)
                                log("could only find version of this request with a different instance count: \(request.originalUrl), requestedInstanceCount: \(instanceCount)", category: .matchingRequests, type: .error)
                            }
                        }
                    }
                    
                    if let requestRecord = foundRecord {
                        if let responseRecord = try db.response(for: requestRecord) {
                            let response = responseRecord.toHTTPURLResponse(url: request.originalUrl)
                            if let error = responseRecord.error {
                                continuation.resume(throwing: error)
                            } else if let data = responseRecord.data {
                                continuation.resume(returning: (data: data, response: response))
                            } else {
                                continuation.resume(throwing: DejavuError.internalError("No response or error was found for request"))
                            }
                        } else {
                            log("cannot find response in cache: \(request.originalUrl)", category: .matchingRequests)
                            continuation.resume(throwing: DejavuError.noMatchingResponseFoundInCache(requestUrl: request.url))
                        }
                    } else {
                        // see if the same request (already authenticated) exists
                        if let challenge = try self.findAuthenticatedRequest(database: db, request: request, instanceCount: instanceCount) {
                            log("returning auth error for request: \(request.originalUrl)", category: .matchingRequests)
                            continuation.resume(returning: challenge)
                        } else {
                            log("cannot find request in cache: \(request.originalUrl), instanceCount: \(instanceCount), hash: \(request.hashString), hca: \(request.headersContainAuthentication), qca: \(request.queryContainsAuthentication), bca: \(request.bodyContainsAuthentication), method: \(request.method ?? "null")", category: .matchingRequests, type: .error)
                            log("  - query \(request.originalUrl.query?.removingPercentEncoding ?? "") ", category: .matchingRequests)
                            var info: [AnyHashable: Any] = ["URL": request.url]
                            if let query = request.query {
                                info["query"] = query
                            }
                            if let body = request.body, let bodyString = String(data: body, encoding: .utf8) {
                                info["body"] = bodyString
                            }
                            NotificationCenter.default.post(name: DejavuSessionNotifications.didFailToFindRequestInCache, object: self, userInfo: info)
                            continuation.resume(throwing: DejavuError.noMatchingRequestFoundInCache(requestUrl: request.url))
                        }
                    }
                } catch {
                    continuation.resume(throwing: DejavuError.failedToFetchResponseInCache(error))
                }
            }
        }
    }
}
