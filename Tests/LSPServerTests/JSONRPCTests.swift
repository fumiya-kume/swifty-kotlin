import Foundation
@testable import LSPServer
import XCTest

final class JSONRPCTests: XCTestCase {
    func testRoundTripSingleMessage() {
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": ["rootUri": "file:///tmp"],
        ]
        let input = MemoryInputStream(LSPTestSupport.frame(message))
        let connection = JSONRPCConnection(input: input, output: MemoryOutputStream())

        let received = connection.receive()
        XCTAssertEqual(received?["method"] as? String, "initialize")
        XCTAssertEqual(received?["id"] as? Int, 1)
        XCTAssertNil(connection.receive(), "Stream should be exhausted after one message")
    }

    func testReadsMultipleMessagesAcrossChunkBoundaries() {
        let first = LSPTestSupport.frame(["jsonrpc": "2.0", "method": "a"])
        let second = LSPTestSupport.frame(["jsonrpc": "2.0", "method": "b"])
        // Split the combined stream at an arbitrary mid-point to exercise buffering.
        var combined = first
        combined.append(second)
        let mid = combined.count / 2
        let chunks = [combined.prefix(mid), combined.suffix(from: mid)].map { Data($0) }

        let connection = JSONRPCConnection(input: MemoryInputStream(chunks: chunks), output: MemoryOutputStream())
        XCTAssertEqual(connection.receive()?["method"] as? String, "a")
        XCTAssertEqual(connection.receive()?["method"] as? String, "b")
        XCTAssertNil(connection.receive())
    }

    func testSendProducesParseableFrame() {
        let output = MemoryOutputStream()
        let connection = JSONRPCConnection(input: MemoryInputStream(Data()), output: output)
        connection.send(["jsonrpc": "2.0", "id": 7, "result": NSNull()])

        let text = String(decoding: output.data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("Content-Length: "), "Frame must start with the header")

        let messages = LSPTestSupport.decodeMessages(from: output)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["id"] as? Int, 7)
    }
}
