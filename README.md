# AsyncServerSentEvents

An implementation of [Server-Sent Events (SSE)](https://html.spec.whatwg.org/multipage/server-sent-events.html) for Swift using async sequences. Events are parsed from any `AsyncSequence` of bytes and exposed as an `AsyncSequence` of `ServerSentEvent` values, with an optional `EventSource`-style reconnecting client built on `URLSession`.

## Usage

### EventSource (reconnecting client)

`EventSource` mirrors the specification's `EventSource` interface: it sends the `Accept: text/event-stream` header, automatically reconnects when the server closes the stream or the network drops, honors the server's `retry` interval, and resumes with the `Last-Event-ID` header.

```swift
let url = URL(string: "https://example.com/sse")!

for try await event in EventSource(url: url) {
    print(event.type, event.data)
}
```

Iteration only ends when the server responds with HTTP 204 (the spec's "stop reconnecting" signal), an unrecoverable response is received (thrown as `SSEError`), or the consuming task is cancelled. To resume a previous session, pass the last event ID you stored:

```swift
let source = EventSource(
    request: URLRequest(url: url),
    configuration: .init(retryInterval: 3000, lastEventId: storedId)
)
```

### Single connection (no reconnection)

The `URLSession` helpers open one connection, send the required headers, and validate that the response is a `200` with a `text/event-stream` content type (throwing `SSEError` otherwise):

```swift
let (sse, response) = try await URLSession.shared.serverSentEvents(from: url)

for try await event in sse {
    print(event.data)
}

// For manual reconnection:
let lastEventId = await sse.state.lastEventId
let retryInterval = await sse.state.retryInterval
```

You can also parse an existing byte stream directly:

```swift
let (bytes, response) = try await URLSession.shared.bytes(from: url)

for try await event in bytes.sse() {
    print(event)
}
```

### Parsing any byte stream

The parser is generic over `AsyncSequence` with `UInt8` elements, so it isn't tied to `URLSession`:

```swift
let events = AsyncServerSentEvents(bytes: someByteSequence)
```

Parsing is lazy and driven by iteration: bytes are only consumed as you request events, errors from the byte stream are rethrown to the consumer, and cancelling the consuming task stops the parse.

## Events

Each `ServerSentEvent` carries:

- `data` — the event payload, with multiple `data` fields joined by newlines per the spec
- `name` — the raw `event` field, if present; `type` applies the spec's `"message"` default
- `id` — the `id` field explicitly present on this event's block, if any
- `lastEventId` — the last event ID in effect when the event was dispatched (persists across events, per the spec); this is the value to resume from

## Supported Features

- [x] WHATWG-compliant line parsing (`CR`, `LF`, `CRLF`)
- [x] UTF-8 decoding with replacement characters and leading BOM removal
- [x] Strict field parsing (`data`, `id`, `event`, `retry`) with single-space value trim
- [x] Comment lines ignored per spec
- [x] Last event ID persistence across events, committed at dispatch time
- [x] `retry` field handling
- [x] Errors from the transport are rethrown to the consumer
- [x] `Accept: text/event-stream` request header and response validation (status and content type)
- [x] Automatic reconnection with `retry` interval and `Last-Event-ID` header (`EventSource`)
- [x] HTTP 204 handled as "stop reconnecting"

## Platforms

The library works on Apple platforms and Linux. Instead of `URLSession.AsyncBytes` (which is unavailable on Linux), networking is built on `SSEByteStream`, a small delegate-based byte stream over `URLSessionDataTask`, so the parser, the `URLSession` helpers, and `EventSource` all behave identically everywhere. On Apple platforms, `URLSession.AsyncBytes.sse()` remains available as a convenience.
