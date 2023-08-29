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

import Dejavu
import XCTest

final class ExamplesTests: XCTestCase {
    override func setUp() {
        let config = DejavuConfiguration(
            fileURL: .testDataDirectory.appendingPathComponent(mockDataSubpath),
            mode: .playback
        )
        
        URLProtocolNetworkInterceptor.shared.urlProtocolRegistrationHandler = { [weak self] protocolClass in
            guard let self else { return }
            let config = URLSessionConfiguration.default
            config.protocolClasses = [protocolClass]
            self.session = URLSession(configuration: config)
        }
        
        URLProtocolNetworkInterceptor.shared.urlProtocolUnregistrationHandler = { [weak self] protocolClass in
            self?.session = URLSession(configuration: .default)
        }
        
        URLProtocolNetworkObserver.shared.urlProtocolRegistrationHandler = { [weak self] protocolClass in
            guard let self = self else { return }
            let config = URLSessionConfiguration.default
            config.protocolClasses = [protocolClass]
            self.session = URLSession(configuration: config)
        }
        
        URLProtocolNetworkObserver.shared.urlProtocolUnregistrationHandler = { [weak self] protocolClass in
            self?.session = URLSession(configuration: .default)
        }
        
        Dejavu.startSession(configuration: config)
    }
    
    override func tearDown() {
        Dejavu.endSession()
    }
    
    var session: URLSession = URLSession(configuration: .default)
    
    func testExample() async throws {
        let (data, _) = try await session.data(from: .esri)
        XCTAssertEqual(data.count, 45668)
    }
}

extension URL {
    static var esri: URL {
        URL(string: "https://www.esri.com")!
    }
}
