// SKIP-DIFF: URL.fragment is available in this compiler but not in kotlinc diff reference.
import java.net.URL

fun main() {
    val base = URL("https://example.com/base/index.html?x=1#frag")
    val child = URL(base, "../child?q=a%20b#next")

    println(child.protocol)
    println(child.host)
    println(child.port)
    println(child.path)
    println(child.query)
    println(child.fragment)
    println(child.toExternalForm())
    println(child.toURI().toString())
    println(child.sameFile(URL("https://example.com/child?q=a%20b#other")))
    println(child.equals(URL("https://example.com/child?q=a%20b#next")))
    println(URL("https://example.com/child?q=a%20b#next").hashCode() == child.hashCode())
}
