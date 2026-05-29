@testable import CompilerCore
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCatchesArrayIndexOutOfBoundsException() throws {
        let source = """
        fun main() {
            try {
                throw ArrayIndexOutOfBoundsException("bad index")
            } catch (e: ArrayIndexOutOfBoundsException) {
                println("array-index")
            }

            try {
                throw ArrayIndexOutOfBoundsException()
            } catch (e: IndexOutOfBoundsException) {
                println("index")
            }
        }
        """

        let normalizedStdout = try runCodegenExecutableStdout(
            source,
            moduleName: "ArrayIndexOutOfBoundsExceptionCase"
        )
        XCTAssertEqual(normalizedStdout, "array-index\nindex\n")
    }
}
