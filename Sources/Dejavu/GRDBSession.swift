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

internal import GRDB
internal import os

final class GRDBSession: DejavuSession, @unchecked Sendable {
    let configuration: DejavuSessionConfiguration
    
    private struct State {
        var instanceCounts: [String: Int] = [:]
        var transactions: [String: Transaction] = [:]
        
        mutating func register(_ request: Request) -> Int {
            var instanceCount = instanceCounts[request.hashString, default: 0]
            instanceCount += 1
            instanceCounts[request.hashString] = instanceCount
            return instanceCount
        }
        
        @discardableResult
        mutating func unregister(_ request: Request) -> Int {
            guard var instanceCount = instanceCounts[request.hashString] else {
                return 0
            }
            instanceCount -= 1
            instanceCounts[request.hashString] = instanceCount
            return instanceCount
        }
    }
    
    private let state = OSAllocatedUnfairLock(initialState: State())
    
    let dbQueue: DatabaseQueue
    
    required init(configuration: DejavuSessionConfiguration) throws {
        log("Initializing Dejavu GRDB session: \(configuration.fileURL)", category: .beginSession, type: .info)
        
        lazy var temporaryURL = URL.temporaryDirectory
            .appending(component: ProcessInfo().globallyUniqueString)
        
        switch configuration.mode {
        case .cleanRecord:
            dbQueue = try Self.makeDatabaseAndSchema(fileURL: temporaryURL)
        case .supplementalRecord:
            if FileManager.default.fileExists(at: configuration.fileURL) {
                try FileManager.default.copyItem(
                    at: configuration.fileURL,
                    to: temporaryURL
                )
                dbQueue = try DatabaseQueue(fileURL: temporaryURL)
            } else {
                dbQueue = try Self.makeDatabaseAndSchema(fileURL: temporaryURL)
            }
        case .playback:
            if FileManager.default.fileExists(at: configuration.fileURL) {
                // Only try to open if the file exists. In playback mode, don't
                // create a database if there isn't one.
                dbQueue = try DatabaseQueue(fileURL: configuration.fileURL)
            } else {
                dbQueue = try Self.makeDatabaseAndSchema(fileURL: temporaryURL)
            }
        }
        
        self.configuration = configuration
    }
    
    func clearCache() {
        // If db file exists, then delete it.
        try? FileManager.default.removeItem(at: configuration.fileURL)
    }
    
    private static func makeDatabaseAndSchema(fileURL: URL) throws -> DatabaseQueue {
        // if db parent directory does not exist, then create it
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // Create database.
        let dbQueue = try DatabaseQueue(fileURL: fileURL)
        
        // Create requests table.
        try dbQueue.inDatabase { db in
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
        
        // Create response table.
        try dbQueue.inDatabase { db in
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
        
        return dbQueue
    }
    
    func register(_ request: Request) -> Int {
        return state.withLock { $0.register(request) }
    }
    
    @discardableResult
    func unregister(_ request: Request) -> Int {
        return state.withLock { $0.unregister(request) }
    }
    
    func record(_ request: Request, instanceCount: Int, response: HTTPURLResponse?, data: Data?, error: Error?) {
        dbQueue.asyncWriteWithoutTransaction { db in
            do {
                // if request already exists
                if let requestRecord = try? db.record(for: request, instanceCount: instanceCount) {
                    guard let requestID = requestRecord.id else {
                        throw DejavuError.internalError("primary key column is null and it should not be")
                    }
                    
                    // if response already exists, update it
                    if let responseRecord = try? db.response(for: requestRecord) {
                        responseRecord.updateResponse(response: response, data: data, error: error as NSError?)
                        try responseRecord.update(db)
                    } else {
                        // no response in database for an existing request, this shouldn't happen
                        let responseRecord = ResponseRecord(response: response, requestID: requestID, data: data, error: error as NSError?)
                        try responseRecord.insert(db)
                    }
                } else {
                    if self.configuration.mode == .supplementalRecord {
                        // output to console - this can be helpful for trying to get
                        // supplemental recording to help tests pass consistently
                        log("Supplemental recording - recorded new request!", category: .recording)
                    }
                    
                    let requestRecord = RequestRecord(request: request, instance: Int64(instanceCount))
                    try requestRecord.insert(db)
                    
                    guard let requestID = requestRecord.id else {
                        throw DejavuError.internalError("primary key column is null and it should not be")
                    }
                    
                    let responseRecord = ResponseRecord(response: response, requestID: requestID, data: data, error: error as NSError?)
                    try responseRecord.insert(db)
                }
            } catch {
                log("error inserting record: \(error)", type: .error)
            }
        }
    }
    
    func findAuthenticatedRequest(database: Database, request: Request, instanceCount: Int) throws -> (data: Data, response: URLResponse)? {
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
            let records = try RequestRecord
                .filter(
                    Column("urlNoQuery") == tmp.urlNoQuery
                    && Column("body") == tmp.body
                    && Column("method") == tmp.method
                    && Column("queryContainsAuthentication") == true
                )
                .fetchAll(database)
            
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
            let records = try RequestRecord
                .filter(
                    Column("urlNoQuery") == tmp.urlNoQuery
                    && Column("query") == tmp.query
                    && Column("method") == tmp.method
                    && Column("bodyContainsAuthentication") == true
                )
                .fetchAll(database)
            
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
            let rowCount = try RequestRecord
                .filter(
                    Column("urlNoQuery") == tmp.urlNoQuery
                    && Column("query") == tmp.query
                    && Column("body") == tmp.body
                    && Column("method") == tmp.method
                    && Column("headersContainAuthentication") == true
                )
                .fetchCount(database)
            if rowCount > 0 {
                return authenticationRequiredResponse(for: request)
            }
        }
        
        return nil
    }
    
    func authenticationRequiredResponse(for request: Request) -> (data: Data, response: URLResponse)? {
        guard let response = HTTPURLResponse(url: request.originalUrl, statusCode: 403, httpVersion: nil, headerFields: [:]) else {
            return nil
        }
        let data = Data(
            #"{"error":{"code":403,"details":[],"message":"You do not have permissions to access this resource or perform this operation.","messageCode":"GWM_0003"}}"#.utf8
        )
        return (data: data, response: response)
    }
    
    func begin() {
        switch configuration.mode {
        case .playback:
            configuration.networkInterceptor.startIntercepting(handler: self)
        case .cleanRecord, .supplementalRecord:
            configuration.networkObserver.startObserving(handler: self)
        }
    }
    
    func end() {
        log("Ending Dejavu GRDB session: \(configuration.fileURL)", category: .endSession, type: .info)
        
        // Let the queue clear out and finish it's work before ending.
        dbQueue.releaseMemory()
        
        switch configuration.mode {
        case .cleanRecord, .supplementalRecord:
            let networkObserver = configuration.networkObserver
            networkObserver.stopObserving()
            
            let remainingTransactions = state.withLock { state in
                let transactions = state.transactions
                state.transactions.removeAll()
                return transactions
            }
            if !remainingTransactions.isEmpty {
                log("disabled recorder while waiting on requests to finish...", category: .recording, type: .error)
                
                // If here, then the network recorder was disabled before all requests had the
                // chance to finish.
                // During recording, sometimes an object will fail to load as soon as an http
                // response is received with an error code, and the test will then end before
                // the request has a chance to finish loading with an error.
                // In this case, record what's been observed so far, which is most likely
                // just the response.
                for transaction in remainingTransactions.values {
                    record(
                        transaction.dejavuRequest,
                        instanceCount: transaction.instanceCount,
                        response: transaction.response as? HTTPURLResponse,
                        data: transaction.data,
                        error: transaction.error
                    )
                }
            }
            
            do {
                try FileManager.default.moveItem(
                    at: dbQueue.url,
                    to: configuration.fileURL
                )
            } catch {
                _ = try? FileManager.default.replaceItemAt(
                    configuration.fileURL,
                    withItemAt: configuration.fileURL
                )
            }
        case .playback:
            configuration.networkInterceptor.stopIntercepting()
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
                var userInfo: [String: String] = [:]
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

extension GRDBSession /* Transactions */ {
    struct Transaction: Sendable {
        var request: URLRequest
        var dejavuRequest: Request
        var instanceCount: Int
        var response: URLResponse?
        var data: Data?
        var error: Error?
    }
}

extension GRDBSession: DejavuNetworkObservationHandler {
    func requestWillBeSent(identifier: String, request: URLRequest) {
        log("requesting: \(request.url?.absoluteString ?? "")", category: .requesting, type: .info)
        log("requestWillBeSent: \(identifier): \(request.url?.absoluteString ?? "")", category: .recording)
        
        guard let dejavuRequest = try? Request(request: request, configuration: configuration) else {
            return
        }
        
        state.withLock { state in
            let instance = state.register(dejavuRequest)
            state.transactions[identifier] = Transaction(request: request, dejavuRequest: dejavuRequest, instanceCount: instance)
        }
    }
    
    func responseReceived(identifier: String, response: URLResponse) {
        log("responseReceived: \(identifier)", category: .recording)
        state.withLock { state in
            guard var transaction = state.transactions[identifier] else {
                return
            }
            transaction.response = response
            state.transactions[identifier] = transaction
        }
    }
    
    func requestFinished(identifier: String, result: Result<Data, Error>) {
        guard var transaction = state.withLock({ $0.transactions.removeValue(forKey: identifier) }) else {
            return
        }
        
        switch result {
        case .success(let responseBody):
            log("loadingFinished: \(identifier)", category: .recording)
            // normalize the response
            transaction.data = configuration.normalizeJsonData(data: responseBody, mode: .response) ?? responseBody
            // record the response
            let response = transaction.response as? HTTPURLResponse
            record(transaction.dejavuRequest, instanceCount: transaction.instanceCount, response: response, data: transaction.data, error: nil)
        case .failure(let error):
            log("loadingFailed: \(identifier)", category: .recording)
            transaction.error = error
            let response = transaction.response as? HTTPURLResponse
            record(transaction.dejavuRequest, instanceCount: transaction.instanceCount, response: response, data: nil, error: error)
        }
    }
}

extension Database {
    func record(for request: Request, instanceCount: Int, requireMatchedInstance: Bool = true) throws -> GRDBSession.RequestRecord? {
        // create a record, so that it will normalize and then it can be used find the desired one
        let tmp = GRDBSession.RequestRecord(request: request, instance: Int64(instanceCount))
        
        var foundRecord = try GRDBSession.RequestRecord
            .filter(
                Column("hash") == tmp.hash
                && Column("instance") == tmp.instance
                && Column("urlNoQuery") == tmp.urlNoQuery
                && Column("query") == tmp.query
                && Column("body") == tmp.body
                && Column("method") == tmp.method
            )
            .fetchOne(self)
        
        if !requireMatchedInstance {
            // If one with the correct instance wasn't found,
            // then search for the last instance and return that.
            // This causes a lot of problems if not used judiciously.
            if foundRecord == nil {
                var foundRecords = try GRDBSession.RequestRecord
                    .filter(
                        Column("hash") == tmp.hash
                        && Column("urlNoQuery") == tmp.urlNoQuery
                        && Column("query") == tmp.query
                        && Column("body") == tmp.body
                        && Column("method") == tmp.method
                    )
                    .fetchAll(self)
                foundRecords.sort { $0.instance < $1.instance }
                foundRecord = foundRecords.last
            }
        }
        
        return foundRecord
    }
    
    func response(for requestRecord: GRDBSession.RequestRecord) throws -> GRDBSession.ResponseRecord? {
        return try GRDBSession.ResponseRecord.filter(Column("requestID") == requestRecord.id).fetchOne(self)
    }
    
    func otherAuthenticatedRecord(for request: Request, instanceCount: Int, configuration: GRDBSession.Configuration) throws -> GRDBSession.RequestRecord? {
        // Given an authenticated request, this method finds the same request, but authenticated a different way.
        
        let tmp = GRDBSession.RequestRecord(request: request, instance: Int64(instanceCount))
        
        if request.queryContainsAuthentication,
            let queryTokenRemoved = configuration.normalize(url: request.url, mode: .removeTokenParameters).query?.removingPercentEncoding {
            if let record = try GRDBSession.RequestRecord.filter(
                Column("urlNoQuery") == tmp.urlNoQuery
                && Column("instance") == tmp.instance
                && Column("body") == tmp.body
                && Column("method") == tmp.method
                && Column("queryContainsAuthentication") == false
                && Column("query") == queryTokenRemoved
                && Column("headersContainAuthentication") == true // this is where to look for the request with token in headers
            ).fetchOne(self) {
                return record
            }
        }
        
        return nil
    }
    
    func unauthenticatedRecord(for request: Request, instanceCount: Int, configuration: DejavuSessionConfiguration) throws -> GRDBSession.RequestRecord? {
        // Given an authenticated request, this method finds the same request, but not authenticated
        
        let tmp = GRDBSession.RequestRecord(request: request, instance: Int64(instanceCount))
        
        if request.queryContainsAuthentication,
            let queryTokenRemoved = configuration.normalize(url: request.url, mode: .removeTokenParameters).query?.removingPercentEncoding {
            if let record = try GRDBSession.RequestRecord.filter(
                Column("urlNoQuery") == tmp.urlNoQuery
                && Column("instance") == tmp.instance
                && Column("body") == tmp.body
                && Column("method") == tmp.method
                && Column("queryContainsAuthentication") == false
                && Column("query") == queryTokenRemoved
            ).fetchOne(self) {
                return record
            }
        }
        
        if request.bodyContainsAuthentication,
            let body = request.body,
            let bodyTokenRemoved = configuration.normalizeRequestBody(data: body, mode: .removeTokenParameters) {
            if let record = try GRDBSession.RequestRecord.filter(
                Column("urlNoQuery") == tmp.urlNoQuery &&
                    Column("instance") == tmp.instance &&
                    Column("query") == tmp.query &&
                    Column("method") == tmp.method &&
                    Column("body") == bodyTokenRemoved &&
                    Column("bodyContainsAuthentication") == false
                ).fetchOne(self) {
                return record
            }
        }
        
        if request.headersContainAuthentication {
            if let record = try GRDBSession.RequestRecord.filter(
                Column("urlNoQuery") == tmp.urlNoQuery &&
                    Column("instance") == tmp.instance &&
                    Column("query") == tmp.query &&
                    Column("body") == tmp.body &&
                    Column("method") == tmp.method &&
                    Column("headersContainAuthentication") == false
                ).fetchOne(self) {
                return record
            }
        }
        
        return nil
    }
}

private extension DatabaseQueue {
    var url: URL { .init(filePath: path) }
    
    convenience init(fileURL: URL) throws {
        try self.init(path: fileURL.path)
    }
}

private extension FileManager {
    func fileExists(at fileURL: URL) -> Bool {
        return fileExists(atPath: fileURL.path)
    }
}
