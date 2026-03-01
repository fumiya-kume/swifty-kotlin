@testable import CompilerCore
import Foundation
import XCTest

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlowSemaPass+BodyAnalysis.swift (45.8%)
//          DataFlowSemaPass+HeaderCollection.swift (49.9%)
//          TypeCheckSemaPass+ExprInference.swift (51.4%)

final class DataFlowAndSemaRegressionTests: XCTestCase {
    // MARK: - BodyAnalysis: duplicate parameter name

    func testDuplicateParameterNameEmitsDiagnostic() throws {
        let source = """
        fun bad(x: Int, x: Int): Int = x
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-TYPE-0002", in: ctx)
        }
    }

    // MARK: - BodyAnalysis: expression-body binding

    func testExpressionBodyFunctionBindsReturnType() throws {
        let source = """
        fun answer(): Int = 42
        fun main() = answer()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - BodyAnalysis: property decl binding

    func testPropertyDeclBindsIdentifierAndType() throws {
        let source = """
        val greeting: String = "hello"
        fun main() = greeting
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let greetingSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "greeting"
            }
            XCTAssertNotNil(greetingSymbol)
        }
    }

    // MARK: - BodyAnalysis: resolveTypeRef nullable

    func testNullableTypeAnnotationResolvesCorrectly() throws {
        let source = """
        fun nullable(x: Int?): Int? = x
        fun main() = nullable(null)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let nullableSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "nullable"
            }
            XCTAssertNotNil(nullableSymbol)
            if let sym = nullableSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id)
            {
                XCTAssertEqual(sig.parameterTypes.count, 1)
            }
        }
    }

    // MARK: - BodyAnalysis: function type parameter

    func testFunctionTypeParameterResolvesCorrectly() throws {
        let source = """
        fun apply(f: (Int) -> Int, x: Int): Int = f(x)
        fun main() = apply(f = { it -> it + 1 }, x = 5)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let applySymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "apply"
            }
            XCTAssertNotNil(applySymbol)
        }
    }

    // MARK: - HeaderCollection: secondary constructor

    func testSecondaryConstructorDefinesSymbol() throws {
        let source = """
        class Person(val name: String) {
            constructor(first: String, last: String): this(first)
        }
        fun main() = Person("Alice")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let ctorSymbols = sema.symbols.allSymbols().filter { symbol in
                symbol.kind == .constructor
            }
            XCTAssertGreaterThanOrEqual(ctorSymbols.count, 2, "Expected primary + secondary constructor")
        }
    }

    // MARK: - HeaderCollection: enum class entries

    func testEnumClassEntriesDefineFieldSymbols() throws {
        let source = """
        enum class Color { RED, GREEN, BLUE }
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let fieldSymbols = sema.symbols.allSymbols().filter { symbol in
                symbol.kind == .field && (
                    ctx.interner.resolve(symbol.name) == "RED" ||
                        ctx.interner.resolve(symbol.name) == "GREEN" ||
                        ctx.interner.resolve(symbol.name) == "BLUE"
                )
            }
            XCTAssertGreaterThanOrEqual(fieldSymbols.count, 1, "Expected at least 1 enum entry field")
        }
    }

    // MARK: - HeaderCollection: object declaration

    func testObjectDeclarationDefinesSymbol() throws {
        let source = """
        object Singleton {
            val value: Int = 42
        }
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let objectSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Singleton" && symbol.kind == .object
            }
            XCTAssertNotNil(objectSymbol)
        }
    }

    // MARK: - HeaderCollection: interface declaration

    func testInterfaceDeclarationDefinesSymbol() throws {
        let source = """
        interface Greetable {
            fun greet(): String
        }
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let interfaceSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Greetable" && symbol.kind == .interface
            }
            XCTAssertNotNil(interfaceSymbol)
        }
    }

    // MARK: - HeaderCollection: typeAlias declaration

    func testTypeAliasDeclarationDefinesSymbol() throws {
        let source = """
        typealias Name = String
        fun greet(n: Name): String = n
        fun main() = greet("World")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let aliasSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Name" && symbol.kind == .typeAlias
            }
            XCTAssertNotNil(aliasSymbol)
        }
    }

    // MARK: - HeaderCollection: extension function with receiver type

    func testExtensionFunctionHasReceiverType() throws {
        let source = """
        fun String.shout(): String = this
        fun main() = "hello".shout()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let shoutSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "shout"
            }
            XCTAssertNotNil(shoutSymbol)
            if let sym = shoutSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id)
            {
                XCTAssertNotNil(sig.receiverType)
            }
        }
    }

    // MARK: - HeaderCollection: reified inline function

    func testReifiedInlineFunctionDefinesTypeParameter() throws {
        let source = """
        inline fun <reified T> typeCheck(x: Any): Boolean = x is T
        fun main() = typeCheck<Int>(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let typeCheckSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "typeCheck"
            }
            XCTAssertNotNil(typeCheckSymbol)
            if let sym = typeCheckSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id)
            {
                XCTAssertFalse(sig.reifiedTypeParameterIndices.isEmpty)
            }
        }
    }

    // MARK: - HeaderCollection: reified on non-inline emits diagnostic

    func testReifiedOnNonInlineFunctionEmitsDiagnostic() throws {
        let source = """
        fun <reified T> badReified(x: Any): Boolean = x is T
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0020", in: ctx)
        }
    }

    // MARK: - HeaderCollection: member functions and properties

    func testClassMemberFunctionsAndPropertiesDefineSymbols() throws {
        let source = """
        class Counter {
            val count: Int = 0
            fun increment(): Int = count
        }
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let incrementSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "increment"
            }
            XCTAssertNotNil(incrementSymbol)
            let countSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "count" && symbol.kind == .property
            }
            XCTAssertNotNil(countSymbol)
        }
    }

    // MARK: - HeaderCollection: duplicate declaration diagnostic

    func testDuplicateTopLevelDeclarationEmitsDiagnostic() throws {
        let source = """
        val x: Int = 1
        val x: Int = 2
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0001", in: ctx)
        }
    }
}
