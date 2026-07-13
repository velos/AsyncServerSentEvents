# Improve the SSE Parser for 0.2.0

## Summary

Extract the parsing logic into `SSEParser`, a synchronous, value-semantic incremental parser, and rebuild the async APIs as thin wrappers over it. Everything that exists in 0.1.0 keeps compiling and behaving identically; the new surface is small and non-throwing.

## Public API Additions

- `SSEParser`, a `Sendable` **struct** (value semantics, no locking):
  - `mutating func consume(_ byte: UInt8) -> ServerSentEvent?`
  - `mutating func consume(_ bytes: some Sequence<UInt8>) -> [ServerSentEvent]`
  - `mutating func finish()` — end of stream: applies an unterminated trailing field line (so a trailing `retry` still counts, matching 0.1.0), discards the incomplete block per spec, and resets for a new stream (BOM stripped again) while retaining reconnect state.
  - `private(set) var lastEventId: String?` and `retryInterval: Int?` — the committed reconnect state.
  - `static func parse(_ bytes: some Sequence<UInt8>) -> [ServerSentEvent]` for fully buffered input.
  - Nothing throws: per spec, invalid UTF-8 decodes with replacement characters and malformed lines are ignored, so parsing is total.
- Generic `AsyncSequence where Element == UInt8` extension providing `.sse()`, replacing (source-compatibly) the concrete `SSEByteStream` and Darwin-only `URLSession.AsyncBytes` extensions.

## Deliberately cut from the other plan

- `ServerSentEventBlock` — its `data == nil` sentinel duplicated `ServerSentEvent` awkwardly; block-level state consumers just read `lastEventId`/`retryInterval` off the parser.
- `SSEParser.Limits` and throwing `consume` — speculative; can be added additively in a later release if ever needed.
- `.sseBlocks()` adapters — no consumer.

## Implementation Changes

- New `SSEParser.swift`: internal `SSELineSplitter` (byte → line state machine, CR/LF/CRLF, leading BOM) + `SSEParser` (field parsing directly from bytes, decoding only recognized values; no `String.split`).
- `AsyncServerSentEvents.AsyncIterator` becomes a loop feeding bytes to an `SSEParser`, mirroring committed state into the existing public `SSEState` actor only when it changes.
- `EventSource` reads reconnect state synchronously from its iterator's parser instead of awaiting the `SSEState` actor.
- Behavioral compatibility pinned: id commits only at blank line; retry applies per line (including an unterminated final line at EOF); state-only blocks observable; comment-only blocks silent; per-stream last-event-ID buffer resets across reconnects while the committed value persists.

## Test Plan

- All 63 existing tests pass unchanged (line-splitting tests port to the sync splitter, same assertions).
- New `SSEParserTests`: every existing fixture parsed sync vs async with identical events and final state; chunk-boundary invariance (sizes 1/2/3/7/16/1024); emission timing; state-only blocks; `finish()` reuse incl. BOM re-strip; trailing unterminated `retry` line.
- Clean `swift build` and `swift test`.
