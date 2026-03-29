@testable import CompilerCore
import XCTest

final class KotlinCompilationLoggingTests: XCTestCase {
    func testCompile_basicLoggerUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.logging.getLogger
        import java.util.logging.INFO

        fun main() {
            val logger = getLogger("demo")
            logger.info("hello")
            logger.warning("warn")
            logger.severe("boom")
            logger.log(INFO, "again")
        }
        """)
    }
}
