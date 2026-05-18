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

    func testAtomicIntArrayInConcurrentPackageIsResolved() throws {
        let source = """
        import kotlin.concurrent.AtomicIntArray

        fun main() {
            val values = AtomicIntArray(2)
            values.storeAt(0, 10)
            val ok = values.compareAndSetAt(0, 10, 11)
            println(if (ok) values.loadAt(0) else values.size)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "AtomicIntArray in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testAtomicLongArrayInConcurrentPackageIsResolved() throws {
        let source = """
        import kotlin.concurrent.AtomicLongArray

        fun main() {
            val values = AtomicLongArray(2)
            values.storeAt(0, 10L)
            val ok = values.compareAndSetAt(0, 10L, 11L)
            println(if (ok) values.loadAt(0) else values.size.toLong())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "AtomicLongArray in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
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
            val previous = atomic.getAndSet(loaded)
            atomic.compareAndSet(exchanged, loaded)
            val fetched = atomic.fetchAndUpdate { current -> current }
            return atomic.compareAndExchange(fetched, previous)
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

    func testPathCopyToOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.CopyOption
        import kotlin.io.path.Path
        import kotlin.io.path.copyTo

        fun copyPath(source: Path, target: Path, option: CopyOption): Path {
            val first = source.copyTo(target)
            val second = source.copyTo(target, option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.copyTo(target, options) extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let copyOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "CopyOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let copyOptionType = types.make(.classType(ClassType(classSymbol: copyOptionSymbol, args: [], nullability: .nonNull)))
            let copyToSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "copyTo"].map(interner.intern))
            let copyTo = try XCTUnwrap(copyToSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, copyOptionType]
                    && signature.returnType == pathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: copyTo), "kk_path_copyTo_options")

            let signature = try XCTUnwrap(symbols.functionSignature(for: copyTo))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, true])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "copyTo", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, copyTo)
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], pathType)
            }
        }
    }

    func testPathIsDirectoryOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.isDirectory

        fun directoryPath(path: Path, option: LinkOption): Boolean {
            val first = path.isDirectory()
            val second = path.isDirectory(option)
            return first && second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.isDirectory(options) extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let isDirectorySymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "isDirectory"].map(interner.intern))
            let isDirectory = try XCTUnwrap(isDirectorySymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == types.booleanType
            })
            XCTAssertEqual(symbols.externalLinkName(for: isDirectory), "kk_path_isDirectory")

            let signature = try XCTUnwrap(symbols.functionSignature(for: isDirectory))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [true])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "isDirectory", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, isDirectory)
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], types.booleanType)
            }
        }
    }

    func testPathListDirectoryEntriesGlobExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.collections.List
        import kotlin.io.path.Path
        import kotlin.io.path.listDirectoryEntries

        fun entries(path: Path): List<Path> {
            val first = path.listDirectoryEntries()
            val second = path.listDirectoryEntries("*.kt")
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.listDirectoryEntries(glob) extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let listSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "collections", "List"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let listOfPathType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(pathType)],
                nullability: .nonNull
            )))
            let listDirectoryEntriesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "listDirectoryEntries"].map(interner.intern))
            let listDirectoryEntries = try XCTUnwrap(listDirectoryEntriesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [types.stringType]
                    && signature.returnType == listOfPathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: listDirectoryEntries), "kk_path_listDirectoryEntries")

            let signature = try XCTUnwrap(symbols.functionSignature(for: listDirectoryEntries))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [true])
            XCTAssertEqual(signature.valueParameterIsVararg, [false])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "listDirectoryEntries", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, listDirectoryEntries)
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], listOfPathType)
            }
        }
    }

    func testPathBaseSubpathsTopLevelFactoryInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path

        fun makePath(): Path {
            return Path("src", "main", "App.kt")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path(base, subpaths) top-level factory in kotlin.io.path should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let pathFactorySymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            let pathFactory = try XCTUnwrap(pathFactorySymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes == [types.stringType, types.stringType]
                    && signature.returnType == pathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: pathFactory), "kk_path_get_base_subpaths")

            let signature = try XCTUnwrap(symbols.functionSignature(for: pathFactory))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, true])
            XCTAssertEqual(signature.valueParameterSymbols.count, 2)
            XCTAssertEqual(interner.resolve(try XCTUnwrap(symbols.symbol(signature.valueParameterSymbols[0])?.name)), "base")
            XCTAssertEqual(interner.resolve(try XCTUnwrap(symbols.symbol(signature.valueParameterSymbols[1])?.name)), "subpaths")

            let ast = try XCTUnwrap(ctx.ast)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return interner.resolve(calleeName) == "Path"
            })
            XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, pathFactory)
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], pathType)
        }
    }

    func testPathFileAttributesViewOrNullOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import java.nio.file.attribute.FileAttributeView
        import kotlin.io.path.Path
        import kotlin.io.path.fileAttributesViewOrNull

        fun <V : FileAttributeView> attributesView(path: Path, option: LinkOption): V? {
            val first: V? = path.fileAttributesViewOrNull<V>()
            val second: V? = path.fileAttributesViewOrNull<V>(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.fileAttributesViewOrNull<V>(options) extension function in kotlin.io.path should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let fileAttributeViewSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttributeView"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let fileAttributeViewType = types.make(.classType(ClassType(classSymbol: fileAttributeViewSymbol, args: [], nullability: .nonNull)))
            let fileAttributesViewOrNullSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "fileAttributesViewOrNull"].map(interner.intern))
            let fileAttributesViewOrNull = try XCTUnwrap(fileAttributesViewOrNullSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID),
                      let typeParameterSymbol = signature.typeParameterSymbols.first
                else {
                    return false
                }
                let returnType = types.makeNullable(types.make(.typeParam(TypeParamType(
                    symbol: typeParameterSymbol,
                    nullability: .nonNull
                ))))
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == returnType
            })
            XCTAssertEqual(symbols.externalLinkName(for: fileAttributesViewOrNull), "kk_path_fileAttributesViewOrNull")

            let signature = try XCTUnwrap(symbols.functionSignature(for: fileAttributesViewOrNull))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [true])
            XCTAssertEqual(signature.typeParameterSymbols.count, 1)
            XCTAssertEqual(signature.typeParameterUpperBoundsList, [[fileAttributeViewType]])
            XCTAssertEqual(
                symbols.typeParameterUpperBounds(for: try XCTUnwrap(signature.typeParameterSymbols.first)),
                [fileAttributeViewType]
            )

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "fileAttributesViewOrNull", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, fileAttributesViewOrNull)
                XCTAssertNotNil(sema.bindings.exprTypes[callExpr])
            }
        }
    }

    func testPathGetAttributeOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.getAttribute

        fun attribute(path: Path, option: LinkOption): Any {
            val first = path.getAttribute("size")
            val second = path.getAttribute("lastModifiedTime", option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.getAttribute(attribute, options) extension function in kotlin.io.path should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let getAttributeSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "getAttribute"].map(interner.intern))
            let getAttribute = try XCTUnwrap(getAttributeSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [types.stringType, linkOptionType]
                    && signature.returnType == types.anyType
            })
            XCTAssertEqual(symbols.externalLinkName(for: getAttribute), "kk_path_getAttribute")

            let signature = try XCTUnwrap(symbols.functionSignature(for: getAttribute))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, true])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "getAttribute", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, getAttribute)
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], types.anyType)
            }
        }
    }

    func testPathIsRegularFileOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.isRegularFile

        fun regularPath(path: Path, option: LinkOption): Boolean {
            val first = path.isRegularFile()
            val second = path.isRegularFile(option)
            return first && second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.isRegularFile(options) extension function in kotlin.io.path should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let isRegularFileSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "isRegularFile"].map(interner.intern))
            let isRegularFile = try XCTUnwrap(isRegularFileSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == types.booleanType
            })
            XCTAssertEqual(symbols.externalLinkName(for: isRegularFile), "kk_path_isRegularFile")

            let signature = try XCTUnwrap(symbols.functionSignature(for: isRegularFile))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [true])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "isRegularFile", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, isRegularFile)
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], types.booleanType)
            }
        }
    }

    func testPathAppendLinesIterableExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.appendLines
        import kotlin.text.Charsets

        fun appendPathLines(path: Path, lines: Iterable<CharSequence>): Path {
            val first = path.appendLines(lines)
            val second = path.appendLines(lines, Charsets.UTF_8)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.appendLines Iterable extension function in kotlin.io.path should resolve: \(diagnostics)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let interner = ctx.interner
            let pathTypeSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("io"), interner.intern("path"), interner.intern("Path")])
            )
            let charSequenceSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("CharSequence")])
            )
            let iterableSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Iterable")])
            )
            let charsetSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("text"), interner.intern("Charset")])
            )
            let pathType = sema.types.make(.classType(ClassType(classSymbol: pathTypeSymbol, args: [], nullability: .nonNull)))
            let charSequenceType = sema.types.make(.classType(ClassType(classSymbol: charSequenceSymbol, args: [], nullability: .nonNull)))
            let iterableType = sema.types.make(.classType(ClassType(classSymbol: iterableSymbol, args: [.invariant(charSequenceType)], nullability: .nonNull)))
            let charsetType = sema.types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))

            let appendLinesSymbols = sema.symbols.lookupAll(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("path"),
                interner.intern("appendLines"),
            ])
            let defaultSymbol = try XCTUnwrap(appendLinesSymbols.first { symbol in
                sema.symbols.functionSignature(for: symbol)?.parameterTypes == [iterableType]
            })
            let charsetOverloadSymbol = try XCTUnwrap(appendLinesSymbols.first { symbol in
                sema.symbols.functionSignature(for: symbol)?.parameterTypes == [iterableType, charsetType]
            })
            let defaultSignature = try XCTUnwrap(sema.symbols.functionSignature(for: defaultSymbol))
            XCTAssertEqual(defaultSignature.receiverType, pathType)
            XCTAssertEqual(defaultSignature.returnType, pathType)
            XCTAssertEqual(defaultSignature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(sema.symbols.externalLinkName(for: defaultSymbol), "kk_path_appendLines_iterable_default")

            let charsetSignature = try XCTUnwrap(sema.symbols.functionSignature(for: charsetOverloadSymbol))
            XCTAssertEqual(charsetSignature.receiverType, pathType)
            XCTAssertEqual(charsetSignature.returnType, pathType)
            XCTAssertEqual(charsetSignature.valueParameterHasDefaultValues, [false, false])
            XCTAssertEqual(sema.symbols.externalLinkName(for: charsetOverloadSymbol), "kk_path_appendLines_iterable")

            let appendLinesCalls = memberCallExprIDs(named: "appendLines", in: ast, interner: interner)
            XCTAssertEqual(appendLinesCalls.count, 2)
            let chosenCallees = appendLinesCalls.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }
            XCTAssertTrue(chosenCallees.contains(defaultSymbol))
            XCTAssertTrue(chosenCallees.contains(charsetOverloadSymbol))
            for call in appendLinesCalls {
                XCTAssertEqual(sema.bindings.exprTypes[call], pathType)
            }
        }
    }

    func testPathWriteLinesIterableExtensionFunctionInIOPathPackageSurfaceIsRegistered() throws {
        let source = """
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writeLines
        import kotlin.text.Charsets

        fun writePathLines(path: Path, lines: Iterable<CharSequence>, option: OpenOption) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.writeLines Iterable extension function in kotlin.io.path should register: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charSequenceSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "CharSequence"].map(interner.intern)))
            let iterableSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "collections", "Iterable"].map(interner.intern)))
            let charsetSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let openOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charSequenceType = types.make(.classType(ClassType(classSymbol: charSequenceSymbol, args: [], nullability: .nonNull)))
            let iterableType = types.make(.classType(ClassType(classSymbol: iterableSymbol, args: [.invariant(charSequenceType)], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let writeLinesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "writeLines"].map(interner.intern))
            let writeLines = try XCTUnwrap(writeLinesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [iterableType, charsetType, openOptionType]
                    && signature.returnType == pathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: writeLines), "kk_path_writeLines_iterable")

            let signature = try XCTUnwrap(symbols.functionSignature(for: writeLines))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, true, false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, false, true])
        }
    }

    func testPathWriteLinesSequenceExtensionFunctionInIOPathPackageSurfaceIsRegistered() throws {
        let source = """
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writeLines
        import kotlin.sequences.Sequence
        import kotlin.text.Charsets

        fun writePathLines(path: Path, lines: Sequence<CharSequence>, option: OpenOption) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.writeLines Sequence extension function in kotlin.io.path should register: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charSequenceSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "CharSequence"].map(interner.intern)))
            let sequenceSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "sequences", "Sequence"].map(interner.intern)))
            let charsetSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let openOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charSequenceType = types.make(.classType(ClassType(classSymbol: charSequenceSymbol, args: [], nullability: .nonNull)))
            let sequenceType = types.make(.classType(ClassType(classSymbol: sequenceSymbol, args: [.out(charSequenceType)], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let writeLinesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "writeLines"].map(interner.intern))
            let writeLines = try XCTUnwrap(writeLinesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [sequenceType, charsetType, openOptionType]
                    && signature.returnType == pathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: writeLines), "kk_path_writeLines_sequence")

            let signature = try XCTUnwrap(symbols.functionSignature(for: writeLines))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, true, false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, false, true])
        }
    }

    func testPathWriterOptionsExtensionFunctionInIOPathPackageSurfaceIsRegistered() throws {
        let source = """
        import java.io.BufferedWriter
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writer
        import kotlin.text.Charsets

        fun pathWriter(path: Path, option: OpenOption) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.writer(charset, options) extension function in kotlin.io.path should register: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charsetSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let openOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let bufferedWriterSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let bufferedWriterType = types.make(.classType(ClassType(classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull)))
            let writerSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "writer"].map(interner.intern))
            let writer = try XCTUnwrap(writerSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charsetType, openOptionType]
                    && signature.returnType == bufferedWriterType
            })
            XCTAssertEqual(symbols.externalLinkName(for: writer), "kk_path_writer")

            let signature = try XCTUnwrap(symbols.functionSignature(for: writer))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [true, false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, true])
        }
    }

    func testPathFileSizeExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.fileSize

        fun size(path: Path): Long {
            return path.fileSize()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.fileSize extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let fileSizeSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "fileSize"].map(interner.intern))
            let fileSize = try XCTUnwrap(fileSizeSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == types.longType
            })
            XCTAssertEqual(symbols.externalLinkName(for: fileSize), "kk_path_fileSize")

            let signature = try XCTUnwrap(symbols.functionSignature(for: fileSize))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
            XCTAssertEqual(signature.valueParameterIsVararg, [])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "fileSize", in: ast, interner: interner)

            XCTAssertEqual(callExprs.count, 1)
            XCTAssertEqual(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee, fileSize)
            XCTAssertEqual(sema.bindings.exprTypes[callExprs[0]], types.longType)
        }
    }

    func testPathRelativeToOrNullExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.relativeToOrNull

        fun relativePathOrNull(path: Path, base: Path): Path? {
            return path.relativeToOrNull(base)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.relativeToOrNull extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let nullablePathType = types.makeNullable(pathType)
            let relativeToOrNullSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "relativeToOrNull"].map(interner.intern))
            let relativeToOrNull = try XCTUnwrap(relativeToOrNullSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType]
                    && signature.returnType == nullablePathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: relativeToOrNull), "kk_path_relativeToOrNull")

            let signature = try XCTUnwrap(symbols.functionSignature(for: relativeToOrNull))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "relativeToOrNull", in: ast, interner: interner)

            XCTAssertEqual(callExprs.count, 1)
            XCTAssertEqual(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee, relativeToOrNull)
            XCTAssertEqual(sema.bindings.exprTypes[callExprs[0]], nullablePathType)
        }
    }

    func testPathSetPosixFilePermissionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.attribute.PosixFilePermission
        import kotlin.collections.Set
        import kotlin.io.path.Path
        import kotlin.io.path.setPosixFilePermissions

        fun setPermissions(path: Path, value: Set<PosixFilePermission>): Path {
            return path.setPosixFilePermissions(value)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.setPosixFilePermissions extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics)"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let setSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "collections", "Set"].map(interner.intern)))
            let posixFilePermissionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "PosixFilePermission"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let posixFilePermissionType = types.make(.classType(ClassType(classSymbol: posixFilePermissionSymbol, args: [], nullability: .nonNull)))
            let setOfPosixFilePermissionType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(posixFilePermissionType)],
                nullability: .nonNull
            )))
            let setPosixFilePermissionsSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "setPosixFilePermissions"].map(interner.intern))
            let setPosixFilePermissions = try XCTUnwrap(setPosixFilePermissionsSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [setOfPosixFilePermissionType]
                    && signature.returnType == pathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: setPosixFilePermissions), "kk_path_setPosixFilePermissions")

            let signature = try XCTUnwrap(symbols.functionSignature(for: setPosixFilePermissions))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "setPosixFilePermissions", in: ast, interner: interner)

            XCTAssertEqual(callExprs.count, 1)
            XCTAssertEqual(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee, setPosixFilePermissions)
            XCTAssertEqual(sema.bindings.exprTypes[callExprs[0]], pathType)
        }
    }

    func testPathGetPosixFilePermissionsOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import java.nio.file.attribute.PosixFilePermission
        import kotlin.collections.Set
        import kotlin.io.path.Path
        import kotlin.io.path.getPosixFilePermissions

        fun permissions(path: Path, option: LinkOption): Set<PosixFilePermission> {
            val first = path.getPosixFilePermissions()
            val second = path.getPosixFilePermissions(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.getPosixFilePermissions(options) extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let posixFilePermissionSymbol = try XCTUnwrap(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "PosixFilePermission"].map(interner.intern)))
            let setSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "collections", "Set"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let posixFilePermissionType = types.make(.classType(ClassType(classSymbol: posixFilePermissionSymbol, args: [], nullability: .nonNull)))
            let setOfPosixFilePermissionType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(posixFilePermissionType)],
                nullability: .nonNull
            )))
            let getPosixFilePermissionsSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "getPosixFilePermissions"].map(interner.intern))
            let getPosixFilePermissions = try XCTUnwrap(getPosixFilePermissionsSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == setOfPosixFilePermissionType
            })
            XCTAssertEqual(symbols.externalLinkName(for: getPosixFilePermissions), "kk_path_getPosixFilePermissions")

            let signature = try XCTUnwrap(symbols.functionSignature(for: getPosixFilePermissions))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [true])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "getPosixFilePermissions", in: ast, interner: interner)
            XCTAssertEqual(callExprs.count, 2)
            for callExpr in callExprs {
                XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, getPosixFilePermissions)
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], setOfPosixFilePermissionType)
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

    func testPathReadSymbolicLinkExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.readSymbolicLink

        fun readLinkTarget(path: Path): Path {
            return path.readSymbolicLink()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.readSymbolicLink extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let readSymbolicLinkSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "readSymbolicLink"].map(interner.intern))
            let readSymbolicLink = try XCTUnwrap(readSymbolicLinkSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == pathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: readSymbolicLink), "kk_path_readSymbolicLink")

            let signature = try XCTUnwrap(symbols.functionSignature(for: readSymbolicLink))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [])
            XCTAssertEqual(signature.valueParameterIsVararg, [])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "readSymbolicLink", in: ast, interner: interner)

            XCTAssertEqual(callExprs.count, 1)
            XCTAssertEqual(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee, readSymbolicLink)
            XCTAssertEqual(sema.bindings.exprTypes[callExprs[0]], pathType)
        }
    }

    func testPathRelativeToOrSelfExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.relativeToOrSelf

        fun relativePathOrSelf(path: Path, base: Path): Path {
            return path.relativeToOrSelf(base)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.relativeToOrSelf extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let relativeToOrSelfSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "relativeToOrSelf"].map(interner.intern))
            let relativeToOrSelf = try XCTUnwrap(relativeToOrSelfSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType]
                    && signature.returnType == pathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: relativeToOrSelf), "kk_path_relativeToOrSelf")

            let signature = try XCTUnwrap(symbols.functionSignature(for: relativeToOrSelf))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "relativeToOrSelf", in: ast, interner: interner)

            XCTAssertEqual(callExprs.count, 1)
            XCTAssertEqual(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee, relativeToOrSelf)
            XCTAssertEqual(sema.bindings.exprTypes[callExprs[0]], pathType)
        }
    }

    func testPathRelativeToExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.relativeTo

        fun relativePath(path: Path, base: Path): Path {
            return path.relativeTo(base)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.relativeTo extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try XCTUnwrap(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let relativeToSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "relativeTo"].map(interner.intern))
            let relativeTo = try XCTUnwrap(relativeToSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType]
                    && signature.returnType == pathType
            })
            XCTAssertEqual(symbols.externalLinkName(for: relativeTo), "kk_path_relativeTo")

            let signature = try XCTUnwrap(symbols.functionSignature(for: relativeTo))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
            XCTAssertEqual(signature.valueParameterIsVararg, [false])

            let ast = try XCTUnwrap(ctx.ast)
            let callExprs = memberCallExprIDs(named: "relativeTo", in: ast, interner: interner)

            XCTAssertEqual(callExprs.count, 1)
            XCTAssertEqual(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee, relativeTo)
            XCTAssertEqual(sema.bindings.exprTypes[callExprs[0]], pathType)
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

    func testPathInvariantSeparatorsPathPropertyInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.invariantSeparatorsPath

        fun invariantSeparators(path: Path): String {
            val normalized: String = path.invariantSeparatorsPath
            return normalized
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.invariantSeparatorsPath in kotlin.io.path should resolve as String: \(ctx.diagnostics.diagnostics.map(\.message))"
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

    func testPathAbsolutePathStringExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.absolutePathString

        fun pathAbsolutePathString(path: Path): String {
            return path.absolutePathString()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            let sema = try XCTUnwrap(ctx.sema)
            let astAbs = try XCTUnwrap(ctx.ast)
            let interner = ctx.interner
            let pathSymbolAbs = try XCTUnwrap(
                sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("io"),
                    interner.intern("path"),
                    interner.intern("Path"),
                ])
            )
            let pathTypeAbs = sema.types.make(.classType(ClassType(
                classSymbol: pathSymbolAbs,
                args: [],
                nullability: .nonNull
            )))
            let absolutePathStringSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("io"),
                    interner.intern("path"),
                    interner.intern("absolutePathString"),
                ])
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: absolutePathStringSymbol))
            XCTAssertEqual(signature.receiverType, pathTypeAbs)
            XCTAssertEqual(signature.parameterTypes, [])
            XCTAssertEqual(signature.returnType, sema.types.stringType)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.absolutePathString() in kotlin.io.path should resolve as String: \(diagnostics)"
            )

            let callExpr = try XCTUnwrap(memberCallExprIDs(named: "absolutePathString", in: astAbs, interner: interner).first)
            XCTAssertEqual(sema.bindings.callBinding(for: callExpr)?.chosenCallee, absolutePathStringSymbol)
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.stringType)
        }
    }

    func testPathAppendBytesExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.appendBytes

        fun appendPathBytes(path: Path, bytes: ByteArray) {
            path.appendBytes(bytes)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Path.appendBytes extension function in kotlin.io.path should resolve: \(diagnostics)"
            )

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            let interner = ctx.interner
            let pathTypeSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("io"), interner.intern("path"), interner.intern("Path")])
            )
            let byteArraySymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("ByteArray")])
            )
            let pathType = sema.types.make(.classType(ClassType(classSymbol: pathTypeSymbol, args: [], nullability: .nonNull)))
            let byteArrayType = sema.types.make(.classType(ClassType(classSymbol: byteArraySymbol, args: [], nullability: .nonNull)))
            let appendBytesSymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("io"), interner.intern("path"), interner.intern("appendBytes")]),
                "Expected kotlin.io.path.appendBytes synthetic extension function"
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: appendBytesSymbol))
            XCTAssertEqual(signature.receiverType, pathType)
            XCTAssertEqual(signature.parameterTypes, [byteArrayType])
            XCTAssertEqual(signature.returnType, sema.types.unitType)
            XCTAssertEqual(sema.symbols.externalLinkName(for: appendBytesSymbol), "kk_path_appendBytes")

            let appendBytesCall = try XCTUnwrap(memberCallExprIDs(named: "appendBytes", in: ast, interner: interner).first)
            XCTAssertEqual(sema.bindings.callBinding(for: appendBytesCall)?.chosenCallee, appendBytesSymbol)
            XCTAssertEqual(sema.bindings.exprTypes[appendBytesCall], sema.types.unitType)
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
