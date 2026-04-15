import Foundation
@testable import Runtime
import XCTest

final class RuntimeNetworkTests: IsolatedRuntimeXCTestCase {
    private final class HTTPTestServer {
        private static let serverStartupTimeout: TimeInterval = 5
        private static let serverShutdownTimeout: TimeInterval = 5
        private static let serverShutdownPollInterval: TimeInterval = 0.05
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let scriptURL: URL
        let directoryURL: URL
        let port: Int

        init() throws {
            directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            scriptURL = directoryURL.appendingPathComponent("server.py")
            try serverScript.write(to: scriptURL, atomically: true, encoding: .utf8)

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "-u", scriptURL.path]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try process.run()
            port = try Self.readPort(from: stdoutPipe.fileHandleForReading, process: process)
        }

        deinit {
            stop()
        }

        func stop() {
            if process.isRunning {
                process.terminate()
                let deadline = Date().addingTimeInterval(Self.serverShutdownTimeout)
                while process.isRunning, Date() < deadline {
                    Thread.sleep(forTimeInterval: Self.serverShutdownPollInterval)
                }
                if process.isRunning {
                    process.interrupt()
                    let interruptDeadline = Date().addingTimeInterval(Self.serverShutdownTimeout)
                    while process.isRunning, Date() < interruptDeadline {
                        Thread.sleep(forTimeInterval: Self.serverShutdownPollInterval)
                    }
                    if process.isRunning {
                        // Note: There's a race condition between this check and the kill() call where the process
                        // could exit and the PID could be reused. This is a fundamental limitation of the kill() API.
                        let killResult = kill(process.processIdentifier, SIGKILL)
                        if killResult != 0 && errno != ESRCH {
                            // kill() failed with error other than ESRCH (no such process)
                            // ESRCH is expected if process exited between isRunning check and kill call
                            // Other errors are unusual but we continue anyway
                        }
                        let sigkillDeadline = Date().addingTimeInterval(1.0)
                        while process.isRunning, Date() < sigkillDeadline {
                            Thread.sleep(forTimeInterval: Self.serverShutdownPollInterval)
                        }
                    }
                }
            }
            try? FileManager.default.removeItem(at: directoryURL)
        }

        private static func readPort(from handle: FileHandle, process: Process) throws -> Int {
            var bytes = Data()
            let deadline = Date().addingTimeInterval(serverStartupTimeout)
            while true {
                if Date() >= deadline {
                    throw NSError(domain: "RuntimeNetworkTests", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Timed out waiting for HTTP test server port"
                    ])
                }
                if !process.isRunning, bytes.isEmpty {
                    throw NSError(domain: "RuntimeNetworkTests", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "HTTP test server exited before reporting a port"
                    ])
                }
                let chunk = try handle.read(upToCount: 1) ?? Data()
                if chunk.isEmpty { break }
                if chunk[chunk.startIndex] == 10 { break }
                bytes.append(chunk)
            }
            guard let text = String(data: bytes, encoding: .utf8),
                  let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                throw NSError(domain: "RuntimeNetworkTests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to read HTTP test server port"
                ])
            }
            return port
        }

        private let serverScript = """
import http.server
import socketserver
import sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        header = self.headers.get("X-Test", "")
        body = f"GET:{header}".encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("X-Echo", header)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        payload = self.rfile.read(length).decode("utf-8")
        body = f"POST:{payload}".encode("utf-8")
        self.send_response(201)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("X-Method", "POST")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        return

class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True

with ThreadedTCPServer(("127.0.0.1", 0), Handler) as httpd:
    print(httpd.server_address[1], flush=True)
    httpd.serve_forever()
"""
    }

    private func runtimeString(_ text: String) -> Int {
        text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(text.utf8.count)))
            }
        }
    }

    private func stringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func listStrings(_ raw: Int) -> [String] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let list = tryCast(ptr, to: RuntimeListBox.self)
        else {
            return []
        }
        return list.elements.map(stringValue)
    }

    private func mapStringsToLists(_ raw: Int) -> [String: [String]] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let map = tryCast(ptr, to: RuntimeMapBox.self)
        else {
            return [:]
        }
        var result: [String: [String]] = [:]
        for (index, keyRaw) in map.keys.enumerated() where index < map.values.count {
            result[stringValue(keyRaw)] = listStrings(map.values[index])
        }
        return result
    }

    func testHTTPClientSupportsGetAndPost() throws {
        let server = try HTTPTestServer()
        defer { server.stop() }

        var thrown = 0
        let clientRaw = kk_http_client_newHttpClient()
        let responseHandlerRaw = kk_http_body_handlers_ofString(0)

        let getURI = kk_uri_new(runtimeString("http://127.0.0.1:\(server.port)/get"), &thrown)
        XCTAssertEqual(thrown, 0)
        let getBuilderRaw = kk_http_request_newBuilder_uri(getURI)
        _ = kk_http_request_builder_header(getBuilderRaw, runtimeString("X-Test"), runtimeString("alpha"))
        _ = kk_http_request_builder_GET(getBuilderRaw)
        let getRequestRaw = kk_http_request_builder_build(getBuilderRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        let getResponseRaw = kk_http_client_send(clientRaw, getRequestRaw, responseHandlerRaw, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_http_response_statusCode(getResponseRaw), 200)
        XCTAssertEqual(stringValue(kk_http_response_body(getResponseRaw)), "GET:alpha")

        let getHeadersRaw = kk_http_response_headers(getResponseRaw)
        XCTAssertEqual(stringValue(kk_http_headers_firstValue(getHeadersRaw, runtimeString("X-Echo"))), "alpha")
        let getHeaderMap = mapStringsToLists(kk_http_headers_map(getHeadersRaw))
        XCTAssertEqual(getHeaderMap["X-Echo"]?.first, "alpha")

        let postURI = kk_uri_new(runtimeString("http://127.0.0.1:\(server.port)/post"), &thrown)
        XCTAssertEqual(thrown, 0)
        let postBuilderRaw = kk_http_request_newBuilder()
        _ = kk_http_request_builder_uri(postBuilderRaw, postURI)
        _ = kk_http_request_builder_header(postBuilderRaw, runtimeString("Content-Type"), runtimeString("text/plain"))
        let publisherRaw = kk_http_body_publishers_ofString(0, runtimeString("payload"))
        _ = kk_http_request_builder_POST(postBuilderRaw, publisherRaw)
        let postRequestRaw = kk_http_request_builder_build(postBuilderRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        let postResponseRaw = kk_http_client_send(clientRaw, postRequestRaw, responseHandlerRaw, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_http_response_statusCode(postResponseRaw), 201)
        XCTAssertEqual(stringValue(kk_http_response_body(postResponseRaw)), "POST:payload")
        let postHeadersRaw = kk_http_response_headers(postResponseRaw)
        XCTAssertEqual(stringValue(kk_http_headers_firstValue(postHeadersRaw, runtimeString("X-Method"))), "POST")
    }

    func testHTTPRequestBuildThrowsWithoutURI() {
        var thrown = 0
        let builderRaw = kk_http_request_newBuilder()
        let requestRaw = kk_http_request_builder_build(builderRaw, &thrown)
        XCTAssertEqual(requestRaw, 0)
        XCTAssertNotEqual(thrown, 0)
    }
}
