@testable import CompilerCore
import XCTest

final class KotlinCompilationHTTPClientTests: XCTestCase {
    func testCompile_httpClientAdvancedUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.net.http.HttpClient
        import kotlinx.coroutines.runBlocking

        fun main() = runBlocking {
            val client = HttpClient()
            client.setConnectTimeoutMillis(1_000)
            client.setReadTimeoutMillis(2_000)
            client.setFollowRedirects(true)
            client.setDefaultHeader("Accept", "application/json")
            client.setBasicAuth("demo", "secret")
            client.clearAuthentication()
            client.setBearerToken("token-123")

            val syncResponse = client.get("https://example.com")
            val asyncResponse = client.postAsync("https://example.com/api", "payload")

            val code = syncResponse.statusCode
            val body = syncResponse.body
            val ok = asyncResponse.isSuccessful
            val header = asyncResponse.header("content-type")
            val timedOut = asyncResponse.timedOut
            val errorMessage = asyncResponse.errorMessage
            val finalUrl = asyncResponse.url
            val contentType = asyncResponse.contentType
        }
        """)
    }
}
