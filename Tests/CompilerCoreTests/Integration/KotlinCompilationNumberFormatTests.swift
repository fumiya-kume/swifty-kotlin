@testable import CompilerCore
import XCTest

final class KotlinCompilationNumberFormatTests: XCTestCase {
    func testCompile_numberFormatBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.text.getCurrencyInstance
        import java.text.getIntegerInstance
        import java.text.getNumberInstance
        import java.text.getPercentInstance
        import java.util.Locale

        fun main() {
            val locale = Locale("de_DE")
            val integerFmt = getIntegerInstance(locale)
            val numberFmt = getNumberInstance(locale)
            val currencyFmt = getCurrencyInstance(Locale("en_US"))
            val percentFmt = getPercentInstance(Locale("en_US"))

            val a = integerFmt.format(1234567)
            val b = numberFmt.format(1234.5)
            val c = currencyFmt.format(1234.5)
            val d = percentFmt.format(0.125)
        }
        """)
    }
}
