@testable import CompilerCore
import XCTest

final class KotlinCompilationAssertionTests: XCTestCase {
    func testCompile_assertCalls() throws {
        try assertKotlinCompilesToKIR("""
        fun main() {
            assert(true)
            assert(1 < 2) { "ok" }
        }
        """)
    }
}
