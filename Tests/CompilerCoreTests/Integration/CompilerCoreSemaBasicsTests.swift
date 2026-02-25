import Foundation
import XCTest
@testable import CompilerCore

extension CompilerCoreTests {
    func testLexerRecognizesQuestionQuestionSymbol() {
        let source = Data("a ?? b".utf8)
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let lexer = KotlinLexer(
            file: FileID(rawValue: 0),
            source: source,
            interner: interner,
            diagnostics: diagnostics
        )

        let tokens = lexer.lexAll()
        XCTAssertTrue(tokens.contains { token in
            token.kind == .symbol(.questionQuestion)
        })
        XCTAssertFalse(diagnostics.hasError)
    }

    func testSemaBindsSimpleCallExpression() throws {
        let source = """
        fun foo(a: Int) = a
        fun bar() = foo(1)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        XCTAssertFalse(sema.bindings.callBindings.isEmpty)
    }

    func testWhenExhaustivenessDiagnosticForBooleanWithoutElse() throws {
        let source = """
        fun test() {
            when (true) {
                true -> 1
            }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    func testWhenExhaustivenessDiagnosticForNullableBooleanWithoutNullBranch() throws {
        let source = """
        fun test(x: Boolean?) {
            when (x) {
                true -> 1
                false -> 0
            }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    func testWhenExhaustivenessAcceptsNullableBooleanWithNullBranch() throws {
        let source = """
        fun test(x: Boolean?) {
            when (x) {
                true -> 1
                false -> 0
                null -> 2
            }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    func testWhenExhaustivenessAcceptsEnumWithAllEntries() throws {
        let source = """
        enum class Color { Red, Green }
        fun pick(color: Color) = when (color) {
            Red -> 1
            Green -> 2
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    func testWhenExhaustivenessAcceptsSealedWithAllDirectSubtypes() throws {
        let source = """
        sealed class Expr
        object A : Expr()
        object B : Expr()
        fun eval(e: Expr): Int {
            when (e) {
                A -> 1
                B -> 2
            }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }

    func testWhenExhaustivenessDiagnosticForSealedMissingSubtype() throws {
        let source = """
        sealed class Expr
        object A : Expr()
        object B : Expr()
        fun eval(e: Expr): Int {
            when (e) {
                A -> 1
            }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        // P5-78: sealed missing-branch diagnostic now uses KSWIFTK-SEMA-0071
        assertHasDiagnostic("KSWIFTK-SEMA-0071", in: ctx)

        // Also assert that the diagnostic text mentions missing branches and the missing subtype.
        let sealedDiag = ctx.diagnostics.diagnostics.first { $0.code == "KSWIFTK-SEMA-0071" }
        XCTAssertNotNil(sealedDiag)
        XCTAssertTrue(
            sealedDiag?.message.contains("Missing branches") == true,
            "Expected diagnostic message to mention missing branches"
        )
        XCTAssertTrue(
            sealedDiag?.message.contains("B") == true,
            "Expected diagnostic message to mention missing subtype 'B'"
        )
    }

    // P5-78: sealed interface when exhaustiveness accepts all branches
    func testSealedInterfaceWhenExhaustivenessAcceptsAllBranches() throws {
        let source = """
        sealed interface Expr
        class Literal : Expr
        class Add : Expr

        fun eval(e: Expr): String {
            when (e) {
                is Literal -> "lit"
                is Add -> "add"
            }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }

    func testWhenNullBranchSmartCastsLocalToNonNullInOtherBranches() throws {
        let source = """
        fun takesInt(x: Int) = x
        fun smart(x: Int?): Int {
            when (x) {
                null -> 0
                else -> takesInt(x)
            }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testWhenBranchSmartCastsSealedSubjectToMatchedSubtype() throws {
        let source = """
        sealed class Expr
        object A : Expr()
        object B : Expr()
        fun takesA(x: A) = 1
        fun eval(e: Expr): Int {
            when (e) {
                A -> takesA(e)
                B -> 0
            }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testWhenBooleanBranchSmartCastsNullableBooleanToNonNull() throws {
        let source = """
        fun takesBool(x: Boolean) = x
        fun eval(b: Boolean?) {
            when (b) {
                true -> takesBool(b)
                false -> takesBool(b)
                null -> false
            }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testTypeCheckReportsReturnTypeMismatchForExpressionBody() throws {
        let source = """
        fun bad(): Int = "x"
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    func testPropertyInitializerInfersTypeForSubsequentCalls() throws {
        let source = """
        val num = 1
        fun takesInt(x: Int) = x
        fun use() = takesInt(num)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testPropertyInitializerTypeMismatchReportsTypeDiagnostic() throws {
        let source = """
        val bad: Int = "x"
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    func testPropertyGetterTypeMismatchReportsTypeDiagnostic() throws {
        let source = """
        val bad: Int {
            get() = "x"
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    func testSetterOnValReportsDiagnostic() throws {
        let source = """
        val bad: Int {
            set(value) {
                value
            }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0005", in: ctx)
    }

    func testClassInitBlockIsTypeChecked() throws {
        let source = """
        fun takesInt(x: Int) = x
        class C {
            init {
                takesInt("x")
            }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testOverloadRejectsBooleanArgumentForIntParameter() throws {
        let source = """
        fun foo(a: Int) = a
        fun bar() = foo(true)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testCallSupportsMixedNamedAndPositionalArguments() throws {
        let source = """
        fun pick(x: Int, flag: Boolean) = x
        fun use() = pick(1, flag = true)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testCallRejectsPositionalArgumentAfterNamedArgument() throws {
        let source = """
        fun pick(x: Int, y: Int) = x
        fun use() = pick(y = 1, 2)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testCallSupportsNonTrailingVarargWithNamedTail() throws {
        let source = """
        fun sum(vararg items: Int, tail: Int) = tail
        fun use() = sum(1, 2, tail = 3)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testCallRejectsSpreadForNonVarargParameter() throws {
        let source = """
        fun take(x: Int) = x
        fun use() = take(*1)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testSemaAllowsOverloadedTopLevelFunctionsWithoutDuplicateDiagnostic() throws {
        let source = """
        fun pick(x: Int) = x
        fun pick(x: String) = x
        fun use() = pick(1)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0001", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testInferredExpressionBodyReturnTypeCanFlowIntoTypedCall() throws {
        let source = """
        fun foo() = 1
        fun takesInt(a: Int) = a
        fun bar() = takesInt(foo())
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testBuildASTParsesExtensionFunctionReceiverType() throws {
        let source = """
        fun String.echo(): String = this
        """
        let ctx = try makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let firstFile = try XCTUnwrap(ast.files.first)
        let firstDeclID = try XCTUnwrap(firstFile.topLevelDecls.first)
        let decl = try XCTUnwrap(ast.arena.decl(firstDeclID))
        guard case .funDecl(let funDecl) = decl else {
            XCTFail("Expected function declaration")
            return
        }

        XCTAssertNotEqual(funDecl.name, .invalid)
        let receiverTypeID = try XCTUnwrap(funDecl.receiverType)
        let receiverType = try XCTUnwrap(ast.arena.typeRef(receiverTypeID))
        if case .named(let path, _, let nullable) = receiverType {
            XCTAssertFalse(nullable)
            XCTAssertEqual(path.count, 1)
            XCTAssertEqual(ctx.interner.resolve(path[0]), "String")
        } else {
            XCTFail("Expected named receiver type")
        }
    }

    func testBuildASTParsesClassTypeParameterVariance() throws {
        let source = """
        class Box<out T, in U, V>
        """
        let ctx = try makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let firstFile = try XCTUnwrap(ast.files.first)
        let firstDeclID = try XCTUnwrap(firstFile.topLevelDecls.first)
        let decl = try XCTUnwrap(ast.arena.decl(firstDeclID))
        guard case .classDecl(let classDecl) = decl else {
            XCTFail("Expected class declaration")
            return
        }

        XCTAssertEqual(classDecl.typeParams.count, 3)
        XCTAssertEqual(classDecl.typeParams.map(\.variance), [.out, .in, .invariant])
        XCTAssertEqual(classDecl.typeParams.map { ctx.interner.resolve($0.name) }, ["T", "U", "V"])
    }

    func testSemaResolvesUnqualifiedExtensionCallWithImplicitReceiver() throws {
        let source = """
        fun String.ext() = 1
        fun String.wrap() = ext()
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testGenericIdentityFunctionIsInferredAtCallSite() throws {
        let source = """
        fun <T> id(x: T): T = x
        fun takesInt(a: Int) = a
        fun main() = takesInt(id(1))
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testGenericConstraintFailureReportsTypeDiagnostic() throws {
        let source = """
        fun <T> id(x: T): T = x
        fun bad(): Boolean = id(1)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }
}
