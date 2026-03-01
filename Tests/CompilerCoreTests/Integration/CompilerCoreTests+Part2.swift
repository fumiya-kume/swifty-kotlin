import Foundation
import XCTest
@testable import CompilerCore


extension CompilerCoreTests {
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
        let ctx = makeContextFromSources(sources)
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
        let ctx = makeContextFromSources(sources)
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
        let ctx = makeContextFromSource(source)
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
        let ctx = makeContextFromSource(source)
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
        let ctx = makeContextFromSource(source)
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
        let ctx = makeContextFromSource(source)
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
        let ctx = makeContextFromSource(source)
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
        let ctx = makeContextFromSource(source)
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

}
