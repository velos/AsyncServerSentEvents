import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AsyncServerSentEvents

/// Exhaustive coverage of the byte-to-line state machine, which must treat
/// LF, CR, and CRLF as equivalent line terminators per the specification.
@Suite("Line Splitting")
struct SSELineSplittingTests {

    private func splitLines(_ bytes: [UInt8]) -> [String] {
        var splitter = SSELineSplitter()
        var lines: [String] = []
        for byte in bytes {
            if let line = splitter.consume(byte) {
                lines.append(String(decoding: line, as: UTF8.self))
            }
        }
        if let line = splitter.finish() {
            lines.append(String(decoding: line, as: UTF8.self))
        }
        return lines
    }

    private func splitLines(_ text: String) -> [String] {
        splitLines(Array(text.utf8))
    }

    @Test("All three terminators should be equivalent")
    func mixedTerminators() {
        let lines = splitLines("a\rb\nc\r\nd")
        #expect(lines == ["a", "b", "c", "d"])
    }

    @Test("Empty lines should be preserved for every terminator style")
    func emptyLines() {
        // a CR | CR LF (empty line) | LF (empty line) | b (unterminated)
        let lines = splitLines("a\r\r\n\nb")
        #expect(lines == ["a", "", "", "b"])

        let crlfOnly = splitLines("\r\n\r\n")
        #expect(crlfOnly == ["", ""])
    }

    @Test("A CRLF pair should produce exactly one boundary")
    func crlfIsSingleBoundary() {
        let lines = splitLines("a\r\nb")
        #expect(lines == ["a", "b"])
    }

    @Test("Consecutive CRs should each terminate a line")
    func consecutiveCRs() {
        let lines = splitLines("a\r\rb")
        #expect(lines == ["a", "", "b"])
    }

    @Test("Trailing terminators at end of stream should not add lines")
    func trailingTerminators() {
        #expect(splitLines("a\r") == ["a"])
        #expect(splitLines("a\n") == ["a"])
        #expect(splitLines("a\r\n") == ["a"])
    }

    @Test("Edge inputs")
    func edgeInputs() {
        #expect(splitLines("") == [])
        #expect(splitLines("\n") == [""])
        #expect(splitLines("\r") == [""])
        #expect(splitLines("\r\n") == [""])
        #expect(splitLines("a") == ["a"])
    }

    @Test("Other Unicode line separators should not split lines")
    func unicodeSeparatorsAreContent() async throws {
        // NEL (U+0085), LINE SEPARATOR (U+2028), PARAGRAPH SEPARATOR (U+2029)
        let text = "a\u{0085}b\u{2028}c\u{2029}d"
        let lines = splitLines(text + "\n")
        #expect(lines == [text])

        // And they must survive through the full parser as data content.
        let sse = AsyncServerSentEvents(bytes: Array("data: \(text)\n\n".utf8).byteStream)
        let events = try await sse.collect()
        try #require(events.count == 1)
        #expect(events[0].data == text)
    }

    @Test("A trailing CR should act as a blank-line dispatch boundary")
    func trailingCRDispatches() async throws {
        let sse = AsyncServerSentEvents(bytes: Array("data: hi\n\r".utf8).byteStream)
        let events = try await sse.collect()

        try #require(events.count == 1)
        #expect(events[0].data == "hi")
    }

    @Test("A leading BOM should be stripped even with CRLF terminators")
    func bomWithCRLF() async throws {
        let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("data: x\r\n\r\n".utf8)
        let events = try await AsyncServerSentEvents(bytes: bytes.byteStream).collect()

        try #require(events.count == 1)
        #expect(events[0].data == "x")
    }

    @Test("CRLF split across chunk boundaries should stay one boundary")
    func crlfAcrossChunks() async throws {
        let (chunks, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let task = URLSession.shared.dataTask(with: URLRequest(url: URL(string: "https://example.com/sse")!))
        let bytes = SSEByteStream(task: task, chunks: chunks)

        continuation.yield(Data("data: a\r".utf8))
        continuation.yield(Data("\n\r".utf8))
        continuation.yield(Data("\ndata: b\n\n".utf8))
        continuation.finish()

        let events = try await bytes.sse().collect()

        try #require(events.count == 2)
        #expect(events[0].data == "a")
        #expect(events[1].data == "b")
    }

    @Test("Multi-byte characters split across chunk boundaries should decode intact")
    func multiByteAcrossChunks() async throws {
        let (chunks, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let task = URLSession.shared.dataTask(with: URLRequest(url: URL(string: "https://example.com/sse")!))
        let bytes = SSEByteStream(task: task, chunks: chunks)

        let payload = Array("data: é🎉\n\n".utf8)
        // Split in the middle of the emoji's four-byte sequence.
        let splitIndex = payload.count - 5
        continuation.yield(Data(payload[..<splitIndex]))
        continuation.yield(Data(payload[splitIndex...]))
        continuation.finish()

        let events = try await bytes.sse().collect()

        try #require(events.count == 1)
        #expect(events[0].data == "é🎉")
    }
}
