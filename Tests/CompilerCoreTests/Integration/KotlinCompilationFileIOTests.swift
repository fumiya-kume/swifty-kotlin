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

    // STDLIB-IO-PROP-002: `File.extension` resolves to a non-null `String`
    // through the synthetic stub registered in HeaderHelpers+SyntheticFileIOStubs.
    // The property is exposed as a member so that callers can use it on any
    // `java.io.File` instance produced by either `File(path)` constructor.
    func testCompile_file_extensionPropertyResolves() throws {
        try assertKotlinCompilesToKIR("""
        import java.io.File

        fun main() {
            val src = File("Main.kt")
            val archive = File("archive.tar.gz")
            val readme = File("README")
            val nested = File("/tmp", "notes.md")
            val srcExt: String = src.extension
            val archiveExt: String = archive.extension
            val readmeExt: String = readme.extension
            val nestedExt: String = nested.extension
            println(srcExt)
            println(archiveExt)
            println(readmeExt)
            println(nestedExt)
        }
        """)
    }
}
