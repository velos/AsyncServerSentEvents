import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A minimal scripted HTTP server for exercising the streaming connection path
/// end-to-end on both Darwin and Linux (corelibs `URLSession` does not support
/// `file:` URLs for data tasks).
///
/// Each accepted connection consumes the next scripted response; once the
/// script is exhausted, further connections receive `204 No Content`, which is
/// also the specification's "stop reconnecting" signal for `EventSource`.
final class TestHTTPServer: @unchecked Sendable {
    struct Response {
        var status = "200 OK"
        var contentType: String? = "text/event-stream"
        var body = ""
    }

    let port: UInt16
    private let listenSocket: Int32
    private let lock = NSLock()
    private var receivedRequests: [String] = []

    /// The raw request heads received so far, in connection order.
    var requests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return receivedRequests
    }

    init(responses: [Response]) throws {
        signal(SIGPIPE, SIG_IGN)

        #if canImport(Darwin)
        let socketType = SOCK_STREAM
        #else
        let socketType = Int32(SOCK_STREAM.rawValue)
        #endif
        let socketDescriptor = socket(AF_INET, socketType, 0)
        precondition(socketDescriptor >= 0, "socket() failed")

        var reuse: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: UInt32(0x7F000001).bigEndian) // 127.0.0.1
        address.sin_port = 0 // any free port

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        precondition(bound == 0, "bind() failed")
        precondition(listen(socketDescriptor, 8) == 0, "listen() failed")

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketDescriptor, $0, &length)
            }
        }

        listenSocket = socketDescriptor
        port = UInt16(bigEndian: assigned.sin_port)
        var remaining = responses
        let thread = Thread { [weak self] in
            while true {
                let client = accept(socketDescriptor, nil, nil)
                guard client >= 0 else { return }
                self?.record(Self.readRequestHead(from: client))
                let response = remaining.isEmpty
                    ? Response(status: "204 No Content", contentType: nil, body: "")
                    : remaining.removeFirst()
                Self.send(response: response, to: client)
                close(client)
            }
        }
        thread.start()
    }

    func stop() {
        close(listenSocket)
    }

    private func record(_ request: String) {
        lock.lock()
        receivedRequests.append(request)
        lock.unlock()
    }

    private static func readRequestHead(from fd: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let terminator = Data("\r\n\r\n".utf8)
        while data.range(of: terminator) == nil && data.count < 16384 {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func send(response: Response, to fd: Int32) {
        var head = "HTTP/1.1 \(response.status)\r\n"
        if let contentType = response.contentType {
            head += "Content-Type: \(contentType)\r\n"
        }
        let body = Array(response.body.utf8)
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"

        let bytes = Array(head.utf8) + body
        var sent = 0
        while sent < bytes.count {
            let result = bytes.withUnsafeBytes { pointer -> Int in
                #if canImport(Darwin)
                Darwin.send(fd, pointer.baseAddress! + sent, bytes.count - sent, 0)
                #else
                Glibc.send(fd, pointer.baseAddress! + sent, bytes.count - sent, Int32(MSG_NOSIGNAL))
                #endif
            }
            guard result > 0 else { break }
            sent += result
        }
    }
}
