import Foundation
import XCTest
@testable import CompilerCore

final class CompilerCoreTests: XCTestCase {
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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0004"
        })
        XCTAssertTrue(hasDiagnostic)
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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0004"
        })
        XCTAssertTrue(hasDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0004"
        })
        XCTAssertFalse(hasDiagnostic)
    }

    func testWhenExhaustivenessAcceptsEnumWithAllEntries() throws {
        let source = """
        enum class Color { Red, Green }
        fun pick(color: Color) = when (color) {
            Red -> 1
            Green -> 2
        }
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0004"
        })
        XCTAssertFalse(hasDiagnostic)
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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0004"
        })
        XCTAssertFalse(hasDiagnostic)
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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0004"
        })
        XCTAssertTrue(hasDiagnostic)
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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic)
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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testTypeCheckReportsReturnTypeMismatchForExpressionBody() throws {
        let source = """
        fun bad(): Int = "x"
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasTypeError = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-TYPE-0001"
        })
        XCTAssertTrue(hasTypeError)
    }

    func testPropertyInitializerInfersTypeForSubsequentCalls() throws {
        let source = """
        val num = 1
        fun takesInt(x: Int) = x
        fun use() = takesInt(num)
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testPropertyInitializerTypeMismatchReportsTypeDiagnostic() throws {
        let source = """
        val bad: Int = "x"
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasTypeError = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-TYPE-0001"
        })
        XCTAssertTrue(hasTypeError, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testPropertyGetterTypeMismatchReportsTypeDiagnostic() throws {
        let source = """
        val bad: Int {
            get() = "x"
        }
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasTypeError = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-TYPE-0001"
        })
        XCTAssertTrue(hasTypeError, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testSetterOnValReportsDiagnostic() throws {
        let source = """
        val bad: Int {
            set(value) {
                value
            }
        }
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasSetterDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0005"
        })
        XCTAssertTrue(hasSetterDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertTrue(hasNoViableDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testOverloadRejectsBooleanArgumentForIntParameter() throws {
        let source = """
        fun foo(a: Int) = a
        fun bar() = foo(true)
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertTrue(hasNoViableDiagnostic)
    }

    func testCallSupportsMixedNamedAndPositionalArguments() throws {
        let source = """
        fun pick(x: Int, flag: Boolean) = x
        fun use() = pick(1, flag = true)
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testCallRejectsPositionalArgumentAfterNamedArgument() throws {
        let source = """
        fun pick(x: Int, y: Int) = x
        fun use() = pick(y = 1, 2)
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertTrue(hasNoViableDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testCallSupportsNonTrailingVarargWithNamedTail() throws {
        let source = """
        fun sum(vararg items: Int, tail: Int) = tail
        fun use() = sum(1, 2, tail = 3)
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testCallRejectsSpreadForNonVarargParameter() throws {
        let source = """
        fun take(x: Int) = x
        fun use() = take(*1)
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertTrue(hasNoViableDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testSemaAllowsOverloadedTopLevelFunctionsWithoutDuplicateDiagnostic() throws {
        let source = """
        fun pick(x: Int) = x
        fun pick(x: String) = x
        fun use() = pick(1)
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasDuplicateDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0001"
        })
        XCTAssertFalse(hasDuplicateDiagnostic)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic)
    }

    func testInferredExpressionBodyReturnTypeCanFlowIntoTypedCall() throws {
        let source = """
        fun foo() = 1
        fun takesInt(a: Int) = a
        fun bar() = takesInt(foo())
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic)
    }

    func testBuildASTParsesExtensionFunctionReceiverType() throws {
        let source = """
        fun String.echo(): String = this
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)

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
        if case .named(let path, let nullable) = receiverType {
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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)

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
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic)
    }

    func testGenericIdentityFunctionIsInferredAtCallSite() throws {
        let source = """
        fun <T> id(x: T): T = x
        fun takesInt(a: Int) = a
        fun main() = takesInt(id(1))
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic)
    }

    func testGenericConstraintFailureReportsTypeDiagnostic() throws {
        let source = """
        fun <T> id(x: T): T = x
        fun bad(): Boolean = id(1)
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let typeDiagnostics = ctx.diagnostics.diagnostics.filter { diag in
            diag.code == "KSWIFTK-TYPE-0001"
        }
        XCTAssertFalse(typeDiagnostics.isEmpty, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testSemaResolvesTopLevelFunctionAcrossFilesInSamePackage() throws {
        let sources = [
            """
            package demo
            fun helper(x: Int) = x
            """,
            """
            package demo
            fun use() = helper(1)
            """
        ]
        let ctx = try makeContext(sources: sources)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic)
    }

    func testSemaResolvesExplicitImportAcrossPackages() throws {
        let sources = [
            """
            package lib
            fun helper(x: Int) = x
            """,
            """
            package app
            import lib.helper
            fun use() = helper(1)
            """
        ]
        let ctx = try makeContext(sources: sources)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasNoViableDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0002"
        })
        XCTAssertFalse(hasNoViableDiagnostic)
    }

    func testExplicitImportWinsOverDefaultImportForSameName() throws {
        let sources = [
            """
            package kotlin.io
            fun pick(x: Int) = "default"
            """,
            """
            package custom.io
            fun pick(x: Int) = 2
            """,
            """
            package app
            import custom.io.pick
            fun use() = pick(1)
            """
        ]
        let ctx = try makeContext(sources: sources)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let useSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && ctx.interner.resolve(symbol.name) == "use"
        })?.id)
        let useSignature = try XCTUnwrap(sema.symbols.functionSignature(for: useSymbol))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        XCTAssertEqual(useSignature.returnType, intType)

        let hasAmbiguousDiagnostic = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0003"
        })
        XCTAssertFalse(hasAmbiguousDiagnostic)
    }

    func testEmitObjectProducesMachOFile() throws {
        let source = "fun main() {}"
        let tempSource = try writeTempSource(source)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")

        let options = CompilerOptions(
            moduleName: "ObjTest",
            inputs: [tempSource.path],
            outputPath: outputURL.path,
            emit: .object,
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        )
        let driver = CompilerDriver(
            version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
            kotlinVersion: .v2_3_10
        )

        let exitCode = driver.run(options: options)
        XCTAssertEqual(exitCode, 0)
        let data = try Data(contentsOf: outputURL)
        XCTAssertGreaterThanOrEqual(data.count, 4)
        XCTAssertEqual(Array(data.prefix(4)), [0xCF, 0xFA, 0xED, 0xFE])
    }

    func testEmitExecutableFailsWithoutMainFunction() throws {
        let source = "fun notMain() {}"
        let tempSource = try writeTempSource(source)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let options = CompilerOptions(
            moduleName: "ExeTest",
            inputs: [tempSource.path],
            outputPath: outputURL.path,
            emit: .executable,
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        )
        let driver = CompilerDriver(
            version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
            kotlinVersion: .v2_3_10
        )

        let exitCode = driver.run(options: options)
        XCTAssertEqual(exitCode, 1)
    }

    func testDriverFallbackDiagnosticClassifiesPipelineErrors() {
        let load = CompilerDriver.fallbackDiagnostic(for: CompilerPipelineError.loadError)
        XCTAssertEqual(load?.code, "KSWIFTK-PIPELINE-0001")

        let invalid = CompilerDriver.fallbackDiagnostic(for: CompilerPipelineError.invalidInput("missing AST"))
        XCTAssertEqual(invalid?.code, "KSWIFTK-PIPELINE-0002")
        XCTAssertTrue(invalid?.message.contains("missing AST") == true)

        let output = CompilerDriver.fallbackDiagnostic(for: CompilerPipelineError.outputUnavailable)
        XCTAssertEqual(output?.code, "KSWIFTK-PIPELINE-0003")

        struct UnknownError: Error {}
        XCTAssertNil(CompilerDriver.fallbackDiagnostic(for: UnknownError()))
    }

    func testDriverReportsPipelineOutputUnavailableWithoutICE() throws {
        let source = "fun main() = 0"
        let tempSource = try writeTempSource(source)
        let missingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing")
        let outputBase = missingDir.appendingPathComponent("result").path

        let options = CompilerOptions(
            moduleName: "PipelineFailure",
            inputs: [tempSource.path],
            outputPath: outputBase,
            emit: .kirDump,
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        )
        let driver = CompilerDriver(
            version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
            kotlinVersion: .v2_3_10
        )

        let result = driver.runForTesting(options: options)
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "KSWIFTK-PIPELINE-0003" })
        XCTAssertFalse(result.diagnostics.contains { $0.code == "KSWIFTK-ICE-0001" })
    }

    private func makeContext(source: String) throws -> CompilationContext {
        let tempURL = try writeTempSource(source)

        let options = CompilerOptions(
            moduleName: "TestModule",
            inputs: [tempURL.path],
            outputPath: tempURL.deletingPathExtension().appendingPathExtension("out").path,
            emit: .kirDump,
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        )
        return CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
    }

    private func makeContext(sources: [String]) throws -> CompilationContext {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let inputPaths = try sources.enumerated().map { index, source in
            let fileURL = tempDir.appendingPathComponent("input\(index).kt")
            try source.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL.path
        }
        let options = CompilerOptions(
            moduleName: "TestModule",
            inputs: inputPaths,
            outputPath: tempDir.appendingPathComponent("out.kir").path,
            emit: .kirDump,
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        )
        return CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
    }

    private func writeTempSource(_ source: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt")
        try source.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}
