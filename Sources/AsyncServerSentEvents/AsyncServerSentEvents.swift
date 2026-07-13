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
/// and errors from the byte stream are rethrown to the consumer. The parsing
/// itself is performed by ``SSEParser``, which is also available directly for
/// non-async byte sources.
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
        AsyncIterator(base: base.makeAsyncIterator(), state: state)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        var parser = SSEParser()
        let state: SSEState

        private var mirroredRetryInterval: Int?
        private var mirroredLastEventId: String?
        private var finished = false

        init(base: Base.AsyncIterator, state: SSEState) {
            self.base = base
            self.state = state
        }

        public mutating func next() async throws -> ServerSentEvent? {
            guard !finished else { return nil }

            while let byte = try await base.next() {
                let event = parser.consume(byte)
                await mirrorStateIfChanged()
                if let event {
                    return event
                }
            }

            // End of stream: the incomplete final block is discarded per spec,
            // but a trailing retry field still takes effect.
            finished = true
            parser.finish()
            await mirrorStateIfChanged()
            return nil
        }

        /// Keeps the public ``SSEState`` actor in sync with the parser,
        /// hopping to the actor only when a value actually changed.
        private mutating func mirrorStateIfChanged() async {
            if parser.retryInterval != mirroredRetryInterval, let interval = parser.retryInterval {
                mirroredRetryInterval = interval
                await state.updateRetryInterval(interval)
            }
            if parser.lastEventId != mirroredLastEventId, let id = parser.lastEventId {
                mirroredLastEventId = id
                await state.updateLastEventId(id)
            }
        }
    }
}

extension AsyncServerSentEvents: Sendable where Base: Sendable {}

public extension AsyncSequence where Element == UInt8 {
    /// Parses these bytes as a server-sent event stream.
    func sse() -> AsyncServerSentEvents<Self> {
        AsyncServerSentEvents(bytes: self)
    }
}
