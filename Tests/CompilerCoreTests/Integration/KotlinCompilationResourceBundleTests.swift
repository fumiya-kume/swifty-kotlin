@testable import CompilerCore
import XCTest

final class KotlinCompilationResourceBundleTests: XCTestCase {
    func testCompile_resourceBundleBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.Locale
        import java.util.ResourceBundle
        import java.util.getBundle

        fun main() {
            val locale = Locale("ja_JP")
            val bundle = getBundle("messages", locale)
            val greeting = bundle.getString("greeting")
            val obj = bundle.getObject("greeting")
            val keys = bundle.getKeys()
        }
        """)
    }
}
