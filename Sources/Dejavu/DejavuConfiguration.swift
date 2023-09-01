// Copyright 2023 Esri
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

/// A configuration specifies important Dejavu behavior. A configuration is needed to start a
/// new session.
public class DejavuConfiguration {
    /// A mode of operation for the Dejavu session.
    public enum Mode {
        /// Requests and responses go out over the network as normal.
        case disabled
        /// First deletes the cache, then records any network traffic to the cache.
        case cleanRecord
        /// Records any network traffic to the cache. Does not delete the database first.
        case supplementalRecord
        /// Intercepts requests and gets the responses from the cache.
        case playback
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
    public var queryParameterReplacements: [String: Any] = [String: Any]()
    /// Query parameters to be removed.
    public var queryParametersToRemove: [String] = [String]()
    /// Replacements for JSON key/value pairs.
    public var jsonResponseKeyValueReplacements: [String: Any] = [String: Any]()
    /// JSON keys to be removed.
    public var jsonResponseKeyValuesToRemove: [String] = [String]()
    /// Replacements for header entries.
    public var headerReplacements: [String: Any] = [String: Any]()
    /// Header entries to be removed.
    public var headersToRemove: [String] = [String]()
    /// A Boolean value indicating whether multipart request bodies should be ignored.
    public var ignoreMultipartRequestBody = true
    
    /// Useful for situations where requests are made multiple times.
    ///
    /// Use this judiciously when
    /// problems arise with certain static tests where responses wouldn't change.
    public var urlsToIgnoreInstanceCount = [URL]()
    
    /// Authentication token parameter keys.
    public var authenticationTokenParameterKeys = [String]()
    /// Authentication header parameter keys.
    public var authenticationHeaderParameterKeys = [String]()
    
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
    
    internal enum NormalizationMode {
        case request
        case response
        case headers
        case removeTokenParameters
    }
    
    internal func normalize(jsonObject: Any, mode: NormalizationMode) -> Any {
        if let jsonArray = jsonObject as? [Any] {
            return normalize(jsonArray: jsonArray, mode: mode)
        } else if let json = jsonObject as? [String: Any] {
            return normalize(jsonDictionary: json, mode: mode)
        }
        return jsonObject
    }
    
    internal func normalize(jsonArray: [Any], mode: NormalizationMode) -> [Any] {
        return jsonArray.map {
            normalize(jsonObject: $0, mode: mode)
        }
    }
    
    /// Recursively normalizes the json
    internal func normalize(jsonDictionary: [String: Any], mode: NormalizationMode) -> [String: Any] {
        
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
    
    internal func normalizeJsonData(data: Data?, mode: NormalizationMode) -> Data? {
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
    
    internal func normalizeRequestBody(data: Data?, mode: NormalizationMode) -> Data? {
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
        if String(data: data, encoding: .ascii) != nil, ignoreMultipartRequestBody {
            // Return nil. Ignoring the filename portion of multipart request bodies is inconsistent.
            return nil
        }
        
        return data
    }
    
    internal func normalize(url: URL, mode: NormalizationMode) -> URL {
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = comps.queryItems {
            comps.queryItems = normalize(queryItems: queryItems, mode: mode)
            return comps.url!
        }
        return url
    }
    
    internal func queryContainsAuthenticationParameters(url: URL) -> Bool {
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

struct MultipartRequestBody {
    static let newLine = "\r\n"
    static let doubleNewLine = newLine + newLine
    static let boundary = "--AaB03x"
    static let prefix = newLine + boundary
    
    struct Section {
        let contents: String
        let configuration: DejavuConfiguration
        
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
    let configuration: DejavuConfiguration
    
    init(original: String, configuration: DejavuConfiguration) {
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
