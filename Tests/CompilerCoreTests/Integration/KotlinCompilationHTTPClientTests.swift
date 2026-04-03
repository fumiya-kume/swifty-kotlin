@testable import CompilerCore
import XCTest

final class KotlinCompilationHTTPClientTests: XCTestCase {
    func testCompile_httpClientBasicOperations() throws {
        try assertKotlinCompilesToKIR("""
        import java.net.URI
        import java.net.http.HttpClient
        import java.net.http.HttpRequest
        import java.net.http.HttpResponse

        fun main() {
            val client = HttpClient.newHttpClient()
            val getRequest = HttpRequest.newBuilder(URI("https://example.com"))
                .header("Accept", "text/plain")
                .GET()
                .build()

            val postRequest = HttpRequest.newBuilder()
                .uri(URI("https://example.com/post"))
                .header("Content-Type", "text/plain")
                .POST(HttpRequest.BodyPublishers.ofString("payload"))
                .build()

            val response = client.send(getRequest, HttpResponse.BodyHandlers.ofString())
            val status = response.statusCode()
            val body = response.body()
            val headers = response.headers()
            val contentType = headers.firstValue("Content-Type")
            val headerMap = headers.map()
            val postResponse = client.send(postRequest, HttpResponse.BodyHandlers.ofString())
            val postStatus = postResponse.statusCode()
        }
        """)
    }
}
