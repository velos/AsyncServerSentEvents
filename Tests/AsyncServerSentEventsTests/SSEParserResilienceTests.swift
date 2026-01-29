//
//  SSEParserResilienceTests.swift
//  AsyncServerSentEvents
//
//  Created by Zac White on 10/24/24.
//

import Testing
import Foundation
@testable import AsyncServerSentEvents

@Suite("Server-Sent Events Parser Resilience")
struct SSEParserResilienceTests {

    @Test("Parser should ignore invalid field names")
    func invalidFields() async throws {
        let bytes = try await SSETestData.invalidFields.asyncBytes
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        // No valid events should be created from invalid field names
        #expect(events.isEmpty)
    }

    @Test("Parser should handle unusual whitespace")
    func unusualWhitespace() async throws {
        let bytes = try await SSETestData.unusualWhitespace.asyncBytes
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)

        let expectedData = "\ttab after colon\n    many spaces after colon"

        #expect(events[0].data == expectedData)
    }

    @Test("Parser should normalize mixed line endings")
    func mixedLineEndings() async throws {
        let bytes = try await SSETestData.mixedLineEndings.asyncBytes
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 4)

        #expect(events.allSatisfy { $0.data == "test" })
    }

    @Test("Parser should ignore almost-valid fields")
    func almostValidFields() async throws {
        let bytes = try await SSETestData.almostValidFields.asyncBytes
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        // No events should be created from almost-valid field names
        #expect(events.isEmpty)
    }

    @Test("Parser should handle Unicode whitespace")
    func unicodeWhitespace() async throws {
        let bytes = try await SSETestData.unicodeWhitespace.asyncBytes
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)

        let expectedData = "\u{200B}zero-width space\n\u{3000}ideographic space\n\u{3000}"

        #expect(events[0].data == expectedData)
    }

    @Test("Parser should process all resilience tests without crashing")
    func allResilienceTests() async throws {
        for testCase in SSETestData.allResilienceTests {
            let bytes = try await testCase.asyncBytes
            let sse = AsyncServerSentEvents(bytes: bytes)

            // Should not throw when collecting events
            _ = try await sse.collect()
        }
    }

    @Test("Parser should maintain state across malformed input")
    func stateAfterMalformedInput() async throws {
        // Combine invalid fields with a valid event
        let testData = """
        invalid-field:test
        DATA:wrong case

        data:valid event
        id:123

        dAtA:mixed case
        """

        let bytes = try await testData.asyncBytes
        let sse = AsyncServerSentEvents(bytes: bytes)
        let events = try await sse.collect()

        try #require(events.count == 1)

        #expect(events[0].data == "valid event")
        #expect(events[0].id == "123")
    }
}
