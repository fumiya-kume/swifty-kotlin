@testable import CompilerCore
import XCTest

final class KotlinCompilationResourceTests: XCTestCase {
    func testCompile_resourceAccessHelpers() throws {
        try assertKotlinCompilesToKIR("""
        import java.lang.getSystemClassLoader
        import kotlin.io.resourceExists
        import kotlin.io.readResourceAsText

        fun main() {
            val loader = getSystemClassLoader()
            val path = loader.getResource("hello.txt")
            val stream = loader.getResourceAsStream("hello.txt")
            val exists = resourceExists("hello.txt")
            val text = readResourceAsText("hello.txt")
            val first = stream?.read()
            stream?.close()
        }
        """)
    }
}
