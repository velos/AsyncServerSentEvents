// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation

public struct AsyncServerSentEvents: AsyncSequence {
    public typealias Element = Event
    typealias Continuation = AsyncStream<Element>.Continuation

    private struct LineSplitter: AsyncSequence {
        typealias Element = String

        let bytes: URLSession.AsyncBytes

        struct AsyncIterator: AsyncIteratorProtocol {
            var iterator: URLSession.AsyncBytes.AsyncIterator
            var buffer: [UInt8] = []
            var pendingLine: String?
            var sawCarriageReturn = false

            mutating func next() async throws -> String? {
                if let line = pendingLine {
                    pendingLine = nil
                    return line
                }

                while let byte = try await iterator.next() {
                    if sawCarriageReturn {
                        sawCarriageReturn = false
                        if byte == 10 {
                            let line = String(bytes: buffer, encoding: .utf8) ?? ""
                            buffer.removeAll(keepingCapacity: true)
                            return line
                        }

                        let line = String(bytes: buffer, encoding: .utf8) ?? ""
                        buffer.removeAll(keepingCapacity: true)

                        if byte == 13 {
                            sawCarriageReturn = true
                            pendingLine = ""
                            return line
                        }

                        if byte == 10 {
                            return line
                        }

                        buffer.append(byte)
                        return line
                    }

                    if byte == 10 {
                        let line = String(bytes: buffer, encoding: .utf8) ?? ""
                        buffer.removeAll(keepingCapacity: true)
                        return line
                    }

                    if byte == 13 {
                        sawCarriageReturn = true
                        let line = String(bytes: buffer, encoding: .utf8) ?? ""
                        buffer.removeAll(keepingCapacity: true)
                        return line
                    }

                    buffer.append(byte)
                }

                if sawCarriageReturn {
                    sawCarriageReturn = false
                    let line = String(bytes: buffer, encoding: .utf8) ?? ""
                    buffer.removeAll(keepingCapacity: true)
                    return line
                }

                if buffer.isEmpty {
                    return nil
                }

                let line = String(bytes: buffer, encoding: .utf8) ?? ""
                buffer.removeAll(keepingCapacity: true)
                return line
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(iterator: bytes.makeAsyncIterator())
        }
    }

    public struct Event: Hashable, Sendable, Equatable {
        public var id: String?
        public var name: String?
        public var comment: String?
        public var data: String

        mutating func appending(commentLine: String) {
            if comment != nil  {
                comment?.append(commentLine + "\n")
            } else if !commentLine.isEmpty {
                comment = commentLine + "\n"
            }
        }

        mutating func appending(dataLine: String) {
            data.append(dataLine + "\n")
        }

        mutating func trim() {
            data = data.trimmingCharacters(in: .whitespacesAndNewlines)
            comment = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private let stream: AsyncStream<Element>
    private let continuation: Continuation

    public init(bytes: URLSession.AsyncBytes) {
        (stream, continuation) = AsyncStream<Element>.makeStream()

        Task { [continuation] in
            do {
                let lines = LineSplitter(bytes: bytes)

                let emptyEvent = Event(data: "")
                var event = emptyEvent
                for try await line in lines {
                    if line.isEmpty {
                        if !event.data.isEmpty {
                            if event.data.hasSuffix("\n") {
                                event.data.removeLast()
                            }
                            continuation.yield(event)
                        }
                        event = emptyEvent
                    } else {
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
                        case "id":
                            if !value.contains("\0") {
                                event.id = value
                            }
                        case "event":
                            event.name = value
                        case "":
                            continue
                        case "data":
                            event.appending(dataLine: value)
                        default:
                            continue
                        }
                    }
                }

                continuation.finish()
            } catch {
                print("ERROR: \(error)")
            }
        }
    }

    public func makeAsyncIterator() -> AsyncStream<Element>.AsyncIterator {
        stream.makeAsyncIterator()
    }
}
