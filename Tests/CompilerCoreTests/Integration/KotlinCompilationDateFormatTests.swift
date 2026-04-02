@testable import CompilerCore
import XCTest

final class KotlinCompilationDateFormatTests: XCTestCase {
    func testCompile_dateFormatBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.text.ofPattern

        fun main() {
            val fmt = ofPattern("yyyy-MM-dd", "en_US")
            val text = fmt.format(0L)
        }
        """)
    }
}
