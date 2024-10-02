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

internal import os

public enum Dejavu {
    /// The current session.
    public static var currentSession: DejavuSession? {
        _currentSession.withLock { $0 }
    }
    
    private static let _currentSession = OSAllocatedUnfairLock<GRDBSession?>(initialState: nil)
    
    @discardableResult
    /// Starts a new Dejavu session.
    /// - Parameter configuration: The configuration for the new session.
    /// - Returns: The new session.
    public static func startSession(configuration: DejavuSessionConfiguration) throws -> DejavuSession {
        // end current session
        endSession()
        
        // create new session
        let session = try GRDBSession(configuration: configuration)
        _currentSession.withLock { $0 = session }
        
        session.begin()
        
        log("Dejavu session started", category: .beginSession, type: .info)
        
        return session
    }
    
    /// Sets url protocol registration handler for the network observer and interceptor.
    @preconcurrency
    public static func setURLProtocolRegistrationHandler(_ handler: @escaping @Sendable (AnyClass) -> Void) {
        URLProtocolNetworkObserver.shared.setURLProtocolRegistrationHandler(handler)
        URLProtocolNetworkInterceptor.shared.setURLProtocolRegistrationHandler(handler)
    }
    
    /// Sets url protocol unregistration handler for the network observer and interceptor.
    @preconcurrency
    public static func setURLProtocolUnregistrationHandler(_ handler: @escaping @Sendable (AnyClass) -> Void) {
        URLProtocolNetworkObserver.shared.setURLProtocolUnregistrationHandler(handler)
        URLProtocolNetworkInterceptor.shared.setURLProtocolUnregistrationHandler(handler)
    }
    
    /// Ends the current Dejavu session.
    public static func endSession() {
        // First cut the ties to the current session
        let session: GRDBSession? = _currentSession.withLock { currentSession in
            let session = currentSession
            if currentSession != nil {
                currentSession = nil
            }
            return session
        }
        
        guard let session else { return }
        
        // call end on session
        session.end()
        
        log("Dejavu session ended", category: .endSession, type: .info)
    }
}
