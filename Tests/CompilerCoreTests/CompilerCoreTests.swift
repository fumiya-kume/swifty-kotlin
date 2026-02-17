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
        let ctx = try makeContext(source: source)
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
        let ctx = try makeContext(source: source)
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
        let ctx = try makeContext(source: source)
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
        let ctx = try makeContext(source: source)
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
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
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
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
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
        let ctx = try makeContext(source: source)
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
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testTypeCheckReportsReturnTypeMismatchForExpressionBody() throws {
        let source = """
        fun bad(): Int = "x"
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    func testPropertyInitializerInfersTypeForSubsequentCalls() throws {
        let source = """
        val num = 1
        fun takesInt(x: Int) = x
        fun use() = takesInt(num)
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testPropertyInitializerTypeMismatchReportsTypeDiagnostic() throws {
        let source = """
        val bad: Int = "x"
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    func testPropertyGetterTypeMismatchReportsTypeDiagnostic() throws {
        let source = """
        val bad: Int {
            get() = "x"
        }
        """
        let ctx = try makeContext(source: source)
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
        let ctx = try makeContext(source: source)
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
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testOverloadRejectsBooleanArgumentForIntParameter() throws {
        let source = """
        fun foo(a: Int) = a
        fun bar() = foo(true)
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testCallSupportsMixedNamedAndPositionalArguments() throws {
        let source = """
        fun pick(x: Int, flag: Boolean) = x
        fun use() = pick(1, flag = true)
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testCallRejectsPositionalArgumentAfterNamedArgument() throws {
        let source = """
        fun pick(x: Int, y: Int) = x
        fun use() = pick(y = 1, 2)
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testCallSupportsNonTrailingVarargWithNamedTail() throws {
        let source = """
        fun sum(vararg items: Int, tail: Int) = tail
        fun use() = sum(1, 2, tail = 3)
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testCallRejectsSpreadForNonVarargParameter() throws {
        let source = """
        fun take(x: Int) = x
        fun use() = take(*1)
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testSemaAllowsOverloadedTopLevelFunctionsWithoutDuplicateDiagnostic() throws {
        let source = """
        fun pick(x: Int) = x
        fun pick(x: String) = x
        fun use() = pick(1)
        """
        let ctx = try makeContext(source: source)
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
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testBuildASTParsesExtensionFunctionReceiverType() throws {
        let source = """
        fun String.echo(): String = this
        """
        let ctx = try makeContext(source: source)
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
        let ctx = try makeContext(source: source)
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
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testGenericIdentityFunctionIsInferredAtCallSite() throws {
        let source = """
        fun <T> id(x: T): T = x
        fun takesInt(a: Int) = a
        fun main() = takesInt(id(1))
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testGenericConstraintFailureReportsTypeDiagnostic() throws {
        let source = """
        fun <T> id(x: T): T = x
        fun bad(): Boolean = id(1)
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
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
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
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
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
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
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let useSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && ctx.interner.resolve(symbol.name) == "use"
        })?.id)
        let useSignature = try XCTUnwrap(sema.symbols.functionSignature(for: useSymbol))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        XCTAssertEqual(useSignature.returnType, intType)

        assertNoDiagnostic("KSWIFTK-SEMA-0003", in: ctx)
    }

    func testImportAliasWildcardDiagnostic() throws {
        let sources = [
            """
            package lib
            fun helper(x: Int) = x
            """,
            """
            package app
            import lib as L
            fun use() = 1
            """
        ]
        let ctx = try makeContext(sources: sources)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasWildcardAlias = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0022"
        })
        XCTAssertTrue(hasWildcardAlias, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testImportAliasDuplicateDiagnostic() throws {
        let sources = [
            """
            package lib
            fun foo(x: Int) = x
            fun bar(x: Int) = x
            """,
            """
            package app
            import lib.foo as X
            import lib.bar as X
            fun use() = 1
            """
        ]
        let ctx = try makeContext(sources: sources)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasDuplicateAlias = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0023"
        })
        XCTAssertTrue(hasDuplicateAlias, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testImportAliasUnresolvedPathDiagnostic() throws {
        let source = """
        package app
        import nonexistent.Thing as X
        fun use() = 1
        """
        let ctx = try makeContext(source: source)

        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPassesPhase().run(ctx)

        let hasUnresolved = ctx.diagnostics.diagnostics.contains(where: { diag in
            diag.code == "KSWIFTK-SEMA-0024"
        })
        XCTAssertTrue(hasUnresolved, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
    }

    func testImportAliasResolvesAcrossPackages() throws {
        let sources = [
            """
            package lib
            fun helper(x: Int) = x
            """,
            """
            package app
            import lib.helper as h
            fun use() = h(1)
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
        XCTAssertFalse(hasNoViableDiagnostic, "codes: \(ctx.diagnostics.diagnostics.map(\.code))")
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

    func testFunctionExpressionBodyWhenRemainsExpressionBody() throws {
        let source = """
        fun classify(v: Int) = when (v) {
            0 -> 10
            else -> 20
        }
        """
        let ctx = try makeContext(source: source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let file = try XCTUnwrap(ast.files.first)
        let declID = try XCTUnwrap(file.topLevelDecls.first)
        guard let decl = ast.arena.decl(declID), case .funDecl(let function) = decl else {
            XCTFail("Expected top-level function declaration.")
            return
        }

        switch function.body {
        case .expr(let exprID, _):
            guard let expr = ast.arena.expr(exprID),
                  case .whenExpr(_, let branches, let elseExpr, _) = expr else {
                XCTFail("Expected expression body to be parsed as when expression.")
                return
            }
            XCTAssertEqual(branches.count, 1)
            XCTAssertNotNil(elseExpr)
        case .block, .unit:
            XCTFail("Expression-body function must not be parsed as block body.")
        }
    }

    func testBlockBodySplitsStatementsOnNewline() throws {
        let source = """
        fun main() {
            println(1)
            println(2)
        }
        """
        let ctx = try makeContext(source: source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let file = try XCTUnwrap(ast.files.first)
        let declID = try XCTUnwrap(file.topLevelDecls.first)
        guard let decl = ast.arena.decl(declID), case .funDecl(let function) = decl else {
            XCTFail("Expected top-level function declaration.")
            return
        }

        switch function.body {
        case .block(let exprIDs, _):
            XCTAssertEqual(exprIDs.count, 2)
            for exprID in exprIDs {
                guard let expr = ast.arena.expr(exprID), case .call = expr else {
                    XCTFail("Expected block statement to parse as call expression.")
                    return
                }
            }
        case .expr, .unit:
            XCTFail("Block-body function should produce block expressions.")
        }
    }

    func testSubjectLessWhenParsesCorrectly() throws {
        let source = """
        fun classify(x: Int, y: Int): Int {
            return when {
                x > 0 -> 1
                y > 0 -> 2
                else -> 0
            }
        }
        """
        let ctx = try makeContext(source: source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let file = try XCTUnwrap(ast.files.first)
        let declID = try XCTUnwrap(file.topLevelDecls.first)
        guard let decl = ast.arena.decl(declID), case .funDecl(let function) = decl else {
            XCTFail("Expected top-level function declaration.")
            return
        }

        switch function.body {
        case .block(let stmts, _):
            guard let returnExprID = stmts.first,
                  let returnExpr = ast.arena.expr(returnExprID),
                  case .returnExpr(let whenID, _) = returnExpr,
                  let whenID,
                  let whenExpr = ast.arena.expr(whenID),
                  case .whenExpr(let subject, let branches, let elseExpr, _) = whenExpr else {
                XCTFail("Expected return of when expression.")
                return
            }
            XCTAssertNil(subject, "Subject-less when must have nil subject.")
            XCTAssertEqual(branches.count, 2)
            XCTAssertNotNil(elseExpr)
        case .expr, .unit:
            XCTFail("Block-body function should produce block expressions.")
        }
    }

    func testSubjectLessWhenGuardChainSemaPassesWithElse() throws {
        let source = """
        fun classify(x: Int, y: Int): Int = when {
            x > 0 -> 1
            y > 0 -> 2
            else -> 0
        }
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    func testSubjectLessWhenWithoutElseIsNonExhaustive() throws {
        let source = """
        fun classify(x: Int): Int {
            when {
                x > 0 -> 1
            }
        }
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    func testUnresolvedIdentifierEmitsDiagnostic() throws {
        let source = """
        fun test() = unknownVariable
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    func testUnresolvedFunctionCallEmitsDiagnostic() throws {
        let source = """
        fun test() = unknownFunction(1)
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testUnresolvedTypeAnnotationEmitsDiagnostic() throws {
        let source = """
        fun test(x: UnknownType) = x
        """
        let ctx = try makeContext(source: source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
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
