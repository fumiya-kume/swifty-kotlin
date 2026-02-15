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

        XCTAssertNotEqual(funDecl.name.rawValue, invalidID)
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
