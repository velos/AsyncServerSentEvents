import Foundation

/// An incremental, synchronous parser for the server-sent events stream format.
///
/// `SSEParser` is a value type: feed it bytes as they arrive and collect the
/// events it emits. It is the core that ``AsyncServerSentEvents`` is built on,
/// and can be used directly when bytes arrive through something other than an
/// `AsyncSequence` — a delegate callback, a WebSocket frame, or a fully
/// buffered response body:
///
/// ```swift
/// var parser = SSEParser()
/// for chunk in chunks {
///     for event in parser.consume(chunk) {
///         print(event.type, event.data)
///     }
/// }
/// parser.finish()
/// ```
///
/// Parsing never fails: per the
/// [WHATWG specification](https://html.spec.whatwg.org/multipage/server-sent-events.html),
/// invalid UTF-8 decodes with replacement characters and malformed field lines
/// are ignored.
public struct SSEParser: Sendable {

    /// The last event ID committed by a completed block.
    ///
    /// This is the value to resume from (via the `Last-Event-ID` header) when
    /// reconnecting, so ``finish()`` retains it. It is reconnect state only:
    /// per the specification the ID buffer is per-stream, so events parsed
    /// after ``finish()`` do not inherit this value into their
    /// ``ServerSentEvent/lastEventId`` until the new stream sends an `id`.
    public private(set) var lastEventId: String?

    /// The reconnection time in milliseconds from the most recent valid
    /// `retry` field. Retained by ``finish()``.
    public private(set) var retryInterval: Int?

    private var lines = SSELineSplitter()

    /// Accumulates each data value plus a newline; the trailing newline is
    /// removed at dispatch, so a lone `data:` line still dispatches an event
    /// with empty data while a block with no data field dispatches nothing.
    private var dataBuffer = ""
    private var eventName: String?
    private var eventId: String?

    /// The last event ID buffer: set immediately by `id` fields, but only
    /// committed to ``lastEventId`` when a blank line completes a block.
    private var idBuffer: String?

    public init() {}

    /// Consumes one byte, returning an event if this byte completed a block.
    public mutating func consume(_ byte: UInt8) -> ServerSentEvent? {
        guard let line = lines.consume(byte) else { return nil }
        return process(line: line)
    }

    /// Consumes a chunk of bytes, returning the events completed within it.
    public mutating func consume(_ bytes: some Sequence<UInt8>) -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        for byte in bytes {
            if let event = consume(byte) {
                events.append(event)
            }
        }
        return events
    }

    /// Signals the end of the stream.
    ///
    /// An unterminated final line is still processed (so a trailing `retry`
    /// field takes effect), the incomplete block is discarded per the
    /// specification, and the parser resets for a new stream — stripping a
    /// leading BOM again — while ``lastEventId`` and ``retryInterval`` are
    /// retained for reconnection. The ID buffer is per-stream, so events on
    /// the next stream carry a `nil` ``ServerSentEvent/lastEventId`` until
    /// that stream sends an `id` field.
    public mutating func finish() {
        if let line = lines.finish() {
            // An unterminated line is never blank, so this cannot dispatch.
            _ = process(line: line)
        }
        lines = SSELineSplitter()
        dataBuffer = ""
        eventName = nil
        eventId = nil
        idBuffer = nil
    }

    /// Parses a complete stream, returning every dispatched event.
    ///
    /// A trailing block not terminated by a blank line is discarded, per the
    /// specification's end-of-file rule.
    public static func parse(_ bytes: some Sequence<UInt8>) -> [ServerSentEvent] {
        var parser = SSEParser()
        return parser.consume(bytes)
    }

    private mutating func process(line: [UInt8]) -> ServerSentEvent? {
        guard !line.isEmpty else { return dispatchBlock() }

        // Split at the first colon; a line without one is a field name with an
        // empty value. Only one optional space after the colon is removed.
        let colonIndex = line.firstIndex(of: UInt8(ascii: ":"))
        let field = line[..<(colonIndex ?? line.endIndex)]
        var value = line[(colonIndex.map { $0 + 1 } ?? line.endIndex)...]
        if value.first == UInt8(ascii: " ") {
            value = value.dropFirst()
        }

        if field.elementsEqual("data".utf8) {
            dataBuffer.append(String(decoding: value, as: UTF8.self))
            dataBuffer.append("\n")
        } else if field.elementsEqual("event".utf8) {
            eventName = String(decoding: value, as: UTF8.self)
        } else if field.elementsEqual("id".utf8) {
            if !value.contains(0) {
                let id = String(decoding: value, as: UTF8.self)
                eventId = id
                idBuffer = id
            }
        } else if field.elementsEqual("retry".utf8) {
            if !value.isEmpty,
               value.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
               let milliseconds = Int(String(decoding: value, as: UTF8.self)) {
                retryInterval = milliseconds
            }
        }
        // Comment lines (empty field name) and unknown fields are ignored.
        return nil
    }

    /// Handles a blank line: commits the last event ID — even when no event is
    /// dispatched (e.g. an id-only block) — and dispatches the block's event
    /// if it accumulated any data.
    private mutating func dispatchBlock() -> ServerSentEvent? {
        if let id = idBuffer {
            lastEventId = id
        }
        defer {
            dataBuffer = ""
            eventName = nil
            eventId = nil
        }
        guard !dataBuffer.isEmpty else { return nil }
        var data = dataBuffer
        data.removeLast() // the newline appended by the final data field
        return ServerSentEvent(id: eventId, name: eventName, data: data, lastEventId: idBuffer)
    }
}

/// Splits a byte stream into lines terminated by LF, CR, or CRLF, stripping a
/// single leading BOM from the stream, as required by the specification.
///
/// The state machine treats CR as an immediate line terminator and swallows an
/// LF that directly follows it, so `CR LF` yields one line boundary while
/// `CR CR` yields two. Only CR, LF, and CRLF are boundaries — other Unicode
/// line separators (NEL, U+2028, U+2029) are ordinary content bytes per spec.
struct SSELineSplitter: Sendable {
    private var buffer: [UInt8] = []
    private var sawCarriageReturn = false
    private var isFirstLine = true

    /// Consumes one byte, returning a completed line if this byte ended one.
    mutating func consume(_ byte: UInt8) -> [UInt8]? {
        if sawCarriageReturn {
            sawCarriageReturn = false
            if byte == 0x0A { // LF completing a CRLF pair
                return nil
            }
        }

        switch byte {
        case 0x0A:
            return takeLine()
        case 0x0D:
            sawCarriageReturn = true
            return takeLine()
        default:
            buffer.append(byte)
            return nil
        }
    }

    /// Flushes an unterminated final line at end of input, if any.
    mutating func finish() -> [UInt8]? {
        sawCarriageReturn = false
        guard !buffer.isEmpty else { return nil }
        return takeLine()
    }

    private mutating func takeLine() -> [UInt8] {
        defer { buffer.removeAll(keepingCapacity: true) }
        if isFirstLine {
            isFirstLine = false
            if buffer.starts(with: [0xEF, 0xBB, 0xBF]) {
                buffer.removeFirst(3)
            }
        }
        return buffer
    }
}
