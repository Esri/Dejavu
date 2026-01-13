<div align="center">
    <img width="5%" src="/Media/Dejavu~1000x1000.png">
    <h1>Dejavu Tutorial</h1>
    <strong>Setting up and using Dejavu</strong>
    <br>
    <br>
    <img src="https://img.shields.io/badge/license-Apache-blue">
    <img src="https://img.shields.io/badge/swift-5.9-orange">
</div>

Dejavu allows you to record network requests during tests and replay them later, eliminating the unpredictability of network conditions and speeding up your test suite. Dejavu stores all recorded requests and responses in a SQLite database, which can be saved and reused across different test runs. Dejavu provides various configuration options to customize its behavior, such as specifying which requests to record or replay, and how to handle unmatched requests. Dejavu can make tests more deterministic, reliable, and faster.

This tutorial steps you through the process of integrating Dejavu into a test iOS app. It uses [JSONPlaceholder](https://jsonplaceholder.typicode.com/) to simulate network calls, which is useful in scenarios where the real API might be under development, rate-limited, or unavailable due to connectivity issues. In a geospatial context, this could represent a feed of user-submitted location data or address records, which are critical to test without relying on live endpoints.

# Requirements

* Swift 5.9 / Xcode 15.0 (or newer)
* iOS 15.0, Mac Catalyst 15.0 (minimum deployment targets)

# Set up the project

#### 1. Create a new Xcode project
- Open **Xcode** and create a new project.
- Choose **iOS** at the top and select the **App** template and then click **Next**.
- Name our project (e.g. "DejavuDemo") and for the storage you **can set it as None**.

![Create new Project](https://raw.githubusercontent.com/harish-kunchala/blog-images/refs/heads/main/dejavu-blog/create-new-project.png)
#### 2. Set Custom paths for mocked data
- We need to configure a location to store the data that Dejavu will record and playback.
- In our current app, we are going to use `/DejavuDemoTests/MockedData`:
	- First create a new folder named `MockedData` under `DejavuDemo/DejavuDemoTests`
![Mocked Image Folder](https://raw.githubusercontent.com/harish-kunchala/blog-images/refs/heads/main/dejavu-blog/mocked-data-folder.png)
- Under `Xcode > Settings > Locations > Custom Paths` set a custom path named `MOCKED_DATA` and set the absolute path of `MockedData` folder.

![Custom Path](https://raw.githubusercontent.com/harish-kunchala/blog-images/refs/heads/main/dejavu-blog/custom-paths.png)
- Select your project in the Project Navigator. Next, open the **Info** tab of your project's main target. Add a key that can be referenced programmatically. For more details, refer to the [Mocked Data Setup Instructions](https://github.com/Esri/Dejavu/blob/main/AdditionalDocumentation/MockedDataSetupInstructions.md).
![Target Info Tab](https://raw.githubusercontent.com/harish-kunchala/blog-images/refs/heads/main/dejavu-blog/target-info-tab.png)
#### 3. Add Dejavu
   - Go to `File > Add Package Dependencies…`.
   - Enter the Dejavu GitHub repository URL: `https://github.com/Esri/dejavu`.
   - Select the latest version and add it to your project.
#### 4. Add Dejavu to frameworks and libraries
- To ensure Dejavu is properly integrated into your test target, follow these steps:
    1. Open your Xcode project.
    2. Select the `DejavuDemo` project in the Project Navigator.
    3. Select the `DejavuDemoTests` target.
    4. Go to the `General` tab.
    5. Scroll down to the `Frameworks, Libraries, and Embedded Content` section.
    6. Click the `+` button to add a new framework.
    7. Search for `Dejavu` and add it to the list.
### Implement the project
#### 1. Implement the network request
- Let's create a new Swift file `NetworkManager.swift` in our project under `DejavuDemo/NetworkManager.swift`. 
- The `NetworkManger` enum is responsible for handling network requests in our app.
- It uses `URLSession` to perform HTTP requests and fetch data from a give URL.
- By centralizing network operations in a single enum, we can easily manage and reuse network-related code throughout the app. This approach also makes it easier to mock network requests during testing.

Key features of the `NetworkManager` class:
- **Value Type**: Using an enum instead of a class aligns with Swift's emphasis on value types.
- **Asynchronous Fetch Method**: A static method to fetch data from a specified URL and decode the JSON response into a model object using Swift concurrency.
- **Error Handling**: Handles errors gracefully by using Swift's `async` and `throws` keywords to return either the fetched data or an error.
```swift
import Foundation

/// Provides conveniences for making network requests.
enum NetworkManager {
    /// Returns a value decoded from JSON data retrieved asynchronously from the given URL.
    /// - Parameters:
    ///   - url: The URL to retrieve.
    ///   - type: The type of the value to decode from the JSON data.
    static func value<T: Decodable>(forDataFrom url: URL, type: T.Type = T.self) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}

```
#### 2. Set up Dejavu for network testing
- Since we have already enabled tests at the creation of the project, we'll have a folder named DejavuDemoTests.
- Now let's go modify the `DejavuDemoTests.swift` code.

- **Imports**: We import `XCTest` for testing, `Dejavu` for network mocking, and `DejavuDemo` to access the app's code:

```swift
import XCTest
import Dejavu
@testable import DejavuDemo
```

- **Class Declaration**: `DejavuDemoTests` is a subclass of `XCTestCase`, which provides the testing framework.
- **Session Variable**: `session` is a `URLSession` instance that will be configured to use Dejavu.

```swift
final class DejavuDemoTests: XCTestCase {
    var session: URLSession!
```
- **setUpWithError()**: This method is called before each test method in the class.
  - **Registering Dejavu's URL Protocol**: `Dejavu.setURLProtocolRegistrationHandler` registers Dejavu's URL protocol to intercept network requests. It configures a `URLSession` with this protocol.
  - **Unregistering Dejavu's URL Protocol**: `Dejavu.setURLProtocolUnregistrationHandler` unregisters the protocol after tests, resetting the `URLSession` to its default configuration.
  - **Configuring Dejavu**: `DejavuConfiguration` specifies the path to store recorded data (`mockData`) and the mode (`cleanRecord`), which records new data and cleans old data.
  - **Starting Dejavu Session**: `Dejavu.startSession` starts the Dejavu session with the specified configuration.
```swift
    override func setUpWithError() throws {
        // Register Dejavu's URL protocol to intercept network requests.
        Dejavu.setURLProtocolRegistrationHandler { [weak self] protocolClass in
            guard let self else { return }
            let config = URLSessionConfiguration.default
            config.protocolClasses = [protocolClass]
            self.session = URLSession(configuration: config)
        }
        
        // Unregister Dejavu's URL protocol after tests.
        Dejavu.setURLProtocolUnregistrationHandler { [weak self] protocolClass in
            self?.session = URLSession(configuration: .default)
        }
        
        // Configure Dejavu with the path to store recorded data and the mode.
        let configuration = DejavuConfiguration(
            fileURL: .testDataDirectory.appending(component: "mockData"),
            mode: .cleanRecord
        )
        
        // Start Dejavu session with the specified configuration.
        Dejavu.startSession(configuration: configuration)
    }
    
```
- **tearDown()**: This method is called after each test method in the class.
  - **Ending Dejavu Session**: `Dejavu.endSession` ends the Dejavu session.
  - **Resetting Session**: Sets `session` to `nil` to clean up.

```swift
    override func tearDown() {
        // End Dejavu session after tests.
        Dejavu.endSession()
        session = nil
    }
```
- **testFetchDataSuccessfullyReturnsUsers()**: This is an asynchronous test method that performs a network request and verifies the response.
  - **URL Definition**: Defines the URL for the network request.
  - **Network Request**: Uses the configured `session` to perform the network request and await the response.
  - **Data Decoding**: Decodes the received data into an array of `User` objects.
  - **Assertions**: Verifies the response status code and asserts that the `users` array matches the expected data.
```swift
     func testFetchDataSuccessfullyReturnsUsers() async throws {
        // Define the URL for the network request.
        let url = URL(string: "https://jsonplaceholder.typicode.com/users")!
        
        // Perform the network request using the configured session.
        let (data, response) = try await session.data(from: url)
        
        // Verify the response status code.
        if let httpResponse = response as? HTTPURLResponse {
            XCTAssertEqual(httpResponse.statusCode, 200, "Expected status code 200")
        }
        
        // Decode the received data into an array of User objects.
        let users = try JSONDecoder().decode([User].self, from: data)
        
        // Assert that the users array matches the expected data.
        XCTAssertEqual(
            users,
            [
                User(id: 1, name: "Leanne Graham", email: "Sincere@april.biz"),
                User(id: 2, name: "Ervin Howell", email: "Shanna@melissa.tv"),
                User(id: 3, name: "Clementine Bauch", email: "Nathan@yesenia.net"),
                User(id: 4, name: "Patricia Lebsack", email: "Julianne.OConner@kory.org"),
                User(id: 5, name: "Chelsey Dietrich", email: "Lucio_Hettinger@annie.ca"),
                User(id: 6, name: "Mrs. Dennis Schulist", email: "Karley_Dach@jasper.info"),
                User(id: 7, name: "Kurtis Weissnat", email: "Telly.Hoeger@billy.biz"),
                User(id: 8, name: "Nicholas Runolfsdottir V", email: "Sherwood@rosamond.me"),
                User(id: 9, name: "Glenna Reichert", email: "Chaim_McDermott@dana.io"),
                User(id: 10, name: "Clementina DuBuque", email: "Rey.Padberg@karina.biz")
            ]
        )
    }
}
```
- **URL Extension**: Provides a static property `testDataDirectory` to get the path for storing mocked data.
  - **Simulator or Mac Catalyst**: Uses a custom path set in Xcode settings.
  - **Other Environments**: Uses the document directory path.
```swift
extension URL {
    static let testDataDirectory: URL = {
#if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        if let plistPath: String = Bundle.main.object(forInfoDictionaryKey: "MOCKED_DATA") as? String, !plistPath.isEmpty {
            return URL(filePath: plistPath)
        } else {
            fatalError(
                """
                You must set up a custom path in Xcode > Settings > Locations > Custom Paths named
                `MOCKED_DATA` that points to the location of the test data.
                """
            )
        }
#else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appending(component: "Data/")
#endif
    }()
}
```
You can find the entire `DejavuDemoTests` class [here](https://github.com/harish-kunchala/DejavuDemo/blob/main/DejavuDemoTests/DejavuDemoTests.swift).
#### 3. Creating the `ContentView`
- Now that network class and test classes are setup. We can define the UI.
- We'll user a `List` to show the users' names and emails, and handle any errors that might occur during the network request.
- Here's the complete code for our `ContentView`:
```swift
import SwiftUI

// Main view for displaying the list of users.
struct ContentView: View {
    // State variables to hold the list of users and any error messages.
    @State private var result: Result<[User], Error>?
    @State private var isShowingAlert = false
    
    var users: [User] {
        guard case let .success(users) = result else {
            return []
        }
        return users
    }
    
    var error: Error? {
        guard case let .failure(error) = result else {
            return nil
        }
        return error
    }
    
    var body: some View {
        NavigationView {
            // List to display users' names and emails.
            List(users) { user in
                VStack(alignment: .leading) {
                    Text(user.name)
                        .font(.headline)
                    Text(user.email)
                        .font(.subheadline)
                }
            }
            .navigationTitle("Users")
            // Fetch users when the view appears.
            .task {
                guard result == nil else { return }
                let url = URL(string: "https://jsonplaceholder.typicode.com/users")!
                do {
                    let users: [User] = try await NetworkManager.value(forDataFrom: url)
                    result = .success(users)
                } catch {
                    result = .failure(error)
                    isShowingAlert = true
                }
            }
            .alert("Error", isPresented: $isShowingAlert, presenting: error) { _ in
                // OK action included by default.
            } message: { error in
                Text("Error fetching users: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView()
}

// User model conforming to Codable and Identifiable protocols.
// This allows the model to be easily decoded from JSON and used in SwiftUI lists.
struct User: Codable, Equatable, Identifiable {
    let id: Int
    let name: String
    let email: String
}

```

# Outputs
## Build Outputs
- First of all let's make sure that we get an output when we run the app.
- Our goals is to see a list of 10 users. We expect to see their names and their emails.
![Build Output](https://media4.giphy.com/media/v1.Y2lkPTc5MGI3NjExeG1pcTVpcmIzM2F3ZTNlbHVyMWtrNDhsaTB4eWZyanN5c3V4ZWtyeSZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/jIpdzXXXYuNkewkWiE/giphy.gif)
## Test Outputs
### 1. Run Test
- The way Dejavu works is that it creates a SQL database to log our network requests, allowing us to run future tests using the database instead of actual network calls.
- So let's run the test to see if it creates any table.

![Test Output](https://media3.giphy.com/media/v1.Y2lkPTc5MGI3NjExZHJiZmtvam5uM2xoc3VkeHhqYW01bGo3dnNvdG1xcmFpdDJjejlldCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/znBFlDJLY7n36IM8Fe/giphy.gif)
### 2. mockData table
- When I open `mockData` in sqlite3. Here's the schema output:
```sql
CREATE TABLE IF NOT EXISTS "requests" (
    "id" INTEGER PRIMARY KEY,
    "url" TEXT NOT NULL,
    "urlNoQuery" TEXT NOT NULL,
    "query" TEXT,
    "method" TEXT,
    "body" BLOB,
    "headers" BLOB,
    "hash" TEXT NOT NULL,
    "instance" INTEGER NOT NULL,
    "headersContainAuthentication" BOOLEAN NOT NULL,
    "queryContainsAuthentication" BOOLEAN NOT NULL,
    "bodyContainsAuthentication" BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS "responses" (
    "id" INTEGER PRIMARY KEY,
    "requestID" INTEGER REFERENCES "requests"("id") ON DELETE CASCADE,
    "data" BLOB,
    "headers" BLOB,
    "statusCode" INTEGER NOT NULL,
    "failureErrorDomain" TEXT,
    "failureErrorCode" INTEGER,
    "failureErrorDescription" TEXT
);
```
- The `mockData` database has created two tables: **requests** and **responses**.
### 3. Requests table
- Output for commands:
```sql
.headers on
SELECT * FROM requests;
```
- Here's the formatted "requests" table:

| id  | url                                        | urlNoQuery                                 | query | method | body | headers | hash                                                             | instance | headersContainAuthentication | queryContainsAuthentication | bodyContainsAuthentication |
| --- | ------------------------------------------ | ------------------------------------------ | ----- | ------ | ---- | ------- | ---------------------------------------------------------------- | -------- | ---------------------------- | --------------------------- | -------------------------- |
| 1   | https://jsonplaceholder.typicode.com/users | https://jsonplaceholder.typicode.com/users |       | GET    |      | {}      | ffcec943e58af39cccf43a72074c37c0e9cf664cb13645028d43dc48c70c38cf | 1        | 0                            | 0                           | 0                          |
### 4. Responses table
- Output for commands:
```sql
.header on
SELECT * FROM responses;
```

## Playback Speed
One of the standout features of Dejavu is its impressive playback speed once the mock data is registered. Here's a comparison to illustrate the benefits:

**Timing in `.cleanRecord` Mode**
```
Test Case '-[DejavuDemoTests.DejavuDemoTests testFetchDataSuccessfullyReturnsUsers]' passed (0.068 seconds).

Test Suite 'DejavuDemoTests' passed at 2025-02-06 11:17:52.750.

Executed 1 test, with 0 failures (0 unexpected) in 0.068 (0.068) seconds
```

**Timing in `.playback` Mode**
```
Test Case '-[DejavuDemoTests.DejavuDemoTests testFetchDataSuccessfullyReturnsUsers]' passed (0.005 seconds).

Test Suite 'DejavuDemoTests' passed at 2025-02-06 11:18:54.638.

Executed 1 test, with 0 failures (0 unexpected) in 0.005 (0.005) seconds
```
As you can see, the playback mode significantly reduces the test execution time, demonstrating the efficiency and speed benefits of using Dejavu. This makes it an invaluable tool for faster and more reliable testing.

# Licensing
Copyright 2023 Esri

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

A copy of the license is available in the repository's [LICENSE.txt](LICENSE.txt) file.
