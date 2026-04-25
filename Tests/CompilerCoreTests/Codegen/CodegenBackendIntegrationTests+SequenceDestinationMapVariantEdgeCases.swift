@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testSequenceAssociateToPopulatesMutableMapDestination() throws {
        let source = """
        fun main() {
            val src = sequenceOf("a", "bb", "ccc")
            val dest = mutableMapOf<String, Int>()
            val result = src.associateTo(dest) { it to it.length }
            println(result === dest)
            println(dest["a"])
            println(dest["bb"])
            println(dest["ccc"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIBSEQ023_01")
    }

    func testSequenceAssociateByToMapsKeysToOriginalElements() throws {
        let source = """
        fun main() {
            val src = sequenceOf("apple", "banana", "pear")
            val dest = mutableMapOf<Int, String>()
            val result = src.associateByTo(dest) { it.length }
            println(result === dest)
            println(dest[5])
            println(dest[6])
            println(dest[4])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIBSEQ023_02")
    }

    func testSequenceAssociateWithToUsesElementsAsKeys() throws {
        let source = """
        fun main() {
            val src = sequenceOf(1, 2, 3)
            val dest = mutableMapOf<Int, Int>()
            val result = src.associateWithTo(dest) { it * it }
            println(result === dest)
            println(dest[1])
            println(dest[2])
            println(dest[3])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIBSEQ023_03")
    }

    func testSequenceGroupByToAppendsIntoMutableListBuckets() throws {
        let source = """
        fun main() {
            val src = sequenceOf(1, 2, 3, 4, 5)
            val dest = mutableMapOf<String, MutableList<Int>>()
            val result = src.groupByTo(dest) { if (it % 2 == 0) "even" else "odd" }
            println(result === dest)
            println(dest["even"])
            println(dest["odd"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIBSEQ023_04")
    }
}
