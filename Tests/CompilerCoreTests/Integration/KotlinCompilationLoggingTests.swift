@testable import CompilerCore
import XCTest

final class KotlinCompilationLoggingTests: XCTestCase {
    func testCompile_basicLoggerUsage() throws {
        try assertKotlinCompilesToKIR("""
        import java.util.logging.getLogger
        import java.util.logging.INFO
        import java.util.logging.CONFIG
        import java.util.logging.FINE
        import java.util.logging.FINER
        import java.util.logging.FINEST

        fun main() {
            val logger = getLogger("demo")
            logger.info("hello")
            logger.warning("warn")
            logger.severe("boom")
            logger.log(INFO, "again")
            logger.log(CONFIG, "cfg")
            logger.log(FINE, "fine")
            logger.log(FINER, "finer")
            logger.log(FINEST, "finest")
        }
        """)
    }
}
