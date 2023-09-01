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
import GRDB

class GRDBSession: SessionInternal {
    static var serialQueue = DispatchQueue(
        label: "DejavuGRDBSession.serialQueue",
        qos: DispatchQoS.utility,
        attributes: [],
        autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit,
        target: nil
    )
    
    let configuration: DejavuConfiguration
    
    private var instanceCounts = [String: Int]()
    
    private var dbQueue: DatabaseQueue?
    
    required init(configuration: DejavuConfiguration) {
        log("Initializing Dejavu GRDB session: \(configuration.fileURL)", [.info, .beginEndSession])
        
        self.configuration = configuration
        
        GRDBSession.serialQueue.async {
            if configuration.mode == .playback {
                if FileManager.default.fileExists(atPath: configuration.fileURL.path) {
                    // Only try to open if the file exists. In playback mode, don't create a
                    // database if there isn't one.
                    self.dbQueue = try? DatabaseQueue(path: configuration.fileURL.path)
                }
            }
        }
    }
    
    func clearCache() {
        GRDBSession.serialQueue.sync {
            // if db file exists, then delete it
            if FileManager.default.fileExists(atPath: configuration.fileURL.path) {
                try? FileManager.default.removeItem(at: configuration.fileURL)
            }
        }
    }
    
    private func setupDBForRecording() {
        guard dbQueue == nil else { return }
        if configuration.mode == .cleanRecord {
            // if db file exists, then delete it
            if FileManager.default.fileExists(atPath: configuration.fileURL.path) {
                try? FileManager.default.removeItem(at: configuration.fileURL)
            }
            
            createDatabaseAndSchema()
        } else if configuration.mode == .supplementalRecord {
            if !FileManager.default.fileExists(atPath: configuration.fileURL.path) {
                // if database doesn't exist, create it
                createDatabaseAndSchema()
            } else {
                // otherwise open it
                dbQueue = try? DatabaseQueue(path: configuration.fileURL.path)
            }
        }
    }
    
    private func createDatabaseAndSchema() {
        // if db parent directory does not exist, then create it
        try? FileManager.default.createDirectory(
            at: configuration.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // create database
        dbQueue = try? DatabaseQueue(path: configuration.fileURL.path)
        
        // create requests table
        try? dbQueue?.inDatabase { db in
            try db.create(table: "requests") { t in
                t.column("id", .integer).primaryKey()
                t.column("url", .text).notNull()
                t.column("urlNoQuery", .text).notNull()
                t.column("query", .text)
                t.column("method", .text)
                t.column("body", .blob)
                t.column("headers", .blob)
                t.column("hash", .text).notNull()
                t.column("instance", .integer).notNull()
                t.column("headersContainAuthentication", .boolean).notNull()
                t.column("queryContainsAuthentication", .boolean).notNull()
                t.column("bodyContainsAuthentication", .boolean).notNull()
            }
        }
        
        // create response table
        try? dbQueue?.inDatabase { db in
            try db.create(table: "responses") { t in
                t.column("id", .integer).primaryKey()
                t.column("requestID", .integer).references("requests", column: "id", onDelete: .cascade, onUpdate: nil, deferred: false)
                t.column("data", .blob)
                t.column("headers", .blob)
                t.column("statusCode", .integer).notNull()
                t.column("failureErrorDomain", .text)
                t.column("failureErrorCode", .integer)
                t.column("failureErrorDescription", .text)
            }
        }
    }
    
    func register(request: Request) -> Int {
        // increment request count
        var instanceCount = self.instanceCounts[request.hashString] ?? 0
        instanceCount += 1
        self.instanceCounts[request.hashString] = instanceCount
        return instanceCount
    }
    
    @discardableResult
    func unregister(request: Request) -> Int {
        guard var instanceCount = self.instanceCounts[request.hashString] else {
            return 0
        }
        instanceCount -= 1
        self.instanceCounts[request.hashString] = instanceCount
        return instanceCount
    }
    
    func record(request: Request, instanceCount: Int, response: HTTPURLResponse?, data: Data?, error: NSError?) {
        GRDBSession.serialQueue.async {
            self.setupDBForRecording()
            self.dbQueue?.inDatabase { db in
                do {
                    // if request already exists
                    if let requestRecord = try? self.findRequest(database: db, request: request, instanceCount: instanceCount) {
                        guard let requestID = requestRecord.id else {
                            throw DejavuError.internalError("primary key column is null and it should not be")
                        }
                        
                        // if response already exists, update it
                        if let responseRecord = try? self.findResponse(database: db, requestRecord: requestRecord) {
                            responseRecord.updateResponse(response: response, data: data, error: error)
                            try responseRecord.update(db)
                        } else {
                            // no response in database for an existing request, this shouldn't happen
                            let responseRecord = ResponseRecord(response: response, requestID: requestID, data: data, error: error)
                            try responseRecord.insert(db)
                        }
                    } else {
                        if self.configuration.mode == .supplementalRecord {
                            // output to console - this can be helpful for trying to get
                            // supplemental recording to help tests pass consistently
                            log("Supplemental recording - recorded new request!", .recording)
                        }
                        
                        let requestRecord = RequestRecord(request: request, instance: Int64(instanceCount))
                        try requestRecord.insert(db)
                        
                        guard let requestID = requestRecord.id else {
                            throw DejavuError.internalError("primary key column is null and it should not be")
                        }
                        
                        let responseRecord = ResponseRecord(response: response, requestID: requestID, data: data, error: error)
                        try responseRecord.insert(db)
                    }
                } catch let error as NSError {
                    log("error inserting record: \(error)", .error)
                }
            }
        }
    }
    
    // swiftlint:disable cyclomatic_complexity
    
    func fetch(request: Request, completion: @escaping (URLResponse?, Data?, Error?) -> Void ) {
        log("requesting: \(request.url)", [.info, .requesting])
        
        GRDBSession.serialQueue.async {
            guard let dbQueue = self.dbQueue else {
                completion(nil, nil, DejavuError.cacheDoesNotExist(fileURL: self.configuration.fileURL))
                return
            }
            
            let instanceCount = self.register(request: request)
            
            dbQueue.inDatabase { db in
                do {
                    var foundRecord = try self.findRequest(database: db, request: request, instanceCount: instanceCount, requireMatchedInstance: true)
                    
                    if foundRecord == nil {
                        // if can't find, then search for same authenticated request, but look for
                        // one in the cache that is authenticated in a different way
                        foundRecord = try self.findOtherAuthenticatedRequest(database: db, request: request, instanceCount: instanceCount)
                        if foundRecord != nil {
                            log("could only find version of this request that was authenticated as well, but in a different way: \(request.originalUrl)", [.matchingRequests, .warning])
                        }
                    }
                    
                    if foundRecord == nil {
                        // if still can't find, then search for un-authenticated version of the request
                        foundRecord = try self.findUnauthenticatedRequest(database: db, request: request, instanceCount: instanceCount)
                        if foundRecord != nil {
                            log("could only find unauthenticated version of this request: \(request.originalUrl)", [.matchingRequests, .warning])
                        }
                    }
                    
                    if foundRecord == nil {
                        // if still can't find, then check to see if it is a URL where the instanceCount can be ignored
                        if self.configuration.urlsToIgnoreInstanceCount.contains(request.url) {
                            foundRecord = try self.findRequest(database: db, request: request, instanceCount: instanceCount, requireMatchedInstance: false)
                            log("could only find version of this request with a different instance count: \(request.originalUrl), requestedInstanceCount: \(instanceCount)", [.matchingRequests, .warning])
                        }
                    }
                    
                    guard let requestRecord = foundRecord else {
                        // see if the same request (already authenticated) exists
                        if let challenge = try self.findAuthenticatedRequest(database: db, request: request, instanceCount: instanceCount) {
                            log("returning auth error for request: \(request.originalUrl)", .matchingRequests)
                            completion(challenge.response, challenge.data, challenge.error)
                            return
                        }
                        
                        log("cannot find request in cache: \(request.originalUrl), instanceCount: \(instanceCount), hash: \(request.hashString), hca: \(request.headersContainAuthentication), qca: \(request.queryContainsAuthentication), bca: \(request.bodyContainsAuthentication), method: \(request.method ?? "null")", [.matchingRequests, .warning])
                        log("  - query \(request.originalUrl.query?.removingPercentEncoding ?? "") ", .matchingRequests)
                        var info: [AnyHashable: Any] = ["URL": request.url]
                        if let query = request.query {
                            info["query"] = query
                        }
                        if let body = request.body, let bodyString = String(data: body, encoding: .utf8) {
                            info["body"] = bodyString
                        }
                        NotificationCenter.default.post(name: DejavuSessionNotifications.didFailToFindRequestInCache, object: self, userInfo: info)
                        throw DejavuError.noMatchingRequestFoundInCache(requestUrl: request.url)
                    }
                    
                    guard let responseRecord = try self.findResponse(database: db, requestRecord: requestRecord) else {
                        log("cannot find response in cache: \(request.originalUrl)", .matchingRequests)
                        throw DejavuError.noMatchingResponseFoundInCache(requestUrl: request.url)
                    }
                    
                    let response = responseRecord.toHTTPURLResponse(url: request.originalUrl)
                    completion(response, responseRecord.data, responseRecord.error)
                } catch let mbError as DejavuError {
                    completion(nil, nil, mbError)
                } catch let error as NSError {
                    completion(nil, nil, DejavuError.failedToFetchResponseInCache(error))
                }
            }
        }
    }
    
    // swiftlint:enable cyclomatic_complexity
    
    private func findResponse(database: Database, requestRecord: RequestRecord) throws -> ResponseRecord? {
        return try ResponseRecord.filter(Column("requestID") == requestRecord.id).fetchOne(database)
    }
    
    private func findRequest(database: Database, request: Request, instanceCount: Int, requireMatchedInstance: Bool = true) throws -> RequestRecord? {
        // create a record, so that it will normalize and then it can be used find the desired one
        let tmp = RequestRecord(request: request, instance: Int64(instanceCount))
        
        var foundRecord = try RequestRecord.filter(
                Column("hash") == tmp.hash &&
                Column("instance") == tmp.instance &&
                Column("urlNoQuery") == tmp.urlNoQuery &&
                Column("query") == tmp.query &&
                Column("body") == tmp.body &&
                Column("method") == tmp.method
            ).fetchOne(database)
        
        if !requireMatchedInstance {
            // If one with the correct instance wasn't found,
            // then search for the last instance and return that.
            // This causes a lot of problems if not used judiciously.
            if foundRecord == nil {
                var foundRecords = try RequestRecord.filter(
                    Column("hash") == tmp.hash &&
                        Column("urlNoQuery") == tmp.urlNoQuery &&
                        Column("query") == tmp.query &&
                        Column("body") == tmp.body &&
                        Column("method") == tmp.method
                    ).fetchAll(database)
                foundRecords.sort { $0.instance < $1.instance }
                foundRecord = foundRecords.last
            }
        }
        
        return foundRecord
    }
    
    private func findOtherAuthenticatedRequest(database: Database, request: Request, instanceCount: Int) throws -> RequestRecord? {
        // Given an authenticated request, this method finds the same request, but authenticated a different way
        
        let tmp = RequestRecord(request: request, instance: Int64(instanceCount))
        
        if request.queryContainsAuthentication,
            let queryTokenRemoved = configuration.normalize(url: request.url, mode: .removeTokenParameters).query?.removingPercentEncoding {
            if let record = try RequestRecord.filter(
                Column("urlNoQuery") == tmp.urlNoQuery &&
                    Column("instance") == tmp.instance &&
                    Column("body") == tmp.body &&
                    Column("method") == tmp.method &&
                    Column("queryContainsAuthentication") == false &&
                    Column("query") == queryTokenRemoved &&
                    Column("headersContainAuthentication") == true // this is where to look for the request with token in headers
                ).fetchOne(database) {
                return record
            }
        }
        
        return nil
    }
    
    private func findUnauthenticatedRequest(database: Database, request: Request, instanceCount: Int) throws -> RequestRecord? {
        // Given an authenticated request, this method finds the same request, but not authenticated
        
        let tmp = RequestRecord(request: request, instance: Int64(instanceCount))
        
        if request.queryContainsAuthentication,
            let queryTokenRemoved = configuration.normalize(url: request.url, mode: .removeTokenParameters).query?.removingPercentEncoding {
            if let record = try RequestRecord.filter(
                Column("urlNoQuery") == tmp.urlNoQuery &&
                    Column("instance") == tmp.instance &&
                    Column("body") == tmp.body &&
                    Column("method") == tmp.method &&
                    Column("queryContainsAuthentication") == false &&
                    Column("query") == queryTokenRemoved
                ).fetchOne(database) {
                return record
            }
        }
        
        if request.bodyContainsAuthentication,
            let body = request.body,
            let bodyTokenRemoved = configuration.normalizeRequestBody(data: body, mode: .removeTokenParameters) {
            if let record = try RequestRecord.filter(
                Column("urlNoQuery") == tmp.urlNoQuery &&
                    Column("instance") == tmp.instance &&
                    Column("query") == tmp.query &&
                    Column("method") == tmp.method &&
                    Column("body") == bodyTokenRemoved &&
                    Column("bodyContainsAuthentication") == false
                ).fetchOne(database) {
                return record
            }
        }
        
        if request.headersContainAuthentication {
            if let record = try RequestRecord.filter(
                Column("urlNoQuery") == tmp.urlNoQuery &&
                    Column("instance") == tmp.instance &&
                    Column("query") == tmp.query &&
                    Column("body") == tmp.body &&
                    Column("method") == tmp.method &&
                    Column("headersContainAuthentication") == false
                ).fetchOne(database) {
                return record
            }
        }
        
        return nil
    }
    
    // swiftlint:disable cyclomatic_complexity
    
    func findAuthenticatedRequest(database: Database, request: Request, instanceCount: Int) throws -> (response: HTTPURLResponse?, data: Data?, error: Error?)? {
        // This method searches for a request in the database that is the same as the one
        // being searched for, but has already been authenticated.
        // If found, then return an authentication error.
        //
        // This helps with requests that go in different orders as they can be authenticated.
        
        // This code was for when tokens were sent in the body or query parameters
        //
        // create a record, so that it will normalize and then it can be used to find the desired one
        let tmp = RequestRecord(request: request, instance: Int64(instanceCount))
        
        if !request.queryContainsAuthentication {
            let records = try RequestRecord.filter(
                Column("urlNoQuery") == tmp.urlNoQuery &&
                    Column("body") == tmp.body &&
                    Column("method") == tmp.method &&
                    Column("queryContainsAuthentication") == true
                ).fetchAll(database)
            
            for r in records {
                guard let url = URL(string: r.url) else {
                    continue
                }
                // remove token parameters from record's query and see if it matches
                if let queryTokenRemoved = configuration.normalize(url: url, mode: .removeTokenParameters).query?.removingPercentEncoding {
                    if queryTokenRemoved == tmp.query {
                        return authenticationRequiredResponse(for: request)
                    }
                }
            }
        }
        
        if !request.bodyContainsAuthentication {
            let records = try RequestRecord.filter(
                Column("urlNoQuery") == tmp.urlNoQuery &&
                    Column("query") == tmp.query &&
                    Column("method") == tmp.method &&
                    Column("bodyContainsAuthentication") == true
                ).fetchAll(database)
            
            for r in records {
                // remove token parameters from record's body and see if it matches
                if let body = r.body, let bodyTokenRemoved = configuration.normalizeRequestBody(data: body, mode: .removeTokenParameters) {
                    if bodyTokenRemoved == tmp.body {
                        return authenticationRequiredResponse(for: request)
                    }
                }
            }
        }
        
        if !request.headersContainAuthentication {
            let rowCount = try RequestRecord.filter(
                Column("urlNoQuery") == tmp.urlNoQuery &&
                    Column("query") == tmp.query &&
                    Column("body") == tmp.body &&
                    Column("method") == tmp.method &&
                    Column("headersContainAuthentication") == true
                ).fetchCount(database)
            if rowCount > 0 {
                return authenticationRequiredResponse(for: request)
            }
        }
        
        return nil
    }
    
    // swiftlint:enable cyclomatic_complexity
    
    func authenticationRequiredResponse(for request: Request) -> (response: HTTPURLResponse?, data: Data?, error: Error?) {
        let response = HTTPURLResponse(url: request.originalUrl, statusCode: 403, httpVersion: nil, headerFields: [String: String]())
        let responseString = "{\"error\":{\"code\":403,\"details\":[],\"message\":\"You do not have permissions to access this resource or perform this operation.\",\"messageCode\":\"GWM_0003\"}}"
        let data = responseString.data(using: .utf8)
        return (response, data, nil)
    }
    
    func end() {
        // Let the queue clear out and finish it's work before ending.
        GRDBSession.serialQueue.sync {
            // Release any database memory
            self.dbQueue?.releaseMemory()
            log("Ending Dejavu GRDB session: \(self.configuration.fileURL)", [.info, .beginEndSession])
        }
    }
    
    class RequestRecord: Record {
        var id: Int64?
        var url: String
        var urlNoQuery: String
        var query: String?
        var method: String?
        var body: Data?
        var headers: Data?
        var hash: String
        var instance: Int64
        var headersContainAuthentication: Bool
        var queryContainsAuthentication: Bool
        var bodyContainsAuthentication: Bool
        
        /// The table name
        override class var databaseTableName: String {
            return "requests"
        }
        
        init(request: Request, instance: Int64) {
            self.url = request.url.absoluteString
            self.urlNoQuery = request.urlNoQuery.absoluteString
            self.method = request.method
            self.query = request.query
            self.body = request.body
            self.headers = request.headers
            self.hash = request.hashString
            self.headersContainAuthentication = request.headersContainAuthentication
            self.queryContainsAuthentication = request.queryContainsAuthentication
            self.bodyContainsAuthentication = request.bodyContainsAuthentication
            
            self.instance = instance
            
            super.init()
        }
        
        /// Initialize from a database row
        required init(row: Row) throws {
            id = row["id"]
            url = row["url"]
            urlNoQuery = row["urlNoQuery"]
            query = row["query"]
            method = row["method"]
            body = row["body"]
            headers = row["headers"]
            hash = row["hash"]
            instance = row["instance"]
            headersContainAuthentication = row["headersContainAuthentication"]
            queryContainsAuthentication = row["queryContainsAuthentication"]
            bodyContainsAuthentication = row["bodyContainsAuthentication"]
            try super.init(row: row)
        }
        
        /// The values persisted in the database
        override func encode(to container: inout PersistenceContainer) {
            container["id"] = id
            container["url"] = url
            container["urlNoQuery"] = urlNoQuery
            container["query"] = query
            container["method"] = method
            container["body"] = body
            container["headers"] = headers
            container["hash"] = hash
            container["instance"] = instance
            container["headersContainAuthentication"] = headersContainAuthentication
            container["queryContainsAuthentication"] = queryContainsAuthentication
            container["bodyContainsAuthentication"] = bodyContainsAuthentication
        }
        
        /// When relevant, update the record ID after a successful insertion.
        override func didInsert(_ inserted: InsertionSuccess) {
            id = inserted.rowID
        }
    }
    
    class ResponseRecord: Record {
        var id: Int64?
        var requestID: Int64
        var data: Data?
        var headers: Data?
        var statusCode: Int = 0
        var error: NSError?
        
        /// The table name
        override class var databaseTableName: String {
            return "responses"
        }
        
        init(response: HTTPURLResponse?, requestID: Int64, data: Data?, error: NSError?) {
            self.requestID = requestID
            self.data = data
            if let response = response {
                self.statusCode = response.statusCode
                self.headers = try? JSONSerialization.data(withJSONObject: response.allHeaderFields)
            }
            
            let isCancelledError = error?.domain == NSURLErrorDomain
                && (error?.code == NSUserCancelledError || error?.code == -999)
            
            // Don't record a user cancelled error. If recorded, behavior would be different on
            // playback, and things wouldn't work right.
            if !isCancelledError {
                self.error = error
            }
            
            super.init()
        }
        
        func updateResponse(response: HTTPURLResponse?, data: Data?, error: NSError?) {
            self.data = data
            if let response = response {
                self.statusCode = response.statusCode
                self.headers = try? JSONSerialization.data(withJSONObject: response.allHeaderFields)
            } else {
                self.statusCode = 0
                self.headers = nil
            }
            self.error = error
        }
        
        /// Initialize from a database row
        required init(row: Row) throws {
            id = row["id"]
            requestID = row["requestID"]
            data = row["data"]
            headers = row["headers"]
            statusCode = row["statusCode"]
            
            // code is nullable, but it won't cast to Int, just Int64
            if let domain = row["failureErrorDomain"] as? String,
                let code = row["failureErrorCode"] as? Int64 {
                var userInfo = [String: String]()
                if let description = row["failureErrorDescription"] as? String {
                    userInfo[NSLocalizedDescriptionKey] = description
                }
                error = NSError(domain: domain, code: Int(code), userInfo: userInfo)
            }
            
            try super.init(row: row)
        }
        
        /// The values persisted in the database
        override func encode(to container: inout PersistenceContainer) {
            container["id"] = id
            container["requestID"] = requestID
            container["data"] = data
            container["headers"] = headers
            container["statusCode"] = statusCode
            container["failureErrorDomain"] = error?.domain
            container["failureErrorCode"] = error?.code
            container["failureErrorDescription"] = error?.localizedDescription
        }
        
        /// When relevant, update the record ID after a successful insertion.
        override func didInsert(_ inserted: InsertionSuccess) {
            id = inserted.rowID
        }
        
        func toHTTPURLResponse(url: URL) -> HTTPURLResponse {
            var headerFields: [String: String]?
            
            if let headerData = self.headers {
                headerFields = (try? JSONSerialization.jsonObject(with: headerData)) as? [String: String]
            }
            
            let response = HTTPURLResponse(url: url, statusCode: self.statusCode, httpVersion: nil, headerFields: headerFields)!
            return response
        }
    }
}
