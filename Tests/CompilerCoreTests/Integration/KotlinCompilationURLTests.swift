@testable import CompilerCore
import XCTest

final class KotlinCompilationURLTests: XCTestCase {
    func testCompile_urlBasicOperations() throws {
        try assertKotlinCompilesToKIR("""
        import java.net.URL

        fun main() {
            val base = URL("https://example.com/base/index.html?x=1#frag")
            val child = URL(base, "../child?q=1#next")
            val protocol = child.protocol
            val host = child.host
            val port = child.port
            val path = child.path
            val query = child.query
            val fragment = child.fragment
            val uri = child.toURI()
            val external = child.toExternalForm()
            val same = child.sameFile(URL("https://example.com/child?q=1#other"))
            val equal = child.equals(URL("https://example.com/child?q=1#next"))
            val hash = child.hashCode()
        }
        """)
    }
}
