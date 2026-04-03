// SKIP-DIFF: kswiftc's native HTTP client runtime is intentionally not part of kotlinc parity.
import java.net.http.HttpClient
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    val client = HttpClient()
    client.setConnectTimeoutMillis(1_000)
    client.setReadTimeoutMillis(2_000)
    client.setFollowRedirects(true)
    client.setDefaultHeader("Accept", "text/plain")
    client.setBasicAuth("demo", "secret")
    client.clearAuthentication()
    client.setBearerToken("token-123")

    println("http-client-configured")

    val base = "https://example.com"
    val syncResponse = client.get(base)
    println(syncResponse.statusCode)
    println(syncResponse.isSuccessful)
    println(syncResponse.contentType ?: "no-content-type")
    println(syncResponse.errorMessage ?: "no-error")

    val asyncResponse = client.postAsync(base, "payload")
    println(asyncResponse.statusCode)
    println(asyncResponse.url)
    println(asyncResponse.timedOut)
    println(asyncResponse.header("content-type") ?: "no-header")
}
