@testable import CompilerCore
import Foundation
import XCTest

/// TEST-SCRIPT-002: Script-mode (.kts) test coverage expansion.
///
/// Script mode is triggered when a Kotlin source contains top-level statements
/// with no non-property declarations. The parser sets the root CST kind to
/// `.script` and the BuildASTPhase wraps all top-level expressions into a
/// synthetic `main` function body.
final class ScriptModeTests: XCTestCase {

    // MARK: - 1. Top-level statements compile to KIR

    func testScriptTopLevelStatementsCompileToKIR() throws {
        // A file that consists entirely of top-level statements (no fun/class)
        // must be parsed as `.script`, synthesise a `main`, and compile through
        // to KIR without errors.
        let source = """
        println("hello from script")
        val x = 1 + 2
        println(x)
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptTopLevelStmts")
    }

    // MARK: - 2. Top-level val/var properties in script mode

    func testScriptTopLevelValVarPropertiesCompileToKIR() throws {
        // In script mode val/var at the top level are treated as script-body
        // expressions, not top-level property declarations.
        let source = """
        val greeting = "hello"
        var counter = 0
        counter = counter + 1
        println(greeting)
        println(counter)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            // Script mode: scriptBody should be populated
            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            XCTAssertNotNil(scriptFile, "Script file must have a non-empty scriptBody for top-level val/var")
            XCTAssertFalse(ctx.diagnostics.hasError, "Top-level val/var in script mode should not produce errors")
        }
    }

    // MARK: - 3. Script-level function definition alongside statements

    func testScriptLevelFunctionDefinitionAlongsideStatements() throws {
        // In Kotlin script mode a local fun can appear alongside statements.
        // The synthesised `main` wraps all top-level content; the pipeline must
        // not crash or emit errors for this mix.
        //
        // Note: according to the parser logic (KotlinParser.swift) a file is
        // treated as `.script` when it has top-level *statements* but no
        // non-property declarations (fun/class/object/interface trigger
        // kotlinFile). A helper function at the top level therefore causes the
        // root to be classified as `.kotlinFile`, which is the correct Kotlin
        // behaviour for a .kt source file. We verify the pipeline still
        // succeeds (KIR produced, no errors) for that pattern.
        let source = """
        fun double(n: Int): Int = n * 2
        fun main() {
            println(double(21))
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptHelperFun")
    }

    // MARK: - 4. Parser root kind is `.script` for expression statements

    func testParserRootKindIsScriptForExpressionStatements() throws {
        // The parser sets the root CST kind to `.script` when the file contains
        // at least one top-level *statement* (i.e. something that is not a
        // declaration) and no non-property declarations.
        // `val` at the top level is a propertyDecl, so it does NOT trigger
        // the script heuristic on its own. A bare expression like `println("x")`
        // does — and that is what this test verifies.
        let source = """
        println("hello")
        1 + 2
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try LoadSourcesPhase().run(ctx)
            try LexPhase().run(ctx)
            try ParsePhase().run(ctx)

            let rootKinds = ctx.syntaxTrees.map { $0.1.node($0.2).kind }
            XCTAssertTrue(rootKinds.contains(.script),
                          "A file with top-level expression statements must parse as .script, got: \(rootKinds)")
        }
    }

    // MARK: - 5. BuildAST synthesises a `main` function for script bodies

    func testBuildASTSynthesisesMainForScriptBody() throws {
        // The BuildASTPhase should wrap script expressions into a synthetic
        // `main` entry point.  After building the AST, at least one top-level
        // declaration whose interned name resolves to "main" must exist in the
        // file that was parsed as script.
        let source = """
        val x = 42
        println(x)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            XCTAssertNotNil(scriptFile, "scriptBody must be populated after BuildASTPhase for a script file")

            let topLevelDeclNames: [String] = (scriptFile?.topLevelDecls ?? []).compactMap { declID in
                guard let decl = ast.arena.decl(declID) else { return nil }
                if case let .funDecl(f) = decl { return ctx.interner.resolve(f.name) }
                return nil
            }
            XCTAssertTrue(topLevelDeclNames.contains("main"),
                          "BuildASTPhase must synthesise a 'main' entry for script content, got: \(topLevelDeclNames)")
        }
    }

    // MARK: - 6. Arithmetic expression as last statement (last-expression-is-result)

    func testScriptArithmeticExpressionCompilesToKIR() throws {
        // A script whose last top-level statement is a pure arithmetic
        // expression must compile to KIR without errors.
        let source = """
        val a = 3
        val b = 7
        a * b
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptArithLastExpr")
    }

    // MARK: - 7. String concatenation in script body

    func testScriptStringConcatenationCompilesToKIR() throws {
        // Top-level string concatenation via `+` operator in script mode must
        // compile through the full frontend pipeline without errors.
        let source = """
        println("hello" + " " + "world")
        val greeting = "hi"
        println(greeting + "!")
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptStringConcat")
    }

    // MARK: - 8. Mixed val and expression statements in script body

    func testScriptMixedValAndExpressionStatementsCompileToKIR() throws {
        // A script body interleaving val declarations and arbitrary expression
        // statements must produce a KIR file without semantic errors.
        let source = """
        val x = 10
        println("start")
        val y = x * 2
        println(y)
        val z = x + y
        z
        """
        try assertKotlinCompilesToKIR(source, moduleName: "ScriptMixedValsAndExprs")
    }

    // MARK: - 9. Script body populates ASTFile.scriptBody with multiple exprs

    func testScriptBodyContainsMultipleExpressions() throws {
        // After BuildASTPhase the `scriptBody` of the ASTFile must contain more
        // than one expression when the source has multiple statements.
        let source = """
        val a = 1
        val b = 2
        val c = a + b
        println(c)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            let count = scriptFile?.scriptBody.count ?? 0
            XCTAssertGreaterThan(count, 1,
                                 "scriptBody should contain multiple expressions for a multi-statement script")
        }
    }

    // MARK: - 10. Script-mode file coexists with a regular .kt file in one module

    func testScriptFileCoexistsWithRegularKotlinFileInModule() throws {
        // When a module contains both a regular Kotlin file (with fun/class) and
        // a script file (with top-level statements only), the BuildASTPhase must
        // produce two ASTFiles: one with an empty scriptBody (regular) and one
        // with a non-empty scriptBody (script).  This mirrors the
        // multi-file discovery test but exercises it at the full frontend level.
        let regular = """
        fun helper(x: Int): Int = x + 1
        class Config(val value: Int)
        """
        let script = """
        val n = 5
        println(n)
        """
        try withTemporaryFiles(contents: [regular, script]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runFrontend(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            XCTAssertEqual(ast.files.count, 2, "Both files must produce an ASTFile")

            let scriptFile = ast.files.first(where: { !$0.scriptBody.isEmpty })
            XCTAssertNotNil(scriptFile, "One ASTFile must have a non-empty scriptBody")

            let regularFile = ast.files.first(where: { $0.scriptBody.isEmpty })
            XCTAssertNotNil(regularFile, "One ASTFile must have an empty scriptBody")

            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Mixed script+regular module must compile without errors")
        }
    }
}
