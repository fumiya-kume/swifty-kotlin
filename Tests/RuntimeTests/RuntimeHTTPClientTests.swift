import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Runtime
import XCTest

final class RuntimeHTTPClientTests: IsolatedRuntimeXCTestCase {
    private final class MockURLProtocol: URLProtocol {
        private static let handlerLock = NSLock()
        nonisolated(unsafe) private static var _handler: ((URLRequest) -> (HTTPURLResponse, Data?, TimeInterval)?)?
        
        static var handler: ((URLRequest) -> (HTTPURLResponse, Data?, TimeInterval)?)? {
            get {
                handlerLock.lock()
                defer { handlerLock.unlock() }
                return _handler
            }
            set {
                handlerLock.lock()
                defer { handlerLock.unlock() }
                _handler = newValue
            }
        }

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = Self.handler,
                  let (response, data, delay) = handler(request)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
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

    func testHTTPClientSupportsAuthRedirectsAndAsyncRequests() {
        setenv("KSWIFTK_HTTP_PROTOCOL_CLASS", NSStringFromClass(MockURLProtocol.self), 1)
        defer {
            MockURLProtocol.handler = nil
            unsetenv("KSWIFTK_HTTP_PROTOCOL_CLASS")
        }
        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            if url == "https://example.com/redirect" {
                let response = HTTPURLResponse(
                    url: URL(string: url)!,
                    statusCode: 302,
                    httpVersion: nil,
                    headerFields: ["Location": "https://example.com/final"]
                )!
                return (response, nil, 0)
            }
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            let response = HTTPURLResponse(
                url: URL(string: url)!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/plain",
                    "X-Echo-Auth": auth,
                ]
            )!
            let body = "method=\(request.httpMethod ?? "GET");auth=\(auth)"
            return (response, Data(body.utf8), 0)
        }

        let clientRaw = kk_http_client_new()
        _ = kk_http_client_setFollowRedirects(clientRaw, 1)
        _ = kk_http_client_setBearerToken(clientRaw, runtimeString("token-123"))

        let responseRaw = kk_http_client_get(clientRaw, runtimeString("https://example.com/final"))
        XCTAssertEqual(kk_http_response_statusCode(responseRaw), 200)
        XCTAssertEqual(stringValue(kk_http_response_body(responseRaw)), "method=GET;auth=Bearer token-123")
        XCTAssertEqual(stringValue(kk_http_response_header(responseRaw, runtimeString("x-echo-auth"))), "Bearer token-123")
        XCTAssertEqual(kk_http_response_isSuccessful(responseRaw), 1)

        let redirectRaw = kk_http_client_get(clientRaw, runtimeString("https://example.com/redirect"))
        XCTAssertEqual(kk_http_response_statusCode(redirectRaw), 200)
        XCTAssertEqual(stringValue(kk_http_response_url(redirectRaw)), "https://example.com/final")

        let continuation = kk_coroutine_continuation_new(0)
        let asyncResult = kk_http_client_post_async(
            clientRaw,
            runtimeString("https://example.com/final"),
            runtimeString("payload"),
            continuation
        )
        XCTAssertEqual(asyncResult, Int(bitPattern: kk_coroutine_suspended()))
        let state = runtimeContinuationState(from: continuation)
        let expectation = expectation(description: "async http resumes")
        state?.installResumeContinuation {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(kk_http_response_statusCode(kk_coroutine_state_get_completion(continuation)), 200)
        _ = kk_coroutine_state_exit(continuation, 0)
    }

    func testHTTPClientEncodesTimeoutAsResponseState() {
        setenv("KSWIFTK_HTTP_PROTOCOL_CLASS", NSStringFromClass(MockURLProtocol.self), 1)
        defer {
            MockURLProtocol.handler = nil
            unsetenv("KSWIFTK_HTTP_PROTOCOL_CLASS")
        }
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/plain"]
            )!
            return (response, Data("slow".utf8), 0.2)
        }

        let clientRaw = kk_http_client_new()
        _ = kk_http_client_setConnectTimeoutMillis(clientRaw, 50)
        _ = kk_http_client_setReadTimeoutMillis(clientRaw, 50)

        let responseRaw = kk_http_client_get(clientRaw, runtimeString("https://example.com/slow"))
        XCTAssertEqual(kk_http_response_statusCode(responseRaw), 0)
        XCTAssertEqual(kk_http_response_timedOut(responseRaw), 1)
        XCTAssertTrue(stringValue(kk_http_response_errorMessage(responseRaw)).isEmpty == false)
    }
}
