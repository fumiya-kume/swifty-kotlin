@testable import CompilerCore
import XCTest

final class KotlinCompilationURITests: XCTestCase {
    func testCompile_uriBasicOperations() throws {
        try assertKotlinCompilesToKIR("""
        import java.net.URI

        fun main() {
            val uri = URI("https://example.com/base/../path?q=1#frag")
            val scheme = uri.scheme
            val authority = uri.authority
            val path = uri.path
            val query = uri.query
            val fragment = uri.fragment
            val normalized = uri.normalize()
            val resolved = uri.resolve("child")
            val relative = uri.relativize(normalized)
            val text = uri.toString()
        }
        """)
    }
}
