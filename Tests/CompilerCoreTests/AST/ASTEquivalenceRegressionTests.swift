@testable import CompilerCore
import Foundation
import XCTest

// MARK: - AST Equivalence Regression Tests (P5-58)

// Verify that decl/expr counts and source ranges remain consistent
// after BuildAST optimisation changes.

final class ASTEquivalenceRegressionTests: XCTestCase {
    // MARK: - Helpers

    private func buildAST(from source: String) throws -> (ASTModule, CompilationContext) {
        let ctx: CompilationContext = makeContextFromSource(source)
        try runFrontend(ctx)
        let ast = try XCTUnwrap(ctx.ast)
        return (ast, ctx)
    }

    private func assertValidSourceRange(
        _ range: SourceRange?,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let range else {
            XCTFail("\(label): range is nil", file: file, line: line)
            return
        }
        XCTAssertTrue(
            range.start.offset <= range.end.offset,
            "\(label): start (\(range.start.offset)) should be <= end (\(range.end.offset))",
            file: file,
            line: line
        )
    }

    // MARK: - Simple function

    func testSimpleFunctionDeclAndExprCounts() throws {
        let source = """
        fun add(a: Int, b: Int): Int = a + b
        fun main() = add(1, 2)
        """
        let (ast, _) = try buildAST(from: source)

        XCTAssertEqual(ast.declarationCount, 2, "Expected 2 top-level declarations")
        XCTAssertGreaterThanOrEqual(ast.arena.exprs.count, 2, "Expected at least 2 expressions")

        for decl in ast.arena.declarations() {
            switch decl {
            case let .funDecl(f):
                assertValidSourceRange(f.range, label: "funDecl")
            default:
                break
            }
        }
    }

    // MARK: - Block body with locals

    func testBlockBodyDeclExprCounts() throws {
        let source = """
        fun compute(x: Int): Int {
            val a = x + 1
            var b = a * 2
            b += 10
            return b
        }
        fun main() = compute(5)
        """
        let (ast, _) = try buildAST(from: source)

        XCTAssertEqual(ast.declarationCount, 2)
        // At least: localDecl(a), localDecl(b), compoundAssign, returnExpr, + body expressions
        XCTAssertGreaterThanOrEqual(ast.arena.exprs.count, 6)

        for i in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(i))
            assertValidSourceRange(ast.arena.exprRange(id), label: "expr[\(i)]")
        }
    }

    // MARK: - Class with members

    func testClassDeclAndExprCounts() throws {
        let source = """
        class Counter(val initial: Int) {
            var count: Int = initial
            fun increment() { count += 1 }
            fun get(): Int = count
        }
        fun main() = Counter(0).get()
        """
        let (ast, _) = try buildAST(from: source)

        // classDecl + funDecl(main)
        XCTAssertEqual(ast.declarationCount, 2)

        let classDecls = ast.arena.declarations().compactMap { decl -> ClassDecl? in
            guard case let .classDecl(c) = decl else { return nil }
            return c
        }
        XCTAssertEqual(classDecls.count, 1)
        let counterClass = classDecls[0]
        assertValidSourceRange(counterClass.range, label: "Counter class")

        // Should have member decls: property(count), fun(increment), fun(get)
        XCTAssertGreaterThanOrEqual(counterClass.memberFunctions.count, 2)
        XCTAssertGreaterThanOrEqual(counterClass.memberProperties.count, 1)
    }

    // MARK: - Control flow

    func testControlFlowExprCounts() throws {
        let source = """
        fun fib(n: Int): Int {
            if (n <= 1) return n
            var a = 0
            var b = 1
            for (i in 2..n) {
                val tmp = a + b
                a = b
                b = tmp
            }
            return b
        }
        fun main() = fib(10)
        """
        let (ast, _) = try buildAST(from: source)

        XCTAssertEqual(ast.declarationCount, 2)
        // localDecl(a), localDecl(b), forExpr, localDecl(tmp), localAssign(a), localAssign(b), returnExpr etc.
        XCTAssertGreaterThanOrEqual(ast.arena.exprs.count, 8)

        for i in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(i))
            assertValidSourceRange(ast.arena.exprRange(id), label: "expr[\(i)]")
        }
    }

    // MARK: - Lambda and when expression

    func testLambdaAndWhenExprCounts() throws {
        let source = """
        fun classify(x: Int): String {
            val label = when {
                x < 0 -> "negative"
                x == 0 -> "zero"
                else -> "positive"
            }
            return label
        }
        fun apply(f: (Int) -> Int, x: Int): Int = f(x)
        fun main(): Int {
            val double = { v: Int -> v * 2 }
            return apply(double, 21)
        }
        """
        let (ast, _) = try buildAST(from: source)

        XCTAssertEqual(ast.declarationCount, 3)
        XCTAssertGreaterThanOrEqual(ast.arena.exprs.count, 6)

        for i in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(i))
            assertValidSourceRange(ast.arena.exprRange(id), label: "expr[\(i)]")
        }
    }

    // MARK: - Interface and inheritance

    func testInterfaceDeclCounts() throws {
        let source = """
        interface Shape {
            fun area(): Double
        }
        class Circle(val radius: Double) : Shape {
            override fun area(): Double = radius * radius * 3.14
        }
        fun main() = Circle(5.0).area()
        """
        let (ast, _) = try buildAST(from: source)

        // interface + class + fun(main)
        XCTAssertEqual(ast.declarationCount, 3)

        let interfaceDecls = ast.arena.declarations().compactMap { decl -> InterfaceDecl? in
            guard case let .interfaceDecl(i) = decl else { return nil }
            return i
        }
        XCTAssertEqual(interfaceDecls.count, 1)
        assertValidSourceRange(interfaceDecls[0].range, label: "Shape interface")
    }

    // MARK: - Properties with accessors

    func testPropertyDeclCounts() throws {
        let source = """
        class Box(val width: Int, val height: Int) {
            val area: Int
                get() = width * height
        }
        fun main() = Box(3, 4).area
        """
        let (ast, _) = try buildAST(from: source)

        XCTAssertEqual(ast.declarationCount, 2)

        for i in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(i))
            assertValidSourceRange(ast.arena.exprRange(id), label: "expr[\(i)]")
        }
    }

    // MARK: - All source ranges are valid across a complex file

    func testAllSourceRangesValidForComplexInput() throws {
        let source = """
        class Calculator {
            var result: Int = 0
            fun add(x: Int) { result += x }
            fun sub(x: Int) { result -= x }
            fun reset() { result = 0 }
            fun get(): Int = result
        }
        fun factorial(n: Int): Int {
            if (n <= 1) return 1
            return n * factorial(n - 1)
        }
        fun main(): Int {
            val calc = Calculator()
            calc.add(factorial(5))
            calc.sub(10)
            return calc.get()
        }
        """
        let (ast, _) = try buildAST(from: source)

        // class + factorial + main
        XCTAssertEqual(ast.declarationCount, 3)

        // Verify ALL decl ranges are valid
        for decl in ast.arena.declarations() {
            switch decl {
            case let .funDecl(f):
                assertValidSourceRange(f.range, label: "funDecl(\(f.name.rawValue))")
            case let .classDecl(c):
                assertValidSourceRange(c.range, label: "classDecl")
            case let .interfaceDecl(i):
                assertValidSourceRange(i.range, label: "interfaceDecl")
            case let .propertyDecl(p):
                assertValidSourceRange(p.range, label: "propertyDecl")
            case let .objectDecl(o):
                assertValidSourceRange(o.range, label: "objectDecl")
            case let .typeAliasDecl(t):
                assertValidSourceRange(t.range, label: "typeAliasDecl")
            case let .enumEntryDecl(e):
                assertValidSourceRange(e.range, label: "enumEntryDecl")
            }
        }

        // Verify ALL expr ranges are valid
        for i in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(i))
            assertValidSourceRange(ast.arena.exprRange(id), label: "expr[\(i)]")
        }
    }

    // MARK: - Script mode

    func testScriptModeDeclExprCounts() throws {
        let source = """
        val x = 42
        val y = x + 8
        println(y)
        """
        try withTemporaryFile(contents: source, fileExtension: "kts") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try XCTUnwrap(ctx.ast)

            // Script wraps body into a synthetic main function
            XCTAssertGreaterThanOrEqual(ast.declarationCount, 1)
            XCTAssertGreaterThanOrEqual(ast.arena.exprs.count, 2)
        }
    }
}
