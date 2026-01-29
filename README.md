# AsyncServerSentEvents

An implementation of Server-Sent Events (SSE) for Swift using async sequences. Events are parsed from `URLSession.AsyncBytes` and exposed as an `AsyncSequence`.

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

- [x] WHATWG-compliant line parsing (`CR`, `LF`, `CRLF`)
- [x] Strict field parsing (`data`, `id`, `event`) with single-space value trim
- [x] Comment lines ignored per spec
- [ ] Retry field handling
- [ ] Last-Event-ID persistence across events/reconnects
