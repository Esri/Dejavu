# <p align="center">Dejavu</p>

<p align="center">
    <strong>Mocking for Swift network requests</strong>
    <br>
    Stores requests/responses in a sqlite database
</p>

<p align="center">
	<img src="https://img.shields.io/badge/license-Apache-blue">
	<img src="https://img.shields.io/badge/swift-5.7-orange">
</p>

### Usage Overview

#### 1. Prepare network interception and observation

Dejavu can be configured to use custom network interceptors and observers. These can be specified when creating the `DejavuConfiguration`.  However, you may choose to use the defaults. The defaults use `URLProtocol`, which does require setup, specifically to tell the `URLSession` you are using what `URLProtocol` classes to [use](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/1411050-protocolclasses).

To do this, you will need to set `urlProtocolRegistrationHandler` and `urlProtocolUnregistrationHandler` on `URLProtocolNetworkInterceptor.shared` and `URLProtocolNetworkObserver.shared`. The registration and unregistration handlers can be set for both the observer and interceptor in one call each. This is an example of how to wire that up:

```swift
// Set the protocol registration handlers.
Dejavu.setURLProtocolRegistrationHandler { [weak self] protocolClass in
    guard let self else { return }
    let config = URLSessionConfiguration.default
    config.protocolClasses = [protocolClass]
    self.session = URLSession(configuration: config)
}

// Set the protocol unregistration handlers.
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

### Example

A full example of mocked network test can be found [here](Examples/ExamplesTests/ExamplesTests.swift).
