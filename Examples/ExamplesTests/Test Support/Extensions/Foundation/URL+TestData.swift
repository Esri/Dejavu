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

extension URL {
    /// The `URL` of the mocked data directory.
    static let testDataDirectory: URL = {
#if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        if let plistPath: String = Bundle.main.object(forInfoDictionaryKey: "MOCKED_DATA") as? String, !plistPath.isEmpty {
            return URL(fileURLWithPath: plistPath)
        } else {
            fatalError(
                """
                You must setup a custom path in Xcode -> Settings -> Locations -> Custom Paths named
                `MOCKED_DATA` that points to the location of the test data.
                """
            )
        }
#else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Data", isDirectory: true)
#endif
    }()
}
