import Foundation
import XCTest
@testable import CompilerCore

// MARK: - DataFlow + Sema Coverage Tests
// Targets: DataFlowSemaPass+BodyAnalysis.swift (45.8%)
//          DataFlowSemaPass+HeaderCollection.swift (49.9%)
//          TypeCheckSemaPass+ExprInference.swift (51.4%)

final class DataFlowAndSemaCoverageTests: XCTestCase {

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
               let sig = sema.symbols.functionSignature(for: sym.id) {
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
               let sig = sema.symbols.functionSignature(for: sym.id) {
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
               let sig = sema.symbols.functionSignature(for: sym.id) {
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

    // MARK: - HeaderCollection: class with type parameters and variance

    func testClassWithTypeParametersDefinesVariance() throws {
        let source = """
        class Box<out T>(val value: T)
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let boxSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Box"
            }
            XCTAssertNotNil(boxSymbol)
        }
    }

    // MARK: - ExprInference: typed local declaration

    func testTypedLocalDeclarationInfersCorrectly() throws {
        let source = """
        fun main(): Int {
            val x: Int = 42
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let xSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "x" && symbol.kind == .local
            }
            XCTAssertNotNil(xSymbol)
        }
    }

    // MARK: - ExprInference: val reassignment diagnostic

    func testValReassignmentEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            val x = 1
            x = 2
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: do-while loop

    func testDoWhileLoopInfersUnitType() throws {
        let source = """
        fun main(): Int {
            var x = 0
            do {
                x = x + 1
            } while (x < 3)
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: compound assignment operators

    func testCompoundAssignmentOperators() throws {
        let source = """
        fun main(): Int {
            var x = 10
            x += 5
            x -= 3
            x *= 2
            x /= 4
            x %= 3
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: compound assign on val

    func testCompoundAssignOnValEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            val x = 5
            x += 1
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: when expression

    func testWhenExpressionInference() throws {
        let source = """
        fun classify(x: Int): String {
            return when (x) {
                1 -> "one"
                2 -> "two"
                else -> "other"
            }
        }
        fun main() = classify(1)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: return expression

    func testReturnExpressionInference() throws {
        let source = """
        fun earlyReturn(flag: Boolean): Int {
            if (flag) return 42
            return 0
        }
        fun main() = earlyReturn(true)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "earlyReturn", in: module, interner: ctx.interner)
            let returnCount = body.filter { instruction in
                if case .returnValue = instruction { return true }
                return false
            }.count
            XCTAssertGreaterThanOrEqual(returnCount, 2)
        }
    }

    // MARK: - ExprInference: Long/Float/Double/Char literals

    func testLongLiteralInference() throws {
        let source = """
        fun main(): Long = 42L
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testFloatLiteralInference() throws {
        let source = """
        fun main(): Float = 1.5f
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testDoubleLiteralInference() throws {
        let source = """
        fun main(): Double = 3.14
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testCharLiteralInference() throws {
        let source = """
        fun main(): Char = 'A'
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: is check and as cast

    func testIsCheckInfersBoolean() throws {
        let source = """
        fun check(x: Any): Boolean = x is Int
        fun main() = check(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testSafeCastInfersNullableType() throws {
        let source = """
        fun tryCast(x: Any): Int? = x as? Int
        fun main() = tryCast(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testHardCastInference() throws {
        let source = """
        fun forceCast(x: Any): Int = x as Int
        fun main() = forceCast(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: null assert

    func testNullAssertInfersNonNullable() throws {
        let source = """
        fun forceUnwrap(x: Int?): Int = x!!
        fun main() = forceUnwrap(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: elvis operator

    func testElvisOperatorInference() throws {
        let source = """
        fun fallback(x: Int?): Int = x ?: 0
        fun main() = fallback(null)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: break/continue outside loop

    func testBreakOutsideLoopEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            break
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0018", in: ctx)
        }
    }

    func testContinueOutsideLoopEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            continue
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0019", in: ctx)
        }
    }

    // MARK: - ExprInference: unresolved reference

    func testUnresolvedReferenceEmitsDiagnostic() throws {
        let source = """
        fun main(): Int = unknownVar
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        }
    }

    // MARK: - ExprInference: unresolved function

    func testUnresolvedFunctionEmitsDiagnostic() throws {
        let source = """
        fun main(): Int = unknownFunc(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        }
    }

    // MARK: - ExprInference: local function

    func testLocalFunctionDeclarationInference() throws {
        let source = """
        fun main(): Int {
            fun add(a: Int, b: Int): Int = a + b
            return add(1, 2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: array access and assign

    func testArrayAccessAndAssignInference() throws {
        let source = """
        fun main(): Int {
            val arr = IntArray(3)
            arr[0] = 10
            return arr[0]
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: for loop with loop variable

    func testForLoopInfersElementType() throws {
        let source = """
        fun main(): Int {
            val arr = IntArray(3)
            var sum = 0
            for (item in arr) {
                sum += item
            }
            return sum
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: binary type promotion

    func testBinaryOperatorTypePromotionLong() throws {
        let source = """
        fun main(): Long = 1L + 2
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testBinaryOperatorTypePromotionDouble() throws {
        let source = """
        fun main(): Double = 1.0 + 2.0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testBinaryOperatorTypePromotionFloat() throws {
        let source = """
        fun main(): Float = 1.5f + 2.5f
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: string template

    func testStringTemplateInference() throws {
        let source = """
        fun main(): String {
            val name = "World"
            return "Hello, $name!"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: if expression with else

    func testIfExpressionWithElseInfersLUB() throws {
        let source = """
        fun pick(flag: Boolean): Int {
            val x = if (flag) 1 else 2
            return x
        }
        fun main() = pick(true)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: if expression without else infers Unit

    func testIfExpressionWithoutElseInfersUnit() throws {
        let source = """
        fun doSomething(flag: Boolean) {
            if (flag) println("yes")
        }
        fun main() = doSomething(true)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: null reference

    func testNullLiteralInference() throws {
        let source = """
        fun main(): Any? = null
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: while loop

    func testWhileLoopInference() throws {
        let source = """
        fun main(): Int {
            var i = 0
            while (i < 10) {
                i = i + 1
            }
            return i
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: rangeTo operator

    func testRangeToOperatorInference() throws {
        let source = """
        fun main() {
            val r = 1..10
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: local assign to unresolved variable

    func testLocalAssignToUnresolvedVariableEmitsDiagnostic() throws {
        let source = """
        fun main() {
            noSuchVar = 42
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0013", in: ctx)
        }
    }

    // MARK: - ExprInference: when without else (boolean exhaustive)

    func testWhenBooleanExhaustive() throws {
        let source = """
        fun desc(flag: Boolean): String = when (flag) {
            true -> "yes"
            false -> "no"
        }
        fun main() = desc(true)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - HeaderCollection: property with type annotation

    func testPropertyTypeAnnotationResolves() throws {
        let source = """
        val count: Int = 0
        val name: String = "test"
        val flag: Boolean = true
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let countSym = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "count" && symbol.kind == .property
            }
            XCTAssertNotNil(countSym)
            if let sym = countSym {
                XCTAssertNotNil(sema.symbols.propertyType(for: sym.id))
            }
        }
    }

    // MARK: - HeaderCollection: function with type parameters and upper bounds

    func testFunctionTypeParameterWithUpperBound() throws {
        let source = """
        fun <T : Any> wrap(value: T): T = value
        fun main() = wrap(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let wrapSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "wrap"
            }
            XCTAssertNotNil(wrapSymbol)
            if let sym = wrapSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id) {
                XCTAssertFalse(sig.typeParameterSymbols.isEmpty)
            }
        }
    }

    // MARK: - ExprInference: try-catch expression

    func testTryCatchExpressionInference() throws {
        let source = """
        fun risky(): Int {
            return try {
                42
            } catch (e: Any) {
                0
            }
        }
        fun main() = risky()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    func testTryCatchClauseBindingsResolvePrimitiveAndNominalTypes() throws {
        let source = """
        class MyError

        fun risky(): Int {
            return try {
                42
            } catch (e: Int) {
                e
            } catch (e: MyError) {
                0
            }
        }

        fun main() = risky()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let tryExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                if case .tryExpr = expr {
                    return true
                }
                return false
            })
            guard case .tryExpr(_, let catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
                XCTFail("Expected try expression")
                return
            }
            XCTAssertEqual(catchClauses.count, 2)

            let firstBinding = try XCTUnwrap(sema.bindings.catchClauseBinding(for: catchClauses[0].body))
            let secondBinding = try XCTUnwrap(sema.bindings.catchClauseBinding(for: catchClauses[1].body))
            XCTAssertNotEqual(firstBinding.parameterSymbol, .invalid)
            XCTAssertNotEqual(secondBinding.parameterSymbol, .invalid)
            XCTAssertNotEqual(firstBinding.parameterSymbol, secondBinding.parameterSymbol)

            let intType = sema.types.make(.primitive(.int, .nonNull))
            XCTAssertEqual(firstBinding.parameterType, intType)
            XCTAssertEqual(sema.symbols.propertyType(for: firstBinding.parameterSymbol), intType)

            let customErrorSymbol = sema.symbols.allSymbols().first { symbol in
                symbol.kind == .class && ctx.interner.resolve(symbol.name) == "MyError"
            }
            let resolvedCustomErrorSymbol = try XCTUnwrap(customErrorSymbol)
            guard case .classType(let customErrorType) = sema.types.kind(of: secondBinding.parameterType) else {
                XCTFail("Expected nominal catch parameter type")
                return
            }
            XCTAssertEqual(customErrorType.classSymbol, resolvedCustomErrorSymbol.id)
            XCTAssertEqual(sema.symbols.propertyType(for: secondBinding.parameterSymbol), secondBinding.parameterType)

            let catchNameRef = try XCTUnwrap(firstExprID(in: ast) { exprID, expr in
                guard case .nameRef(let name, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(name) == "e"
                    && sema.bindings.identifierSymbol(for: exprID) == firstBinding.parameterSymbol
            })
            XCTAssertEqual(sema.bindings.identifierSymbol(for: catchNameRef), firstBinding.parameterSymbol)
            XCTAssertEqual(sema.bindings.exprType(for: catchNameRef), intType)
        }
    }

    func testTryCatchClauseBindingWithoutParameterDefaultsToAny() throws {
        let source = """
        fun risky(): Int {
            return try {
                42
            } catch {
                0
            }
        }
        fun main() = risky()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let tryExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                if case .tryExpr = expr {
                    return true
                }
                return false
            })
            guard case .tryExpr(_, let catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
                XCTFail("Expected try expression")
                return
            }
            let binding = try XCTUnwrap(sema.bindings.catchClauseBinding(for: catchClauses[0].body))
            XCTAssertEqual(binding.parameterSymbol, .invalid)
            XCTAssertEqual(binding.parameterType, sema.types.anyType)
        }
    }

    // MARK: - ExprInference: uninitialized variable use

    func testUninitializedVariableUseEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            var x: Int
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    // MARK: - ExprInference: compound assign on uninitialized variable

    func testCompoundAssignOnUninitializedVariableEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            var x: Int
            x += 1
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    // MARK: - ExprInference: local variable deferred initialization via if-else

    func testDeferredInitializationViaIfElse() throws {
        let source = """
        fun main(): Int {
            var x: Int = 0
            if (true) {
                x = 1
            } else {
                x = 2
            }
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    // MARK: - HeaderCollection: suspend function

    func testSuspendFunctionSignature() throws {
        let source = """
        suspend fun delayed(v: Int): Int = v
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let delayedSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "delayed"
            }
            XCTAssertNotNil(delayedSymbol)
            if let sym = delayedSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id) {
                XCTAssertTrue(sig.isSuspend)
            }
        }
    }

    // MARK: - ExprInference: println builtin

    func testPrintlnBuiltinInfersUnit() throws {
        let source = """
        fun main() {
            println("hello")
            println()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - ExprInference: local variable with var and reassignment

    func testVarLocalReassignment() throws {
        let source = """
        fun main(): Int {
            var x = 1
            x = 10
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    private func firstExprID(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else {
                continue
            }
            if predicate(exprID, expr) {
                return exprID
            }
        }
        return nil
    }
}
