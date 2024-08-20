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

/// Wraps a URLRequest.
///
/// Adds things we need in Dejavu:
///  - good hash
///  - normalized values
///  - httpBody (stores it)
///  - etc...
struct Request {
    let urlRequest: URLRequest
    let originalUrl: URL
    let url: URL
    let urlNoQuery: URL
    let query: String?
    let method: String?
    let body: Data?
    let headers: Data?
    let configuration: DejavuConfiguration
    let headersContainAuthentication: Bool
    let queryContainsAuthentication: Bool
    let bodyContainsAuthentication: Bool
    let hashString: String
    
    init(request: URLRequest, configuration: DejavuConfiguration) throws {
        guard let originalUrl = request.url else {
            throw DejavuError.internalError("URLRequest object must have a non-nil url")
        }
        
        self.configuration = configuration
        self.urlRequest = request
        self.originalUrl = originalUrl
        
        self.url = configuration.normalize(url: originalUrl, mode: .request)
        queryContainsAuthentication = configuration.queryContainsAuthenticationParameters(url: originalUrl)
        
        self.urlNoQuery = self.url.removingQuery()
        
        // Remove percent encoding just to make it easier to read in the database
        self.query = self.url.query?.removingPercentEncoding
        
        self.method = request.httpMethod
        
        let originalBody = request.httpBody
        self.body = configuration.normalizeRequestBody(data: originalBody, mode: .request)
        
        // Easiest way to see if there is authentication parameters in the body
        // is to run the process to remove the token parameters,
        // then compare it to the original body size
        bodyContainsAuthentication = if let orig = self.body, let removed = configuration.normalizeRequestBody(data: orig, mode: .removeTokenParameters) {
            orig.count > removed.count
        } else {
            false
        }
        
        if let reqHeaders = request.allHTTPHeaderFields,
            let normalizedHeaders = configuration.normalize(jsonObject: reqHeaders, mode: .headers) as? [String: Any] {
            self.headers = try? normalizedHeaders.toJSONData()
            headersContainAuthentication = reqHeaders.contains { 
                configuration.authenticationHeaderParameterKeys.contains($0.key)
            }
        } else {
            self.headers = nil
            headersContainAuthentication = false
        }
        
        // Create a grand string representing our request, then sha256 hash it
        // all.
        
        let s = "url=" + urlNoQuery.absoluteString
        let q = "query=" + (query ?? "")
        let b = "body=" + (body?.hashSHA256String() ?? "")
        let hca = "headersContainAuthentication=" + (headersContainAuthentication ? "true" : "false")
        let m = "method=" + (method ?? "")
        hashString = [s, q, b, hca, m]
            .joined(separator: ",")
            .hashSHA256()
    }
}
