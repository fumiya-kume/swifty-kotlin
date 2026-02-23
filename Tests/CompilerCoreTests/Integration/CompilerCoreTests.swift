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
        assertNoDiagnostic("KSWIFTK-SEMA-0021", in: ctx)
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

        // P5-78: sealed missing-branch diagnostic now uses KSWIFTK-SEMA-0021
        assertHasDiagnostic("KSWIFTK-SEMA-0021", in: ctx)
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

    func testImportAliasBuildASTPreservesAliasField() throws {
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
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let appFile = try XCTUnwrap(ast.files.first(where: { file in
            file.packageFQName.map { ctx.interner.resolve($0) } == ["app"]
        }))
        let aliasedImport = try XCTUnwrap(appFile.imports.first(where: { importDecl in
            importDecl.alias != nil
        }))
        XCTAssertEqual(ctx.interner.resolve(aliasedImport.alias!), "h")
        XCTAssertEqual(aliasedImport.path.map { ctx.interner.resolve($0) }, ["lib", "helper"])
    }

    func testImportAliasNonAliasedImportHasNilAlias() throws {
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
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let appFile = try XCTUnwrap(ast.files.first(where: { file in
            file.packageFQName.map { ctx.interner.resolve($0) } == ["app"]
        }))
        let regularImport = try XCTUnwrap(appFile.imports.first)
        XCTAssertNil(regularImport.alias)
    }

    func testLambdaInferenceCapturesOuterLocalAndResolvesLocalCallableCall() throws {
        let source = """
        fun host(seed: Int): Int {
            val offset = seed
            val add: (Int) -> Int = { value -> value + offset }
            return add(1)
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let lambdaExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            if case .lambdaLiteral = expr { return true }
            return false
        })
        let addCallExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case .call(let calleeExprID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeExprID),
                  case .nameRef(let calleeName, _) = calleeExpr else {
                return false
            }
            return ctx.interner.resolve(calleeName) == "add"
        })

        let lambdaType = try XCTUnwrap(sema.bindings.exprTypes[lambdaExprID])
        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case .functionType(let functionType) = sema.types.kind(of: lambdaType) else {
            XCTFail("Lambda should infer function type.")
            return
        }
        XCTAssertEqual(functionType.params, [intType])
        XCTAssertEqual(functionType.returnType, intType)

        let offsetSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .local && ctx.interner.resolve(symbol.name) == "offset"
        })?.id)
        XCTAssertEqual(sema.bindings.captureSymbolsByExpr[lambdaExprID], [offsetSymbol])
        XCTAssertNotNil(sema.bindings.callableValueCalls[addCallExprID])
    }

    func testCallableReferenceInfersFunctionTypeAndBindsTargetSymbol() throws {
        let source = """
        fun target(x: Int): Int = x + 1
        fun use(): Int {
            val ref: (Int) -> Int = ::target
            return ref(1)
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let callableRefExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let refCallExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case .call(let calleeExprID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeExprID),
                  case .nameRef(let calleeName, _) = calleeExpr else {
                return false
            }
            return ctx.interner.resolve(calleeName) == "ref"
        })
        let targetSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && ctx.interner.resolve(symbol.name) == "target"
        })?.id)

        XCTAssertEqual(sema.bindings.identifierSymbols[callableRefExprID], targetSymbol)
        XCTAssertEqual(sema.bindings.callableTargets[callableRefExprID], .symbol(targetSymbol))
        XCTAssertEqual(sema.bindings.captureSymbolsByExpr[callableRefExprID], [])

        let refType = try XCTUnwrap(sema.bindings.exprTypes[callableRefExprID])
        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case .functionType(let functionType) = sema.types.kind(of: refType) else {
            XCTFail("Callable reference should infer function type.")
            return
        }
        XCTAssertEqual(functionType.params, [intType])
        XCTAssertEqual(functionType.returnType, intType)
        XCTAssertNotNil(sema.bindings.callableValueCalls[refCallExprID])
    }

    func testBoundCallableReferenceCapturesReceiverAndResolvesExtensionTarget() throws {
        let source = """
        fun Int.incByOne(): Int = this + 1
        fun host(seed: Int): Int {
            val ref: () -> Int = seed::incByOne
            return ref()
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let callableRefExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let extensionSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && ctx.interner.resolve(symbol.name) == "incByOne"
        })?.id)
        let seedSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .valueParameter && ctx.interner.resolve(symbol.name) == "seed"
        })?.id)

        XCTAssertEqual(sema.bindings.callableTargets[callableRefExprID], .symbol(extensionSymbol))
        XCTAssertEqual(sema.bindings.captureSymbolsByExpr[callableRefExprID], [seedSymbol])

        let callableType = try XCTUnwrap(sema.bindings.exprTypes[callableRefExprID])
        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case .functionType(let functionType) = sema.types.kind(of: callableType) else {
            XCTFail("Bound callable reference should infer function type.")
            return
        }
        XCTAssertEqual(functionType.params.count, 0)
        XCTAssertEqual(functionType.returnType, intType)
    }

    func testCallableReferenceOverloadSelectionBindsDeterministicTargetSymbol() throws {
        let source = """
        fun target(x: String): String = x
        fun target(x: Int): Int = x + 1
        fun use(): Int {
            val ref: (Int) -> Int = ::target
            return ref(1)
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0003", in: ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let callableRefExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let intOverloadSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            guard symbol.kind == .function,
                  ctx.interner.resolve(symbol.name) == "target",
                  let signature = sema.symbols.functionSignature(for: symbol.id),
                  signature.parameterTypes.count == 1,
                  signature.parameterTypes[0] == intType else {
                return false
            }
            return true
        })?.id)

        XCTAssertEqual(sema.bindings.identifierSymbols[callableRefExprID], intOverloadSymbol)
        XCTAssertEqual(sema.bindings.callableTargets[callableRefExprID], .symbol(intOverloadSymbol))
    }

    func testDirectCallableReferenceCallPropagatesSymbolTargetBinding() throws {
        let source = """
        fun target(x: String): String = x
        fun target(x: Int): Int = x + 1
        fun use(): Int = (::target)(1)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0003", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let intOverloadSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            guard symbol.kind == .function,
                  ctx.interner.resolve(symbol.name) == "target",
                  let signature = sema.symbols.functionSignature(for: symbol.id),
                  signature.parameterTypes.count == 1,
                  signature.parameterTypes[0] == intType else {
                return false
            }
            return true
        })?.id)
        let callExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case .call(let calleeExprID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeExprID) else {
                return false
            }
            if case .callableRef = calleeExpr {
                return true
            }
            return false
        })

        let callBinding = try XCTUnwrap(sema.bindings.callableValueCalls[callExprID])
        XCTAssertEqual(callBinding.target, .symbol(intOverloadSymbol))
        XCTAssertEqual(callBinding.parameterMapping, [0: 0])
        XCTAssertEqual(sema.bindings.callableTargets[callExprID], .symbol(intOverloadSymbol))
    }

    func testFunctionTypeParameterCallUsesCallableValueResolution() throws {
        let source = """
        fun apply(f: (Int) -> Int, x: Int): Int = f(x)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let callExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
            guard case .call(let calleeExprID, _, _, _) = expr,
                  let calleeExpr = ast.arena.expr(calleeExprID),
                  case .nameRef(let calleeName, _) = calleeExpr else {
                return false
            }
            return ctx.interner.resolve(calleeName) == "f"
        })
        let fParamSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .valueParameter && ctx.interner.resolve(symbol.name) == "f"
        })?.id)
        let callableCallBinding = try XCTUnwrap(sema.bindings.callableValueCalls[callExprID])
        XCTAssertEqual(callableCallBinding.target, .localValue(fParamSymbol))
        XCTAssertEqual(callableCallBinding.parameterMapping, [0: 0])

        let intType = sema.types.make(.primitive(.int, .nonNull))
        guard case .functionType(let functionType) = sema.types.kind(of: callableCallBinding.functionType) else {
            XCTFail("Callable value call binding should store function type.")
            return
        }
        XCTAssertEqual(functionType.params, [intType])
        XCTAssertEqual(functionType.returnType, intType)
    }

    func testEmitObjectProducesMachOFile() throws {
        let source = "fun main() {}"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try withTemporaryFile(contents: source) { tempSourcePath in
            let options = CompilerOptions(
                moduleName: "ObjTest",
                inputs: [tempSourcePath],
                outputPath: outputURL.path,
                emit: .object,
                target: defaultTargetTriple()
            )
            let driver = CompilerDriver(
                version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
                kotlinVersion: .v2_3_10
            )

            let exitCode = driver.run(options: options)
            XCTAssertEqual(exitCode, 0)
            let data = try Data(contentsOf: outputURL)
            XCTAssertGreaterThanOrEqual(data.count, 4)
            #if os(Linux)
            // ELF magic number
            XCTAssertEqual(Array(data.prefix(4)), [0x7F, 0x45, 0x4C, 0x46])
            #else
            // Mach-O magic number
            XCTAssertEqual(Array(data.prefix(4)), [0xCF, 0xFA, 0xED, 0xFE])
            #endif
        }
    }

    func testEmitExecutableFailsWithoutMainFunction() throws {
        let source = "fun notMain() {}"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        try withTemporaryFile(contents: source) { tempSourcePath in
            let options = CompilerOptions(
                moduleName: "ExeTest",
                inputs: [tempSourcePath],
                outputPath: outputURL.path,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let driver = CompilerDriver(
                version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
                kotlinVersion: .v2_3_10
            )

            let exitCode = driver.run(options: options)
            XCTAssertEqual(exitCode, 1)
        }
    }

    func testDriverReportsPipelineOutputUnavailableWithoutICE() throws {
        let source = "fun main() = 0"
        let missingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing")
        let outputBase = missingDir.appendingPathComponent("result").path

        try withTemporaryFile(contents: source) { tempSourcePath in
            let options = CompilerOptions(
                moduleName: "PipelineFailure",
                inputs: [tempSourcePath],
                outputPath: outputBase,
                emit: .kirDump,
                target: defaultTargetTriple()
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
    }

    func testFunctionExpressionBodyWhenRemainsExpressionBody() throws {
        let source = """
        fun classify(v: Int) = when (v) {
            0 -> 10
            else -> 20
        }
        """
        let ctx = try makeContextFromSource(source)
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
        let ctx = try makeContextFromSource(source)
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

    func testLambdaLiteralExpressionBodyParsesAsDedicatedExprNode() throws {
        let source = """
        fun build() = { x: Int -> x + 1 }
        """
        let ctx = try makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let function = try XCTUnwrap(topLevelFunction(named: "build", in: ast, interner: ctx.interner))
        guard case .expr(let exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case .lambdaLiteral(let params, let bodyExprID, _) = expr else {
            XCTFail("Expected lambda literal expression body.")
            return
        }

        XCTAssertEqual(params.map { ctx.interner.resolve($0) }, ["x"])
        guard let bodyExpr = ast.arena.expr(bodyExprID),
              case .binary = bodyExpr else {
            XCTFail("Expected parsed lambda body expression.")
            return
        }
    }

    func testObjectLiteralExpressionBodyParsesAsDedicatedExprNode() throws {
        let source = """
        interface I
        fun build() = object : I {}
        """
        let ctx = try makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let function = try XCTUnwrap(topLevelFunction(named: "build", in: ast, interner: ctx.interner))
        guard case .expr(let exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case .objectLiteral(let superTypes, _) = expr else {
            XCTFail("Expected object literal expression body.")
            return
        }

        XCTAssertEqual(superTypes.count, 1)
        let superType = try XCTUnwrap(ast.arena.typeRef(superTypes[0]))
        guard case .named(let path, _, _) = superType,
              let first = path.first else {
            XCTFail("Expected named super type in object literal.")
            return
        }
        XCTAssertEqual(ctx.interner.resolve(first), "I")
    }

    func testCallableReferenceExpressionBodyParsesAsDedicatedExprNode() throws {
        let source = """
        fun target(x: Int) = x
        fun unbound() = ::target
        fun bound(x: Int) = x::toString
        """
        let ctx = try makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let unbound = try XCTUnwrap(topLevelFunction(named: "unbound", in: ast, interner: ctx.interner))
        guard case .expr(let unboundExprID, _) = unbound.body,
              let unboundExpr = ast.arena.expr(unboundExprID),
              case .callableRef(let unboundReceiver, let unboundMember, _) = unboundExpr else {
            XCTFail("Expected unbound callable reference.")
            return
        }
        XCTAssertNil(unboundReceiver)
        XCTAssertEqual(ctx.interner.resolve(unboundMember), "target")

        let bound = try XCTUnwrap(topLevelFunction(named: "bound", in: ast, interner: ctx.interner))
        guard case .expr(let boundExprID, _) = bound.body,
              let boundExpr = ast.arena.expr(boundExprID),
              case .callableRef(let boundReceiver, let boundMember, _) = boundExpr else {
            XCTFail("Expected bound callable reference.")
            return
        }
        XCTAssertEqual(ctx.interner.resolve(boundMember), "toString")
        let receiverExprID = try XCTUnwrap(boundReceiver)
        guard let receiverExpr = ast.arena.expr(receiverExprID),
              case .nameRef(let receiverName, _) = receiverExpr else {
            XCTFail("Expected callable reference receiver expression.")
            return
        }
        XCTAssertEqual(ctx.interner.resolve(receiverName), "x")
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
        let ctx = try makeContextFromSource(source)
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
        let ctx = try makeContextFromSource(source)
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
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    func testSubjectLessWhenWithNonBooleanConditionEmitsDiagnostic() throws {
        let source = """
        fun test() = when {
            42 -> "invalid"
            else -> "ok"
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0032", in: ctx)
    }

    func testUnresolvedIdentifierEmitsDiagnostic() throws {
        let source = """
        fun test() = unknownVariable
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    func testUnresolvedFunctionCallEmitsDiagnostic() throws {
        let source = """
        fun test() = unknownFunction(1)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testUnresolvedTypeAnnotationEmitsDiagnostic() throws {
        let source = """
        fun test(x: UnknownType) = x
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    // MARK: - P5-40 Regression: Strict unresolved reference / type diagnostics

    func testUnresolvedIdentifierInBlockEmitsDiagnostic() throws {
        let source = """
        fun test(): Int {
            val x = missingIdent
            return 0
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    func testUnresolvedIdentifierInBinaryExprEmitsDiagnostic() throws {
        let source = """
        fun test(): Int = 1 + noSuchVar
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }

    func testUnresolvedFunctionCallWithMultipleArgsEmitsDiagnostic() throws {
        let source = """
        fun test() = missingFun(1, 2, 3)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testUnresolvedFunctionCallInNestedExprEmitsDiagnostic() throws {
        let source = """
        fun known(x: Int): Int = x
        fun test(): Int = known(unknownFn())
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testUnresolvedMemberCallEmitsDiagnostic() throws {
        let source = """
        class Foo
        fun test(f: Foo) = f.missing()
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testUnresolvedSafeMemberCallFallsBackToAnyNullable() throws {
        // Safe member calls with unknown methods fall back to Any? (not errorType)
        // because the compiler may not enumerate all built-in methods (e.g. hashCode).
        let source = """
        class Foo
        fun test(f: Foo?) = f?.missing()
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testUnresolvedBinaryOperatorEmitsDiagnostic() throws {
        let source = """
        class Foo
        fun test(f: Foo): Foo = f + f
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testUnresolvedTypeAnnotationOnLocalVarEmitsDiagnostic() throws {
        let source = """
        fun test() {
            val x: NoSuchType = 42
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testUnresolvedReturnTypeAnnotationEmitsDiagnostic() throws {
        let source = """
        fun test(): MissingReturn = 1
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testUnresolvedPropertyTypeAnnotationEmitsDiagnostic() throws {
        let source = """
        class Holder {
            val x: GhostType = 0
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testResolvedIdentifierDoesNotEmitUnresolvedDiagnostic() throws {
        let source = """
        fun test(): Int {
            val x = 10
            return x
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testResolvedFunctionCallDoesNotEmitUnresolvedDiagnostic() throws {
        let source = """
        fun helper(x: Int): Int = x
        fun test(): Int = helper(42)
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }

    func testResolvedTypeAnnotationDoesNotEmitUnresolvedDiagnostic() throws {
        let source = """
        fun test(x: Int): String = "ok"
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testUnresolvedLocalFunParamTypeEmitsDiagnostic() throws {
        let source = """
        fun outer() {
            fun inner(p: Phantom): Int = 0
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    func testUnresolvedLocalFunReturnTypeEmitsDiagnostic() throws {
        let source = """
        fun outer() {
            fun inner(): Ghost = 0
        }
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: ctx)
    }

    // MARK: - P5-40 Cascading diagnostic suppression

    func testCascadingBinaryAddOnUnresolvedIdentifierEmitsOnlyOneError() throws {
        let source = """
        fun test(): Int = noSuchVar + 1
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 0, in: ctx)
    }

    func testCascadingMemberCallOnUnresolvedReceiverEmitsOnlyOneError() throws {
        let source = """
        fun test(): Int = unknownObj.method()
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0024", expected: 0, in: ctx)
    }

    func testCascadingSafeMemberCallOnUnresolvedReceiverEmitsOnlyOneError() throws {
        let source = """
        fun test() = missingVar?.call()
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0024", expected: 0, in: ctx)
    }

    func testCascadingBinarySubtractOnUnresolvedIdentifierEmitsOnlyOneError() throws {
        let source = """
        fun test(): Int = noSuchVar - 1
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 0, in: ctx)
    }

    func testCascadingBinaryMultiplyOnUnresolvedIdentifierEmitsOnlyOneError() throws {
        let source = """
        fun test(): Int = noSuchVar * 2
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: ctx)
        assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 0, in: ctx)
    }

    // MARK: - P5-40 Resolved negative tests (no spurious diagnostics)

    func testResolvedMemberCallDoesNotEmitUnresolvedDiagnostic() throws {
        let source = """
        class Foo {
            fun bar(): Int = 42
        }
        fun test(f: Foo): Int = f.bar()
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testResolvedSafeMemberCallDoesNotEmitUnresolvedDiagnostic() throws {
        let source = """
        class Foo {
            fun bar(): Int = 42
        }
        fun test(f: Foo?): Int? = f?.bar()
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    func testResolvedBinaryAddDoesNotEmitOperatorDiagnostic() throws {
        let source = """
        fun test(): Int = 1 + 2
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testResolvedBinaryComparisonDoesNotEmitOperatorDiagnostic() throws {
        let source = """
        fun test(): Boolean = 1 == 2
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    func testResolvedStringConcatDoesNotEmitOperatorDiagnostic() throws {
        let source = """
        fun test(): String = "a" + "b"
        """
        let ctx = try makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    private func topLevelFunction(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> FunDecl? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case .funDecl(let function) = decl else {
                    continue
                }
                if interner.resolve(function.name) == name {
                    return function
                }
            }
        }
        return nil
    }


}
