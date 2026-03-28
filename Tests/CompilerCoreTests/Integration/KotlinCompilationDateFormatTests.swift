@testable import CompilerCore
import XCTest

final class KotlinCompilationDateFormatTests: XCTestCase {
    func testCompile_dateFormatBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.text.ofPattern
        import java.util.Locale

        fun main() {
            val locale = Locale("en_US")
            val fmt = ofPattern("yyyy-MM-dd", locale)
            val text = fmt.format(0L)
        }
        """)
    }
}
