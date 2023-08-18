# Dejavu

- Mocking for Swift network requests
- Stores requests/responses in a sqlite database

### Usage

#### Network Interception and Observation

Dejavu can be configured to use custom network interceptors and observers. These can be specified when creating the `DejavuConfiguration`.  However, you may choose to use the defaults. The defaults use `URLProtocol`, which does require setup, specifically to tell the `URLSession` you are using what `URLProtocol` classes to [use](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/1411050-protocolclasses).

To do this, you will need to set the `urlProtocolRegistrationHandler` and `urlProtocolUnregistrationHandler` on `DejavuURLProtocolNetworkInterceptor.shared` and `DejavuURLProtocolNetworkObserver.shared`. This is an example of how to wire that up:

```swift
// Register the interceptor
DejavuURLProtocolNetworkInterceptor.shared.urlProtocolRegistrationHandler = { [weak self] (protocolClass : AnyClass) in
    guard let self = self else { return }
    let config = URLSessionConfiguration.default
    config.protocolClasses = [protocolClass]
    self.session = URLSession(configuration: config)
}

// Register the observer
DejavuURLProtocolNetworkObserver.shared.urlProtocolRegistrationHandler = { [weak self] (protocolClass : AnyClass) in
    guard let self = self else { return }
    let config = URLSessionConfiguration.default
    config.protocolClasses = [protocolClass]
    self.session = URLSession(configuration: config)
}

// Unregister the interceptor
DejavuURLProtocolNetworkInterceptor.shared.urlProtocolUnregistrationHandler = { [weak self] (protocolClass : AnyClass) in
    guard let self = self else { return }
    self.session = URLSession(configuration: .default)
}

// Unregister the observer
DejavuURLProtocolNetworkObserver.shared.urlProtocolUnregistrationHandler = { [weak self] (protocolClass : AnyClass) in
    guard let self = self else { return }
    self.session = URLSession(configuration: .default)
}
```

#### General Use

Dejavu works in 4 modes:

- disabled
- cleanRecord
- supplementalRecord
- playback

##### disabled mode
Does nothing - requests and responses go out over the network as normal.

##### cleanRecord mode
First deletes the cache, then records any network traffic to the cache.

##### supplementalRecord mode
Records any network traffic to the cache. Does not delete the database first.

##### playback
Intercepts requests and gets the responses from the cache.

##### Sample Code

Recording:
```swift
let config = DejavuConfiguration(fileURL: dejavuURL, mode: .cleanRecord)
Dejavu.startSession(configuration: config)
```

Playback:
```swift
let config = DejavuConfiguration(fileURL: dejavuURL, mode: .playback)
Dejavu.startSession(configuration: config)
```