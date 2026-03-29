@testable import CompilerCore
import XCTest

final class KotlinCompilationMessageDigestTests: XCTestCase {
    func testCompile_messageDigestBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.security.getInstance

        fun main() {
            val md = getInstance("SHA-256")
            val bytes = mutableListOf(97, 98, 99)
            val digest = md.digest(bytes)
        }
        """)
    }
}
