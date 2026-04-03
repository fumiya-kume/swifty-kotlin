@testable import CompilerCore
import Foundation
import XCTest

final class KotlinCompilationDeepRecursiveTests: XCTestCase {
    func testCompileDeepRecursiveFunctionBasicUsage() throws {
        try assertKotlinCompilesToKIR("""
        class Node(val next: Node?)

        fun probe(node: Node?): Int {
            val depth: DeepRecursiveFunction<Node?, Int> = DeepRecursiveFunction<Node?, Int> {
                if (it == null) 0 else callRecursive(it.next) + 1
            }
            return depth.invoke(node)
        }
        """)
    }

    func testCompileDeepRecursiveFunctionExplicitParamName() throws {
        try assertKotlinCompilesToKIR("""
        class Node(val next: Node?)

        fun probe(node: Node?): Int {
            val depth: DeepRecursiveFunction<Node?, Int> = DeepRecursiveFunction<Node?, Int> { n ->
                if (n == null) 0 else callRecursive(n.next) + 1
            }
            return depth.invoke(node)
        }
        """)
    }

    func testCompileDeepRecursiveFunctionBasicObjectEmission() throws {
        try assertKotlinCompilesToObject("""
        class Node(val next: Node?)

        fun makeDepth(): DeepRecursiveFunction<Node?, Int> {
            val depth: DeepRecursiveFunction<Node?, Int> = DeepRecursiveFunction<Node?, Int> {
                if (it == null) 0 else callRecursive(it.next) + 1
            }
            return depth
        }
        """)
    }
}
