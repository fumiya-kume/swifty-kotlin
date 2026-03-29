@testable import CompilerCore
import XCTest

final class KotlinCompilationAdvancedLoggingTests: XCTestCase {
    func testCompile_advancedLoggingUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.logging.getLogger
        import java.util.logging.INFO
        import java.util.logging.ConsoleHandler
        import java.util.logging.FileHandler

        fun main() {
            val logger = getLogger("demo")
            logger.addHandler(ConsoleHandler())
            logger.addHandler(FileHandler("demo.log"))
            logger.log(INFO, "hello")
        }
        """)
    }
}
