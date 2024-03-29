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

import Foundation.NSURLProtocol

public enum Dejavu {
    /// The current session.
    public private(set) static var currentSession: DejavuSession?
    
    @discardableResult
    /// Starts a new Dejavu session.
    /// - Parameter configuration: The configuration for the new session.
    /// - Returns: The new session.
    public static func startSession(configuration: DejavuConfiguration) -> DejavuSession {
        // end current session
        endSession()
        
        // create new session
        let session = GRDBSession(configuration: configuration)
        currentSession = session
        
        // enable playing back or recording
        switch configuration.mode {
        case .playback:
            Player.shared.enable(session: session, networkInterceptor: configuration.networkInterceptor)
        case .cleanRecord, .supplementalRecord:
            NetworkRecorder.shared.enable(session: session, networkObserver: configuration.networkObserver)
        case .disabled:
            break
        }
        
        log("Dejavu session started", category: .beginSession, type: .info)
        
        return session
    }
    
    /// Sets url protocol registration handler for the network observer and interceptor.
    public static func setURLProtocolRegistrationHandler(_ handler: @escaping (AnyClass) -> Void) {
        URLProtocolNetworkObserver.shared.urlProtocolRegistrationHandler = handler
        URLProtocolNetworkInterceptor.shared.urlProtocolRegistrationHandler = handler
    }
    
    /// Sets url protocol unregistration handler for the network observer and interceptor.
    public static func setURLProtocolUnregistrationHandler(_ handler: @escaping (AnyClass) -> Void) {
        URLProtocolNetworkObserver.shared.urlProtocolUnregistrationHandler = handler
        URLProtocolNetworkInterceptor.shared.urlProtocolUnregistrationHandler = handler
    }
    
    /// Ends the current Dejavu session.
    public static func endSession() {
        guard let session = currentSession else {
            return
        }
        
        // First cut the ties to the current session
        currentSession = nil
            
        // disable playback or recording
        switch session.configuration.mode {
        case .playback:
            Player.shared.disable()
        case .cleanRecord, .supplementalRecord:
            NetworkRecorder.shared.disable()
        case .disabled:
            break
        }
        
        // call end on session
        (session as? SessionInternal)?.end()
        
        log("Dejavu session ended", category: .endSession, type: .info)
    }
}
