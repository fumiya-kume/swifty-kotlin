@testable import CompilerCore
import XCTest

final class KotlinCompilationFileIOTests: XCTestCase {
    func testCompile_file_inputOutputStreams() throws {
        try assertKotlinCompilesToKIR("""
        import java.io.File

        fun main() {
            val file = File("demo.txt")
            val input = file.inputStream()
            val output = file.outputStream()
            val buffer = mutableListOf(0, 0, 0)
            val first = input.read()
            val copied = input.read(buffer)
            val remaining = input.available()
            input.skip(1)
            output.write(65)
            output.write(buffer)
            output.flush()
            input.close()
            output.close()
        }
        """)
    }
}
