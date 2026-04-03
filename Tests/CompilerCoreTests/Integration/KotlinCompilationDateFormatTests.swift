@testable import CompilerCore
import XCTest

final class KotlinCompilationDateFormatTests: XCTestCase {
    func testCompile_dateFormatBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.text.ofPattern
        import java.text.getDateInstance
        import java.text.getTimeInstance
        import java.text.getDateTimeInstance

        fun main() {
            val fmt = ofPattern("yyyy-MM-dd", "en_US")
            val text = fmt.format(0L)
            val zoned = ofPattern("yyyy-MM-dd HH:mm z", "en_US", "Asia/Tokyo").format(0L)
            val dateOnly = getDateInstance("ja_JP").format(0L)
            val timeOnly = getTimeInstance("en_US", "UTC").format(0L)
            val dateTime = getDateTimeInstance("en_US", "Asia/Tokyo").format(0L)
        }
        """)
    }
}
