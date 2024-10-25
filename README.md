# AsyncServerSentEvents

An implementation of Server-Sent Events (SSE) for Swift using async sequences. Events are parsed and streamed from the `AsyncBytes` sequence returned via URLSession.

## Usage

```swift
let url = URL(string: "https://example.com/sse")!
let sse = try await URLSession.shared
    .asyncBytes(from: url)
    .sse()

for try await event in sse {
    print(event)
}
```

or

```swift
let (sse, response) = try await URLSession.shared.serverSentEvents(from: url)

for try await event in sse {
    print(event)
}
```

or

```swift
let request = URLRequest(url: url)
let (sse, response) = try await URLSession.shared.serverSentEvents(for: request)

for try await event in sse {
    print(event)
}
```

## Supported Features

- [x] Basic SSE parsing
- [x] Event data, id, name and associated comments
- [ ] Parser error handling
- [ ] Last Event ID
