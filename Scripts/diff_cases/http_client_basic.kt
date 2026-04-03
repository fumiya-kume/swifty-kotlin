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

    println(getRequest != null)
    println(postRequest != null)
    println(client != null)
    println(HttpResponse.BodyHandlers.ofString() != null)
}
