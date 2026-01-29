import Testing
import Foundation

@Suite("URLSession Extension Tests")
struct URLSessionExtensionTests {

    let localFileUrl: URL

    init() throws {
        let tempFile = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
        let body = "data: hello\nid: 123\nevent: message\n\n"
        try body.data(using: .utf8)!.write(to: tempFile)

        localFileUrl = tempFile
    }

    @Test("sse()")
    func testSSE() async throws {
        let (sse, _) = try await URLSession.shared.serverSentEvents(from: localFileUrl)
        let events = try await sse.collect()
        #expect(events.count == 1)
    }

    @Test("serverSentEvents(from:)")
    func testServerSentEventsFrom() async throws {
        let (sse, _) = try await URLSession.shared.serverSentEvents(from: localFileUrl)
        let events = try await sse.collect()
        #expect(events.count == 1)
    }

    @Test("serverSentEvents(for:)")
    func testServerSentEventsFor() async throws {
        let request = URLRequest(url: localFileUrl)
        let (sse, _) = try await URLSession.shared.serverSentEvents(for: request)
        let events = try await sse.collect()
        #expect(events.count == 1)
    }
}

