import Foundation

/// A single event parsed from a server-sent event stream.
///
/// See [the WHATWG specification](https://html.spec.whatwg.org/multipage/server-sent-events.html)
/// for details on the wire format.
public struct ServerSentEvent: Hashable, Sendable {
    /// The value of the `id` field explicitly present in this event's block, if any.
    public var id: String?

    /// The raw value of the `event` field, if present. See ``type`` for the
    /// dispatch type with the spec's `"message"` default applied.
    public var name: String?

    /// The event's data. Multiple `data` fields are joined with newlines per the spec.
    public var data: String

    /// The last event ID string in effect when this event was dispatched.
    ///
    /// Per the specification, the last event ID persists across events: an event
    /// without an `id` field inherits the most recently seen ID. This is the value
    /// to resume from (via the `Last-Event-ID` header) when reconnecting.
    public var lastEventId: String?

    /// The event type used for dispatch: ``name`` when non-empty, otherwise
    /// `"message"`, matching `EventSource` semantics in the specification.
    public var type: String {
        if let name, !name.isEmpty {
            return name
        }
        return "message"
    }

    public init(id: String? = nil, name: String? = nil, data: String = "", lastEventId: String? = nil) {
        self.id = id
        self.name = name
        self.data = data
        self.lastEventId = lastEventId
    }

    mutating func appending(dataLine: String) {
        data.append(dataLine + "\n")
    }
}

/// Stream-level state observed while parsing, shared between the parser and the consumer.
public actor SSEState {
    /// The reconnection time in milliseconds from the most recent valid `retry` field.
    public private(set) var retryInterval: Int?

    /// The last event ID committed by a dispatched event block.
    public private(set) var lastEventId: String?

    func updateRetryInterval(_ milliseconds: Int) {
        retryInterval = milliseconds
    }

    func updateLastEventId(_ value: String) {
        lastEventId = value
    }
}

/// An `AsyncSequence` of ``ServerSentEvent`` values parsed from a stream of UTF-8 bytes.
///
/// Parsing is driven lazily by iteration: bytes are only read from the underlying
/// sequence as events are requested, cancellation propagates to the byte stream,
/// and errors from the byte stream are rethrown to the consumer.
///
/// The sequence is single-pass: iterate it once.
public struct AsyncServerSentEvents<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    public typealias Element = ServerSentEvent
    public typealias Event = ServerSentEvent

    /// Stream-level state (`retry` interval and committed last event ID).
    public let state: SSEState

    private let base: Base

    public init(bytes: Base) {
        self.base = bytes
        self.state = SSEState()
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(lines: SSELineIterator(base: base.makeAsyncIterator()), state: state)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var lines: SSELineIterator<Base.AsyncIterator>
        let state: SSEState

        /// The last event ID buffer; per spec this persists across events and is
        /// only committed to ``SSEState`` when a block is dispatched.
        var lastEventIdBuffer: String?
        var committedLastEventId: String?

        public mutating func next() async throws -> ServerSentEvent? {
            var event = ServerSentEvent(data: "")

            while let line = try await lines.next() {
                guard !line.isEmpty else {
                    // Blank line: dispatch the block. The last event ID commits
                    // even when no event is emitted (e.g. an id-only block).
                    if let id = lastEventIdBuffer, id != committedLastEventId {
                        committedLastEventId = id
                        await state.updateLastEventId(id)
                    }

                    guard !event.data.isEmpty else {
                        event = ServerSentEvent(data: "")
                        continue
                    }

                    if event.data.hasSuffix("\n") {
                        event.data.removeLast()
                    }
                    event.lastEventId = lastEventIdBuffer
                    return event
                }

                var elements = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                if elements.count == 1 {
                    elements.append("")
                }

                let field = String(elements[0])
                var value = String(elements[1])
                if value.first == " " {
                    value.removeFirst()
                }

                switch field {
                case "data":
                    event.appending(dataLine: value)
                case "event":
                    event.name = value
                case "id":
                    if !value.contains("\0") {
                        event.id = value
                        lastEventIdBuffer = value
                    }
                case "retry":
                    if !value.isEmpty,
                       value.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
                       let milliseconds = Int(value) {
                        await state.updateRetryInterval(milliseconds)
                    }
                default:
                    // Comment lines (empty field name) and unknown fields are ignored.
                    continue
                }
            }

            // End of stream: an incomplete final block is discarded per spec,
            // including any id it carried.
            return nil
        }
    }
}

extension AsyncServerSentEvents: Sendable where Base: Sendable {}

/// Splits a byte stream into lines terminated by LF, CR, or CRLF, decoding
/// UTF-8 with replacement characters and stripping a single leading BOM,
/// as required by the specification.
///
/// The state machine treats CR as an immediate line terminator and swallows an
/// LF that directly follows it, so `CR LF` yields one line boundary while
/// `CR CR` yields two. Only CR, LF, and CRLF are boundaries — other Unicode
/// line separators (NEL, U+2028, U+2029) are ordinary content bytes per spec.
struct SSELineIterator<BaseIterator: AsyncIteratorProtocol> where BaseIterator.Element == UInt8 {
    var base: BaseIterator
    var buffer: [UInt8] = []
    var sawCarriageReturn = false
    var isFirstLine = true
    var atEnd = false

    mutating func next() async throws -> String? {
        guard !atEnd else { return nil }

        while true {
            guard let byte = try await base.next() else {
                atEnd = true
                if buffer.isEmpty {
                    return nil
                }
                return makeLine()
            }

            if sawCarriageReturn {
                sawCarriageReturn = false
                if byte == 0x0A { // LF completing a CRLF pair
                    continue
                }
            }

            switch byte {
            case 0x0A:
                return makeLine()
            case 0x0D:
                sawCarriageReturn = true
                return makeLine()
            default:
                buffer.append(byte)
            }
        }
    }

    private mutating func makeLine() -> String {
        defer { buffer.removeAll(keepingCapacity: true) }
        if isFirstLine {
            isFirstLine = false
            if buffer.starts(with: [0xEF, 0xBB, 0xBF]) {
                buffer.removeFirst(3)
            }
        }
        return String(decoding: buffer, as: UTF8.self)
    }
}
