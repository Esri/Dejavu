<div align="center">
    <img width="25%" src="/Media/Dejavu~1000x1000.png">
    <h1>Dejavu</h1>
    <strong>Mocking for Swift network requests</strong>
    <br>
    <br>
    <img src="https://img.shields.io/badge/license-Apache-blue">
    <img src="https://img.shields.io/badge/swift-5.9-orange">
</div>

Use Dejavu to mock network requests in Swift tests making them faster and more reliable. First use Dejavu to record network activity. From then on Dejavu can playback the original network request, exactly as it ran the first time. Dejavu stores requests and responses in a sqlite database.

Dejavu is used to help test the [ArcGIS Maps SDK for Swift](https://github.com/Esri/arcgis-maps-sdk-swift).

## Example

A full example of a mocked network test can be found [here](Examples/ExamplesTests/ExamplesTests.swift).

## Instructions

### One time setup

Configure a location to store mocked data. Detailed instructions for this can be found [here](./AdditionalDocumentation/MockedDataSetupInstructions.md).

### Usage Overview

#### 1. Prepare network interception and observation

Dejavu can be configured to use custom network interceptors and observers. These can be specified when creating the `DejavuConfiguration`.  However, you may choose to use the defaults. The defaults use `URLProtocol`, which does require setup, specifically to tell the `URLSession` you are using what `URLProtocol` classes to [use](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/1411050-protocolclasses).

To do this, you will need to set a URL protocol registration and unregistration handler for the
interceptor and observer. This is an example of how to wire that up:

```swift
// Set the protocol registration handler.
Dejavu.setURLProtocolRegistrationHandler { [weak self] protocolClass in
    guard let self else { return }
    let config = URLSessionConfiguration.default
    config.protocolClasses = [protocolClass]
    self.session = URLSession(configuration: config)
}

// Set the protocol unregistration handler.
Dejavu.setURLProtocolUnregistrationHandler { [weak self] protocolClass in
    self?.session = URLSession(configuration: .default)
}
```

#### 2. Record network requests

```swift
let config = DejavuConfiguration(fileURL: URL, mode: .cleanRecord)
Dejavu.startSession(configuration: config)
```

#### 3. Playback network requests

```swift
let config = DejavuConfiguration(fileURL: URL, mode: .playback)
Dejavu.startSession(configuration: config)
```

#### 4. End the session

```swift
Dejavu.endSession()
```

#### 5. Explore other modes

Dejavu has 4 modes:

- `disabled` - Does nothing; requests and responses go out over the network as normal.

- `cleanRecord` - First deletes the cache, then records any network traffic to the cache.
 
- `supplementalRecord` - Records any network traffic to the cache. Does not delete the database first.

- `playback` - Intercepts requests and gets the responses from the cache.

## Requirements

* Swift 5.9 / Xcode 15.0 (or newer)
* iOS 15.0, Mac Catalyst 15.0 (minimum deployment targets)

## Issues

Find a bug or want to request a new feature?  Please let us know by [submitting an issue](https://github.com/ArcGIS/Dejavu/issues/new).

## Contributing

Esri welcomes contributions from anyone and everyone. Please see our [guidelines for contributing](https://github.com/esri/contributing).

## Licensing
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
