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

/// A configuration specifies important Dejavu behavior. A configuration is
/// needed to start a new session.
public final class DejavuSessionConfiguration: Sendable {
    /// A mode of operation for the Dejavu session.
    public enum Mode: Sendable {
        /// First deletes the cache, then records any network traffic to the
        /// cache.
        case cleanRecord
        /// Records any network traffic to the cache. Does not delete the
        /// database first.
        case supplementalRecord
        /// Intercepts requests and gets the responses from the cache.
        case playback
    }

    /// How instance counts should be handled when fetching requests
    public enum InstanceCountBehavior: Sendable, Equatable {
        /// Requires that instanceCount matches when fetching request, unless specified in urlsToIgnoreInstanceCount
        case strict
        /// If no request found matching instanceCount, fall back to first or last matching request
        case fallBackTo(_ request: FallbackRequest)

        public static func ==(lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.strict, .strict):
                return true
            case (.fallBackTo(let lhsFallbackRequest), .fallBackTo(let rhsFallbackRequest)):
                return lhsFallbackRequest == rhsFallbackRequest
            default:
                return false
            }
        }
    }

    /// When falling back to request that does not match instanceCount, we can fall back to first or last matching request
    public enum FallbackRequest: Sendable {
        case first
        case last
    }

    /// The location to store mock data.
    public let fileURL: URL
    /// The mode of operation for the Dejavu session.
    public let mode: Mode
    /// Observes network traffic during the session.
    public let networkObserver: DejavuNetworkObserver
    /// Intercepts network traffic during the session.
    public let networkInterceptor: DejavuNetworkInterceptor
    
    /// Replacements for query parameters.
    @preconcurrency public var queryParameterReplacements: [String: any Sendable] {
        get { state.withLock(\.queryParameterReplacements) }
        set { state.withLock { $0.queryParameterReplacements = newValue } }
    }
    /// Query parameters to be removed.
    public var queryParametersToRemove: [String] {
        get { state.withLock(\.queryParametersToRemove) }
        set { state.withLock { $0.queryParametersToRemove = newValue } }
    }
    /// Replacements for JSON key/value pairs.
    @preconcurrency public var jsonResponseKeyValueReplacements: [String: any Sendable] {
        get { state.withLock(\.jsonResponseKeyValueReplacements) }
        set { state.withLock { $0.jsonResponseKeyValueReplacements = newValue } }
    }
    /// JSON keys to be removed.
    public var jsonResponseKeyValuesToRemove: [String] {
        get { state.withLock(\.jsonResponseKeyValuesToRemove) }
        set { state.withLock { $0.jsonResponseKeyValuesToRemove = newValue } }
    }
    /// Replacements for header entries.
    @preconcurrency public var headerReplacements: [String: any Sendable] {
        get { state.withLock(\.headerReplacements) }
        set { state.withLock { $0.headerReplacements = newValue } }
    }
    /// Header entries to be removed.
    public var headersToRemove: [String] {
        get { state.withLock(\.headersToRemove) }
        set { state.withLock { $0.headersToRemove = newValue } }
    }
    /// A Boolean value indicating whether multipart request bodies should be
    /// ignored.
    public var ignoreMultipartRequestBody: Bool {
        get { state.withLock(\.ignoreMultipartRequestBody) }
        set { state.withLock { $0.ignoreMultipartRequestBody = newValue } }
    }
    
    /// Useful for situations where requests are made multiple times.
    ///
    /// Use this judiciously when problems arise with certain static tests where
    /// responses wouldn't change.
    public var urlsToIgnoreInstanceCount: [URL] {
        get { state.withLock(\.urlsToIgnoreInstanceCount) }
        set { state.withLock { $0.urlsToIgnoreInstanceCount = newValue } }
    }
    /// How instance counts should be handled when fetching requests
    public var instanceCountBehavior: InstanceCountBehavior {
        get { state.withLock(\.instanceCountBehavior) }
        set { state.withLock { $0.instanceCountBehavior = newValue } }
    }

    /// Authentication token parameter keys.
    public var authenticationTokenParameterKeys: [String] {
        get { state.withLock(\.authenticationTokenParameterKeys) }
        set { state.withLock { $0.authenticationTokenParameterKeys = newValue } }
    }
    /// Authentication header parameter keys.
    public var authenticationHeaderParameterKeys: [String] {
        get { state.withLock(\.authenticationHeaderParameterKeys) }
        set { state.withLock { $0.authenticationHeaderParameterKeys = newValue } }
    }
    
    private struct State: Sendable {
        /// Replacements for query parameters.
        var queryParameterReplacements: [String: any Sendable] = [:]
        /// Query parameters to be removed.
        var queryParametersToRemove: [String] = []
        /// Replacements for JSON key/value pairs.
        var jsonResponseKeyValueReplacements: [String: any Sendable] = [:]
        /// JSON keys to be removed.
        var jsonResponseKeyValuesToRemove: [String] = []
        /// Replacements for header entries.
        var headerReplacements: [String: any Sendable] = [:]
        /// Header entries to be removed.
        var headersToRemove: [String] = []
        /// A Boolean value indicating whether multipart request bodies should be ignored.
        var ignoreMultipartRequestBody = true
        
        /// Useful for situations where requests are made multiple times.
        ///
        /// Use this judiciously when
        /// problems arise with certain static tests where responses wouldn't change.
        var urlsToIgnoreInstanceCount: [URL] = []
        /// How instance counts should be handled when fetching requests
        var instanceCountBehavior: InstanceCountBehavior = .strict

        /// Authentication token parameter keys.
        var authenticationTokenParameterKeys: [String] = []
        /// Authentication header parameter keys.
        var authenticationHeaderParameterKeys: [String] = []
    }
    
    private let state = OSAllocatedUnfairLock(initialState: State())
    
    /// Creates a new Dejavu configuration.
    /// - Parameters:
    ///   - fileURL: The location to store mock data.
    ///   - mode: The mode of operation for the Dejavu session.
    public convenience init(fileURL: URL, mode: Mode) {
        self.init(
            fileURL: fileURL,
            mode: mode,
            networkObserver: URLProtocolNetworkObserver.shared,
            networkInterceptor: URLProtocolNetworkInterceptor.shared
        )
    }
    
    /// Creates a new Dejavu configuration.
    /// - Parameters:
    ///   - fileURL: The location to store mock data.
    ///   - mode: The mode of operation for the Dejavu session.
    ///   - networkObserver: Observes network traffic during the session.
    ///   - networkInterceptor: Intercepts network traffic during the session.
    public init(
        fileURL: URL,
        mode: Mode,
        networkObserver: DejavuNetworkObserver,
        networkInterceptor: DejavuNetworkInterceptor
    ) {
        self.fileURL = fileURL
        self.mode = mode
        self.networkObserver = networkObserver
        self.networkInterceptor = networkInterceptor
    }
    
    enum NormalizationMode {
        case request
        case response
        case headers
        case removeTokenParameters
    }
    
    func normalize(jsonObject: Any, mode: NormalizationMode) -> Any {
        return if let jsonArray = jsonObject as? [Any] {
            normalize(jsonArray: jsonArray, mode: mode)
        } else if let json = jsonObject as? [String: Any] {
            normalize(jsonDictionary: json, mode: mode)
        } else {
            jsonObject
        }
    }
    
    func normalize(jsonArray: [Any], mode: NormalizationMode) -> [Any] {
        return jsonArray.map {
            normalize(jsonObject: $0, mode: mode)
        }
    }
    
    /// Recursively normalizes the json
    func normalize(jsonDictionary: [String: Any], mode: NormalizationMode) -> [String: Any] {
        let toRemove: [String]
        let toReplace: [String: Any]
        
        switch mode {
        case .request:
            toRemove = queryParametersToRemove
            toReplace = queryParameterReplacements
        case .response:
            toRemove = jsonResponseKeyValuesToRemove
            toReplace = jsonResponseKeyValueReplacements
        case .headers:
            toRemove = headersToRemove
            toReplace = headerReplacements
        case .removeTokenParameters:
            toReplace = [String: Any]()
            toRemove = authenticationTokenParameterKeys
        }
        
        let filtered = jsonDictionary.filter { (key, _) in
            if toRemove.contains(key) {
                return false
            }
            return true
        }
        
        let replaced = filtered.map { (key: String, value: Any) -> (String, Any) in
            if let replace = toReplace[key] {
                return (key, replace)
            } else {
                return (key, normalize(jsonObject: value, mode: mode))
            }
        }
        
        return Dictionary(uniqueKeysWithValues: replaced)
    }
    
    func normalizeJsonData(data: Data?, mode: NormalizationMode) -> Data? {
        guard let data = data else {
            return nil
        }
        
        // first try to turn data into json
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
            let normalizedJsonObject = normalize(jsonObject: jsonObject, mode: mode)
            
            // turn json back into data
            if let normalizedData = try? JSONSerialization.data(withJSONObject: normalizedJsonObject, options: .sortedKeys) {
                return normalizedData
            }
        }
        
        return nil
    }
    
    func normalizeRequestBody(data: Data?, mode: NormalizationMode) -> Data? {
        guard let data = data else {
            return nil
        }
        
        // first try to turn data into json
        if let normalizedJsonData = normalizeJsonData(data: data, mode: mode) {
            return normalizedJsonData
        }
        
        if let dataString = String(data: data, encoding: .utf8),
            dataString.starts(with: MultipartRequestBody.prefix) {
            // Multipart post body that we can actually easily parse
            // These are the ones that have json data in them
            let multipartRequestBody = MultipartRequestBody(original: dataString, configuration: self)
            return multipartRequestBody.normalizedData()
        }
        
        // if that doesn't work, try to turn it into query params
        if let dataString = String(data: data, encoding: .utf8),
            let paramsString = dataString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed),
            var components = URLComponents(string: "http://dummy.com/path?" + paramsString),
            let queryItems = components.queryItems, !queryItems.isEmpty {
            let normalized = normalize(queryItems: queryItems, mode: mode)
            components.queryItems = normalized
            
            // remove the percent encoding for normalizing the body just so we can read it easier in the db
            if let normalizedBodyString = components.url?.query?.removingPercentEncoding,
                let normalizedBody = normalizedBodyString.data(using: .utf8) {
                return normalizedBody
            }
        }
        
        /// ASCII encoded strings with multipart bodies cannot be parsed.
        if data.isMultipartBody, ignoreMultipartRequestBody {
            // Return nil. Ignoring the filename portion of multipart request bodies is inconsistent.
            return nil
        }
        
        return data
    }
    
    func normalize(url: URL, mode: NormalizationMode) -> URL {
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = comps.queryItems {
            comps.queryItems = normalize(queryItems: queryItems, mode: mode)
            return comps.url!
        }
        return url
    }
    
    func queryContainsAuthenticationParameters(url: URL) -> Bool {
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = comps.queryItems {
            for qi in queryItems {
                if authenticationTokenParameterKeys.contains(qi.name) {
                    return true
                }
            }
        }
        return false
    }
    
    private func normalize(queryItems: [URLQueryItem], mode: NormalizationMode) -> [URLQueryItem] {
        // first sort the queryItems to maintain consistent order
        let sorted = queryItems.sorted { $0.name < $1.name }
        
        let toRemove: [String]
        let toReplace: [String: Any]
        
        switch mode {
        case .request:
            toRemove = queryParametersToRemove
            toReplace = queryParameterReplacements
        case .response:
            toRemove = jsonResponseKeyValuesToRemove
            toReplace = jsonResponseKeyValueReplacements
        case .headers:
            toRemove = headersToRemove
            toReplace = headerReplacements
        case .removeTokenParameters:
            toReplace = [String: Any]()
            toRemove = authenticationTokenParameterKeys
        }
        
        var normalized = [URLQueryItem]()
        for qi in sorted {
            if let replacementValue = toReplace[qi.name] {
                // replace value with configuration replacement value
                normalized.append(URLQueryItem(name: qi.name, value: String(describing: replacementValue)))
            } else if toRemove.contains(qi.name) {
                // don't add ones that are to be removed
                continue
            } else if let data = qi.value?.removingPercentEncoding?.data(using: .utf8),
                    let normalizedJsonData = normalizeJsonData(data: data, mode: mode),
                    let normalizedJsonString = String(data: normalizedJsonData, encoding: .utf8) {
                // if there is json in the query item value, then normalize that
                normalized.append(URLQueryItem(name: qi.name, value: normalizedJsonString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)))
            } else {
                normalized.append(qi)
            }
        }
        return normalized
    }
}

/// A configuration specifies important Dejavu behavior. A configuration is
/// needed to start a new session.
@available(*, deprecated, renamed: "DejavuSessionConfiguration")
public typealias DejavuConfiguration = DejavuSessionConfiguration

private struct MultipartRequestBody {
    static let newLine = "\r\n"
    static let doubleNewLine = newLine + newLine
    static let boundary = "--AaB03x"
    static let prefix = newLine + boundary
    
    struct Section {
        let contents: String
        let configuration: DejavuSessionConfiguration
        
        func normalized() -> String {
            let comps = contents.components(separatedBy: MultipartRequestBody.doubleNewLine)
            
            if comps.count == 2,
                let replacementValue = configuration.queryParameterReplacements.first(where: { key, _ in
                    return comps.first == MultipartRequestBody.newLine + "Content-Disposition: form-data; name=\"\(key)\""
                })?.value {
                // look for and replace multiline form data keys that configuration specifies to replace
                // as query parameter replacements
                let s = String(describing: replacementValue)
                return comps[0] + doubleNewLine + s + MultipartRequestBody.newLine
            } else if comps.count == 2, comps.first == MultipartRequestBody.newLine + "Content-Disposition: form-data; name=\"text\"",
                let possibleJsonData = comps[1].data(using: .utf8),
                let normalizedJsonData = configuration.normalizeJsonData(data: possibleJsonData, mode: .request),
                let normalizedJsonString = String(data: normalizedJsonData, encoding: .utf8) {
                // then try to parse the text as json
                return comps[0] + doubleNewLine + normalizedJsonString + MultipartRequestBody.newLine
            } else {
                return contents
            }
        }
    }
    
    let original: String
    let sections: [Section]
    let configuration: DejavuSessionConfiguration
    
    init(original: String, configuration: DejavuSessionConfiguration) {
        self.original = original
        
        var sections = [Section]()
        let sectionStrings = original.components(separatedBy: MultipartRequestBody.boundary)
        for sectionStr in sectionStrings {
            sections.append(Section(contents: sectionStr, configuration: configuration))
        }
        self.sections = sections
        
        self.configuration = configuration
    }
    
    func normalized() -> String {
        var s = String()
        for (i, section) in sections.enumerated() {
            s.append(section.normalized())
            if i != sections.count - 1 {
                // don't append boundary on last one
                s.append(MultipartRequestBody.boundary)
            }
        }
        return s
    }
    
    func normalizedData() -> Data {
        return normalized().data(using: .utf8)!
    }
}

extension Data {
    /// A Boolean value that indicates whether this data appears to be a multipart request body.
    /// Note: This only checks a small prefix because sometimes the whole data
    /// cannot be decoded into a string.
    var isMultipartBody: Bool {
        guard let prefixData = "\r\n--AaB03x".data(using: .ascii) else { return false }
        return range(of: prefixData)?.lowerBound == 0
    }
}
