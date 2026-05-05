@testable import CompilerCore
import Foundation
import XCTest

final class SemanticsAndUtilitiesRegressionTests: XCTestCase {
    private func memberCallExprIDs(named name: String, in ast: ASTModule, interner: StringInterner) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

    func testAtomicStoreExpressionIsTypedAsUnit() throws {
        let source = """
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val ai = AtomicInt(1)
            val x = ai.store(2)
            val y: Unit = x
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Atomic.store() should be typed as Unit: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testBuilderMemberChainWithSameNamePropertiesResolvesMemberFunctions() throws {
        let source = """
        class Config(
            val host: String,
            val port: Int,
            val debug: Boolean
        ) {
            class Builder {
                var host: String = "localhost"
                var port: Int = 8080
                var debug: Boolean = false

                fun host(h: String): Builder { host = h; return this }
                fun port(p: Int): Builder { port = p; return this }
                fun debug(d: Boolean): Builder { debug = d; return this }
                fun build(): Config = Config(host, port, debug)
            }
        }

        fun main() {
            val cfg = Config.Builder()
                .host("example.com")
                .port(443)
                .debug(true)
                .build()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let interner = ctx.interner
            let helpers = TypeCheckHelpers()

            let builderSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: [interner.intern("Config"), interner.intern("Builder")]),
                "Expected nested Config.Builder symbol"
            )
            let builderType = sema.types.make(.classType(ClassType(classSymbol: builderSymbol, args: [], nullability: .nonNull)))
            let portCandidates = helpers.collectMemberFunctionCandidates(
                named: interner.intern("port"),
                receiverType: builderType,
                sema: sema,
                interner: interner
            )
            XCTAssertTrue(
                portCandidates.contains { candidate in
                    sema.symbols.symbol(candidate)?.fqName == [interner.intern("Config"), interner.intern("Builder"), interner.intern("port")]
                },
                "Expected Config.Builder.port to be visible among candidates"
            )

            let hostCall = try XCTUnwrap(memberCallExprIDs(named: "host", in: ast, interner: interner).first)
            let portCall = try XCTUnwrap(memberCallExprIDs(named: "port", in: ast, interner: interner).first)
            let hostExprType = sema.bindings.exprTypes[hostCall]
            let portExprType = sema.bindings.exprTypes[portCall]

            if case let .memberCall(portReceiverExpr, _, _, _, _) = ast.arena.expr(portCall) {
                let portReceiverType = sema.bindings.exprTypes[portReceiverExpr]
                XCTAssertEqual(
                    portReceiverType,
                    builderType,
                    "Expected host() result used as port() receiver to stay Config.Builder, got \(portReceiverType.map(sema.types.renderType) ?? "nil"); diagnostics: \(diagnostics)"
                )
            } else {
                XCTFail("Expected port call expression to be a memberCall")
            }

            XCTAssertNotNil(sema.bindings.callBinding(for: hostCall)?.chosenCallee, "Expected host() call to resolve")
            XCTAssertEqual(
                hostExprType,
                builderType,
                "Expected host() to return Config.Builder, got \(hostExprType.map(sema.types.renderType) ?? "nil"); diagnostics: \(diagnostics)"
            )
            XCTAssertEqual(
                portExprType,
                builderType,
                "Expected port() to return Config.Builder, got \(portExprType.map(sema.types.renderType) ?? "nil"); diagnostics: \(diagnostics)"
            )
            XCTAssertNotNil(
                sema.bindings.callBinding(for: portCall)?.chosenCallee,
                "Expected port() call to resolve; diagnostics: \(diagnostics)"
            )
        }
    }

    func testLegacyAtomicTypeAliasStillResolves() throws {
        let source = """
        import kotlin.concurrent.AtomicInt

        fun main() {
            val ai = AtomicInt(1)
            println(ai.load())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Legacy kotlin.concurrent.AtomicInt alias should still resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testExperimentalAtomicOptInMarkerIsResolved() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.ExperimentalAtomicApi

        fun main() {
            println("ok")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "ExperimentalAtomicApi marker should resolve under OptIn: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testAtomicReferenceInAtomicsPackageIsResolved() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.ExperimentalAtomicApi
        import kotlin.concurrent.atomics.AtomicReference

        fun main() {
            val ar = AtomicReference("hello")
            println(ar.load())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "ExperimentalAtomicApi marker should resolve under OptIn: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testAtomicLongInConcurrentPackageIsResolved() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.AtomicLong

        fun main() {
            val al = AtomicLong(42L)
            println(al.load())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "AtomicLong in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testExperimentalAtomicArraysInAtomicsPackageAreResolved() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val ints = AtomicIntArray(2)
            ints.storeAt(0, 10)
            ints.storeAt(1, 20)
            val ok = ints.compareAndSetAt(1, 20, 21)
            val old = ints.exchangeAt(0, 11)
            val sum = ints.loadAt(0) + ints.loadAt(1) + if (ok) old else 0

            val longs = AtomicLongArray(1)
            longs.storeAt(0, 1L)
            println(sum)
            println(longs.addAndFetchAt(0, 1L))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Experimental atomic arrays in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testCopyActionContextInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.CopyActionContext

        class CopyContextHolder(val context: CopyActionContext?)

        fun keepCopyContext(context: CopyActionContext): CopyActionContext {
            return context
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "CopyActionContext in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testAtomicNativePtrInAtomicsPackageSurfaceIsResolved() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicNativePtr
        import kotlinx.cinterop.NativePtr

        fun touchAtomicNativePtr(initial: NativePtr, next: NativePtr): NativePtr {
            val atomic = AtomicNativePtr(initial)
            atomic.value = next
            atomic.store(initial)
            val loaded = atomic.load()
            val exchanged = atomic.exchange(next)
            atomic.compareAndSet(exchanged, loaded)
            return atomic.compareAndExchange(loaded, next)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "AtomicNativePtr in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testPathNameExtensionPropertyInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.name

        fun pathName(path: Path): String {
            val name: String = path.name
            return name
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.name extension property in kotlin.io.path should resolve as String: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testCopyActionResultInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.CopyActionResult

        fun nextCopyActionResult(result: CopyActionResult): CopyActionResult {
            return when (result) {
                CopyActionResult.CONTINUE -> CopyActionResult.SKIP_SUBTREE
                CopyActionResult.SKIP_SUBTREE -> CopyActionResult.TERMINATE
                CopyActionResult.TERMINATE -> CopyActionResult.CONTINUE
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "CopyActionResult entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testPathAppendTextExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.appendText
        import kotlin.text.Charsets

        fun appendPathText(path: Path, text: CharSequence): Path {
            val first = path.appendText(text)
            val second = path.appendText(text, Charsets.UTF_8)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.appendText extension functions in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charSequenceSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "CharSequence"].map(interner.intern)))
            let charsetSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charSequenceType = types.make(.classType(ClassType(classSymbol: charSequenceSymbol, args: [], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let appendTextSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "appendText"].map(interner.intern))
            let defaultAppendText = try XCTUnwrap(appendTextSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charSequenceType]
                    && signature.returnType == pathType
            })
            let charsetAppendText = try XCTUnwrap(appendTextSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charSequenceType, charsetType]
                    && signature.returnType == pathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: defaultAppendText), "kk_path_appendText_default")
            XCTAssertEqual(symbols.externalLinkName(for: charsetAppendText), "kk_path_appendText")

            let defaultSignature = try XCTUnwrap(symbols.functionSignature(for: defaultAppendText))
            let charsetSignature = try XCTUnwrap(symbols.functionSignature(for: charsetAppendText))
            XCTAssertEqual(defaultSignature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(charsetSignature.valueParameterHasDefaultValues, [false, false])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "appendText", in: ast, interner: interner)

            XCTAssertEqual(callExprs.count, 2)
            let chosenCallees = callExprs.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }
            XCTAssertTrue(chosenCallees.contains(defaultAppendText))
            XCTAssertTrue(chosenCallees.contains(charsetAppendText))
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], pathType)
            }
        }
    }

    func testOnErrorResultInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.OnErrorResult

        fun nextOnErrorResult(result: OnErrorResult): OnErrorResult {
            return when (result) {
                OnErrorResult.SKIP_SUBTREE -> OnErrorResult.TERMINATE
                OnErrorResult.TERMINATE -> OnErrorResult.SKIP_SUBTREE
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "OnErrorResult entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testPathWalkOptionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.PathWalkOption

        fun nextPathWalkOption(option: PathWalkOption): PathWalkOption {
            return when (option) {
                PathWalkOption.BREADTH_FIRST -> PathWalkOption.FOLLOW_LINKS
                PathWalkOption.FOLLOW_LINKS -> PathWalkOption.BREADTH_FIRST
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "PathWalkOption entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testPathInvariantSeparatorsPathStringPropertyInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.invariantSeparatorsPathString

        fun invariantSeparators(path: Path): String {
            val normalized: String = path.invariantSeparatorsPathString
            return normalized
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.invariantSeparatorsPathString in kotlin.io.path should resolve as String: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testPathAbsoluteExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.absolute

        fun pathAbsolute(path: Path) {
            path.absolute()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let pathFQName = ["kotlin", "io", "path", "Path"].map { ctx.interner.intern($0) }
            let pathSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: pathFQName))
            let pathType = sema.types.make(.classType(ClassType(
                classSymbol: pathSymbol,
                args: [],
                nullability: .nonNull
            )))
            let absoluteFQName = ["kotlin", "io", "path", "absolute"].map { ctx.interner.intern($0) }
            let absoluteSymbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: absoluteFQName).first(where: { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.receiverType == pathType
                })
            )
            let absoluteSignature = try XCTUnwrap(sema.symbols.functionSignature(for: absoluteSymbol))
            XCTAssertEqual(absoluteSignature.parameterTypes, [])
            XCTAssertEqual(absoluteSignature.returnType, pathType)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.absolute extension function in kotlin.io.path should resolve as Path: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            let ast = try XCTUnwrap(ctx.ast)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "absolute"
            })
            XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, absoluteSymbol)
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], pathType)
        }
    }

    func testMemoryOrderInAtomicsPackageIsResolved() throws {
        let source = """
        import kotlin.concurrent.atomics.MemoryOrder

        fun main() {
            val order = MemoryOrder.SEQUENTIALLY_CONSISTENT
            println(order)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "MemoryOrder in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testTypeSystemLUBAndGLB() {
        let types = TypeSystem()

        let intNN = types.make(.primitive(.int, .nonNull))
        let intNullable = types.make(.primitive(.int, .nullable))
        let boolNN = types.make(.primitive(.boolean, .nonNull))

        XCTAssertEqual(types.lub([]), types.errorType)
        XCTAssertEqual(types.lub([intNN, intNN]), intNN)
        XCTAssertEqual(types.lub([intNN, intNullable]), types.nullableAnyType)

        XCTAssertEqual(types.glb([]), types.errorType)
        XCTAssertEqual(types.glb([intNN, intNN]), intNN)
        XCTAssertEqual(types.glb([intNN, types.nothingType]), types.nothingType)

        let glbMixed = types.glb([intNN, boolNN])
        XCTAssertEqual(types.kind(of: glbMixed), .intersection([intNN, boolNN]))

        XCTAssertEqual(types.kind(of: TypeID(rawValue: 9999)), .error)
    }

    func testTypeSystemAnyNonNullSubtypeCoversClassFunctionIntersectionAndDefaultCases() {
        let types = TypeSystem()

        let intNN = types.make(.primitive(.int, .nonNull))
        let intNullable = types.make(.primitive(.int, .nullable))

        let classNN = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 400),
            args: [],
            nullability: .nonNull
        )))
        let classNullable = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 400),
            args: [],
            nullability: .nullable
        )))

        let fnNN = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fnNullable = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nullable
        )))

        let intersectionAllNonNull = types.make(.intersection([intNN, classNN]))
        let intersectionWithNullable = types.make(.intersection([intNN, intNullable]))

        XCTAssertTrue(types.isSubtype(classNN, types.anyType))
        XCTAssertFalse(types.isSubtype(classNullable, types.anyType))
        XCTAssertTrue(types.isSubtype(fnNN, types.anyType))
        XCTAssertFalse(types.isSubtype(fnNullable, types.anyType))
        XCTAssertTrue(types.isSubtype(intersectionAllNonNull, types.anyType))
        // With corrected intersection subtype rules (P5-97): A & B <: C if ANY part <: C.
        // intersection([Int, Int?]) <: Any is true because Int <: Any.
        XCTAssertTrue(types.isSubtype(intersectionWithNullable, types.anyType))
        XCTAssertFalse(types.isSubtype(types.nullableAnyType, types.anyType))

        let fnWithReceiver = types.make(.functionType(FunctionType(
            receiver: intNN,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fnWithoutReceiver = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        XCTAssertFalse(types.isSubtype(fnWithReceiver, fnWithoutReceiver))
    }

    func testSemanticsBindingTableAndSymbolTableScopes() {
        let interner = StringInterner()
        let symbols = SymbolTable()

        let pkg = symbols.define(
            kind: .package,
            name: interner.intern("pkg"),
            fqName: [interner.intern("pkg")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let fn = symbols.define(
            kind: .function,
            name: interner.intern("run"),
            fqName: [interner.intern("pkg"), interner.intern("run")],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction, .suspendFunction]
        )

        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols.symbol(pkg)?.kind, .package)
        XCTAssertEqual(symbols.lookup(fqName: [interner.intern("pkg")]), pkg)

        let signature = FunctionSignature(parameterTypes: [TypeSystem().anyType], returnType: TypeSystem().unitType)
        symbols.setFunctionSignature(signature, for: fn)
        XCTAssertEqual(symbols.functionSignature(for: fn)?.parameterTypes.count, 1)

        let root = PackageScope(parent: nil, symbols: symbols)
        let fileScope = FileScope(parent: root, symbols: symbols)
        fileScope.insert(fn)
        XCTAssertEqual(fileScope.lookup(interner.intern("run")), [fn])
        XCTAssertTrue(root.lookup(interner.intern("run")).isEmpty)

        let bindings = BindingTable()
        let expr = ExprID(rawValue: 1)
        let decl = DeclID(rawValue: 2)
        bindings.bindExprType(expr, type: TypeSystem().anyType)
        bindings.bindIdentifier(expr, symbol: fn)
        bindings.bindCall(expr, binding: CallBinding(chosenCallee: fn, substitutedTypeArguments: [], parameterMapping: [0: 0]))
        bindings.bindCallableTarget(expr, target: .symbol(fn))
        bindings.bindCallableValueCall(
            expr,
            binding: CallableValueCallBinding(
                target: .localValue(fn),
                functionType: TypeSystem().anyType,
                parameterMapping: [0: 0]
            )
        )
        bindings.bindCallableTarget(expr, target: .localValue(fn))
        bindings.bindCaptureSymbols(expr, symbols: [fn, fn])
        bindings.bindDecl(decl, symbol: fn)
        bindings.bindCatchClause(expr, binding: CatchClauseBinding(parameterSymbol: fn, parameterType: TypeSystem().anyType))

        XCTAssertEqual(bindings.identifierSymbol(for: expr), fn)
        XCTAssertEqual(bindings.callBinding(for: expr)?.chosenCallee, fn)
        XCTAssertEqual(bindings.callableTarget(for: expr), .localValue(fn))
        XCTAssertEqual(bindings.callableValueCallBinding(for: expr)?.parameterMapping, [0: 0])
        XCTAssertEqual(bindings.catchClauseBinding(for: expr)?.parameterSymbol, fn)
        XCTAssertEqual(bindings.captureSymbols(for: expr), [fn])
        XCTAssertEqual(bindings.declSymbol(for: decl), fn)
        XCTAssertFalse(bindings.isSuperCallExpr(expr))
    }

    func testImportAliasDeclStoresAliasField() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 10)

        let noAlias = ImportDecl(range: range, path: [interner.intern("a"), interner.intern("B")], alias: nil)
        XCTAssertNil(noAlias.alias)

        let withAlias = ImportDecl(range: range, path: [interner.intern("a"), interner.intern("B")], alias: interner.intern("X"))
        XCTAssertEqual(withAlias.alias, interner.intern("X"))
    }

    func testConditionBranchStructCreation() {
        let analyzer = DataFlowAnalyzer()
        let sym = SymbolID(rawValue: 100)
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        let trueState = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true),
        ])
        let falseState = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [stringType], nullability: .nonNull, isStable: true),
        ])
        let branch = ConditionBranch(trueState: trueState, falseState: falseState)

        XCTAssertEqual(branch.trueState.variables[sym]?.possibleTypes, [intType])
        XCTAssertEqual(branch.falseState.variables[sym]?.possibleTypes, [stringType])

        let merged = analyzer.merge(branch.trueState, branch.falseState)
        XCTAssertEqual(merged.variables[sym]?.possibleTypes.count, 2)
        XCTAssertTrue(merged.variables[sym]?.possibleTypes.contains(intType) == true)
        XCTAssertTrue(merged.variables[sym]?.possibleTypes.contains(stringType) == true)
    }
}

final class CommandRunnerErrorPathTests: XCTestCase {
    func testRunReturnsStdoutOnSuccess() throws {
        let result = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: ["sh", "-c", "printf 'ok'"]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "ok")
    }

    func testRunThrowsNonZeroExitWithCapturedStderr() {
        XCTAssertThrowsError(
            try CommandRunner.run(
                executable: "/usr/bin/env",
                arguments: ["sh", "-c", "printf 'err' >&2; exit 7"]
            )
        ) { error in
            guard case let CommandRunnerError.nonZeroExit(result) = error else {
                XCTFail("Expected nonZeroExit, got \(error)")
                return
            }
            XCTAssertEqual(result.exitCode, 7)
            XCTAssertEqual(result.stderr, "err")
        }
    }

    func testRunThrowsLaunchFailedForMissingExecutable() {
        XCTAssertThrowsError(
            try CommandRunner.run(
                executable: "/definitely/missing/executable",
                arguments: []
            )
        ) { error in
            guard case let CommandRunnerError.launchFailed(message) = error else {
                XCTFail("Expected launchFailed, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Failed to launch"))
        }
    }
}
