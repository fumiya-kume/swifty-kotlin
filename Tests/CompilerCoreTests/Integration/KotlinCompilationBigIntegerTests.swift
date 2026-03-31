@testable import CompilerCore
import XCTest

final class KotlinCompilationBigIntegerTests: XCTestCase {
    func testCompile_bigIntegerAndExtension() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("12")
            val b = BigInteger("10")
            val infix = a and b
            val dotted = a.and(b)
            val text = infix.toString() + dotted.toString()
        }
        """)
    }
}
