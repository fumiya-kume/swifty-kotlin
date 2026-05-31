import Foundation
@testable import LSPServer

/// An in-memory input stream that replays preloaded chunks and then signals EOF.
final class MemoryInputStream: ByteInputStream {
    private var chunks: [Data]

    init(_ data: Data) {
        chunks = [data]
    }

    init(chunks: [Data]) {
        self.chunks = chunks
    }

    func readChunk() -> Data {
        chunks.isEmpty ? Data() : chunks.removeFirst()
    }
}

/// An in-memory output stream that accumulates everything written to it.
final class MemoryOutputStream: ByteOutputStream {
    private(set) var data = Data()

    func write(_ data: Data) {
        self.data.append(data)
    }
}

enum LSPTestSupport {
    /// Assembles a JSON-RPC message dictionary.
    static func message(id: Int? = nil, method: String? = nil, params: Any? = nil) -> [String: Any] {
        var message: [String: Any] = ["jsonrpc": "2.0"]
        if let id { message["id"] = id }
        if let method { message["method"] = method }
        if let params { message["params"] = params }
        return message
    }

    /// Frames a JSON object using the LSP base protocol header.
    static func frame(_ object: [String: Any]) -> Data {
        let body = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var framed = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        framed.append(body)
        return framed
    }

    /// Frames and concatenates a sequence of JSON objects.
    static func frame(_ objects: [[String: Any]]) -> Data {
        var data = Data()
        for object in objects {
            data.append(frame(object))
        }
        return data
    }

    /// Reads every framed message produced on an output stream's buffer.
    static func decodeMessages(from output: MemoryOutputStream) -> [[String: Any]] {
        let connection = JSONRPCConnection(input: MemoryInputStream(output.data), output: MemoryOutputStream())
        var messages: [[String: Any]] = []
        while let message = connection.receive() {
            messages.append(message)
        }
        return messages
    }

    /// Returns the 0-based (line, UTF-16 character) position of the first
    /// occurrence of `needle` in `text`.
    static func position(of needle: String, in text: String) -> (line: Int, character: Int)? {
        guard let range = text.range(of: needle) else { return nil }
        let prefix = text[text.startIndex ..< range.lowerBound]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        let line = lines.count - 1
        let lastLine = lines.last ?? ""
        return (line: line, character: lastLine.utf16.count)
    }
}
