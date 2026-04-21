@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testSequenceMapToAppendsToDestination() throws {
        let source = """
        fun main() {
            val src = sequenceOf(1, 2, 3)
            val dest = mutableListOf("seed")
            val result = src.mapTo(dest) { it.toString() }
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIBSEQ022_01")
    }

    func testSequenceMapIndexedNotNullToAppendsNonNullIndexedTransforms() throws {
        let source = """
        fun main() {
            val src = sequenceOf(10, 20, 30, 40)
            val dest = mutableListOf("seed")
            val result = src.mapIndexedNotNullTo(dest) { index, value ->
                if (index % 2 == 0) index.toString() + ":" + value.toString() else null
            }
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIBSEQ022_02")
    }
}
