import Foundation
import XCTest
@testable import CompilerCore


extension CompilerCoreTests {
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
        let ctx = try makeContextFromSources(sources)
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
        let ctx = try makeContextFromSources(sources)
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
        let ctx = try makeContextFromSources(sources)
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
        let ctx = try makeContextFromSources(sources)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
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
        let ctx = try makeContextFromSources(sources)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testImportAliasUnresolvedPathDiagnostic() throws {
        let source = """
        package app
        import nonexistent.Thing as X
        fun use() = 1
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
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
        let ctx = try makeContextFromSources(sources)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testImportAliasReturnTypeIsInferred() throws {
        let sources = [
            """
            package lib
            fun compute(x: Int): Int = x + 1
            """,
            """
            package app
            import lib.compute as calc
            fun use(): Int = calc(5)
            """
        ]
        let ctx = try makeContextFromSources(sources)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let useSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && ctx.interner.resolve(symbol.name) == "use"
        })?.id)
        let useSignature = try XCTUnwrap(sema.symbols.functionSignature(for: useSymbol))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        XCTAssertEqual(useSignature.returnType, intType)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testImportAliasMultipleDistinctAliasesInSameFile() throws {
        let sources = [
            """
            package lib
            fun foo(x: Int) = x
            fun bar(x: Int) = x + 1
            """,
            """
            package app
            import lib.foo as f
            import lib.bar as b
            fun use() = f(1) + b(2)
            """
        ]
        let ctx = try makeContextFromSources(sources)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testImportAliasCoexistsWithNonAliasedImport() throws {
        let sources = [
            """
            package lib
            fun foo(x: Int) = x
            fun bar(x: Int) = x + 1
            """,
            """
            package app
            import lib.foo as f
            import lib.bar
            fun use() = f(1) + bar(2)
            """
        ]
        let ctx = try makeContextFromSources(sources)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testImportAliasEmptyAliasNameIsIgnored() throws {
        let source = """
        package app
        import kotlin.io.println as
        fun use() = 1
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        // Parser should insert missing token; alias with empty name is skipped
        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

}
