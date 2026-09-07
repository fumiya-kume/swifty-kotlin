@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SemanticsAndUtilitiesRegressionTests {

    // MARK: - Path-aware expression search helpers

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    // MARK: - Consolidated Semantics and Utilities Regression tests
    @Test
    func testSemanticsAndUtilitiesRegression() throws {
        let sources: [String] = [
            // testAtomicStoreExpressionIsTypedAsUnit
            """
            package sample0

                    import kotlin.concurrent.atomics.AtomicInt

                    fun main() {
                        val ai = AtomicInt(1)
                        val x = ai.store(2)
                        val y: Unit = x
                    }

            """,
            // testAtomicMigrationAliasesResolveInAtomicsPackage
            """
            package sample1

                    @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

                    import kotlin.concurrent.atomics.AtomicInt
                    import kotlin.concurrent.atomics.AtomicLong

                    fun main() {
                        val intValue = AtomicInt(1)
                        val nextInt = intValue.incrementAndGet()
                        val intAgain = intValue.get()

                        val longValue = AtomicLong(3L)
                        val nextLong = longValue.incrementAndGet()
                        val longAgain = longValue.get()

                        println(nextInt + intAgain)
                        println(nextLong + longAgain)
                    }

            """,
            // testBuilderMemberChainWithSameNamePropertiesResolvesMemberFunctions
            """
            package sample2

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

            """,
            // testLegacyAtomicTypeAliasStillResolves
            """
            package sample3

                    import kotlin.concurrent.AtomicInt

                    fun main() {
                        val ai = AtomicInt(1)
                        println(ai.load())
                    }

            """,
            // testExperimentalAtomicOptInMarkerIsResolved
            """
            package sample4

                    @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

                    import kotlin.concurrent.atomics.ExperimentalAtomicApi

                    fun main() {
                        println("ok")
                    }

            """,
            // testAtomicReferenceInAtomicsPackageIsResolved
            """
            package sample5

                    @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

                    import kotlin.concurrent.atomics.ExperimentalAtomicApi
                    import kotlin.concurrent.atomics.AtomicReference

                    fun main() {
                        val ar = AtomicReference("hello")
                        println(ar.load())
                    }

            """,
            // testAtomicLongInConcurrentPackageIsResolved
            """
            package sample6

                    @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

                    import kotlin.concurrent.AtomicLong

                    fun main() {
                        val al = AtomicLong(42L)
                        println(al.load())
                    }

            """,
            // testAtomicIntArrayInConcurrentPackageIsResolved
            """
            package sample7

                    @file:OptIn(kotlin.ExperimentalStdlibApi::class)

                    import kotlin.concurrent.AtomicIntArray

                    fun main() {
                        val values = AtomicIntArray(2)
                        values.storeAt(0, 10)
                        val ok = values.compareAndSetAt(0, 10, 11)
                        println(if (ok) values.loadAt(0) else values.size)
                    }

            """,
            // testAtomicLongArrayInConcurrentPackageIsResolved
            """
            package sample8

                    import kotlin.concurrent.AtomicLongArray

                    fun main() {
                        val values = AtomicLongArray(2)
                        values.storeAt(0, 10L)
                        val ok = values.compareAndSetAt(0, 10L, 11L)
                        println(if (ok) values.loadAt(0) else values.size.toLong())
                    }

            """,
            // testExperimentalAtomicArraysInAtomicsPackageAreResolved
            """
            package sample9

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

            """,
            // testAtomicArrayIndexOperatorsResolveWithoutExplicitImport
            """
            package sample10

                    @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

                    import kotlin.concurrent.atomics.AtomicIntArray
                    import kotlin.concurrent.atomics.AtomicLongArray

                    fun main() {
                        val ints = AtomicIntArray(2)
                        ints[0] = 5
                        ints[1] = ints[0] + 1
                        val longs = AtomicLongArray(1)
                        longs[0] = 9L
                        println(ints[0] + ints[1] + longs[0])
                    }

            """,
            // testCopyActionContextInIOPathPackageSurfaceIsResolved
            """
            package sample11

                    import kotlin.io.path.CopyActionContext

                    class CopyContextHolder(val context: CopyActionContext?)

                    fun keepCopyContext(context: CopyActionContext): CopyActionContext {
                        return context
                    }

            """,
            // testAtomicNativePtrInAtomicsPackageSurfaceIsResolved
            """
            package sample12

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

            """,
            // testCopyActionResultInIOPathPackageSurfaceIsResolved
            """
            package sample17

                    import kotlin.io.path.CopyActionResult

                    fun nextCopyActionResult(result: CopyActionResult): CopyActionResult {
                        return when (result) {
                            CopyActionResult.CONTINUE -> CopyActionResult.SKIP_SUBTREE
                            CopyActionResult.SKIP_SUBTREE -> CopyActionResult.TERMINATE
                            CopyActionResult.TERMINATE -> CopyActionResult.CONTINUE
                        }
                    }

            """,
            // CLEANUP-STUB-116 removed fileAttributesView; keep this slot to preserve path indices.
            """
            package sample21

            fun cleanupStub116RemovedCase21() {}
            """,
            // CLEANUP-STUB-116 removed Path.useLines; keep this slot to preserve path indices.
            """
            package sample30

            fun cleanupStub116RemovedCase30() {}
            """,
            // CLEANUP-STUB-116 removed useDirectoryEntries; keep this slot to preserve path indices.
            """
            package sample32

            fun cleanupStub116RemovedCase32() {}
            """,
            // CLEANUP-STUB-116 removed generic readAttributes; keep this slot to preserve path indices.
            """
            package sample33

            fun cleanupStub116RemovedCase33() {}
            """,
            // CLEANUP-STUB-116 removed fileAttributesViewOrNull; keep this slot to preserve path indices.
            """
            package sample37

            fun cleanupStub116RemovedCase37() {}
            """,
            // testOnErrorResultInIOPathPackageSurfaceIsResolved
            """
            package sample55

                    import kotlin.io.path.OnErrorResult

                    fun nextOnErrorResult(result: OnErrorResult): OnErrorResult {
                        return when (result) {
                            OnErrorResult.SKIP_SUBTREE -> OnErrorResult.TERMINATE
                            OnErrorResult.TERMINATE -> OnErrorResult.SKIP_SUBTREE
                        }
                    }

            """,
            // testPathWalkOptionInIOPathPackageSurfaceIsResolved
            """
            package sample71

                    import kotlin.io.path.PathWalkOption

                    fun nextPathWalkOption(option: PathWalkOption): PathWalkOption {
                        return when (option) {
                            PathWalkOption.BREADTH_FIRST -> PathWalkOption.FOLLOW_LINKS
                            PathWalkOption.FOLLOW_LINKS -> PathWalkOption.BREADTH_FIRST
                        }
                    }

            """,
            // testMemoryOrderInAtomicsPackageIsResolved
            """
            package sample78

                    import kotlin.concurrent.atomics.MemoryOrder

                    fun main() {
                        val order = MemoryOrder.SEQUENTIALLY_CONSISTENT
                        println(order)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let interner = ctx.interner
            _ = (ast, sema, symbols, types, interner)

            // testAtomicStoreExpressionIsTypedAsUnit
            do {
                let samplePath = paths[0]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "Atomic.store() should be typed as Unit: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicMigrationAliasesResolveInAtomicsPackage
            do {
                let samplePath = paths[1]
                _ = samplePath
                #expect(
                    !(ctx.diagnostics.hasError),
                    "Atomic migration aliases should resolve from kotlin.concurrent.atomics imports: \(ctx.diagnostics.diagnostics.map(\.message))"
                )
            }

            // testBuilderMemberChainWithSameNamePropertiesResolvesMemberFunctions
            do {
                let samplePath = paths[2]
                _ = samplePath

                let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
                let helpers = TypeCheckHelpers()

                let builderSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("sample2"), interner.intern("Config"), interner.intern("Builder")]))
                let builderType = sema.types.make(.classType(ClassType(classSymbol: builderSymbol, args: [], nullability: .nonNull)))
                let portCandidates = helpers.collectMemberFunctionCandidates(
                    named: interner.intern("port"),
                    receiverType: builderType,
                    sema: sema,
                    interner: interner
                )
                #expect(portCandidates.contains { candidate in
                        sema.symbols.symbol(candidate)?.fqName == [interner.intern("sample2"), interner.intern("Config"), interner.intern("Builder"), interner.intern("port")]
                    }, "Expected Config.Builder.port to be visible among candidates")

                let hostCall = try #require(memberCallExprIDsInPath(named: "host", in: ast, path: samplePath, ctx: ctx, interner: interner).first)
                let portCall = try #require(memberCallExprIDsInPath(named: "port", in: ast, path: samplePath, ctx: ctx, interner: interner).first)
                let hostExprType = sema.bindings.exprTypes[hostCall]
                let portExprType = sema.bindings.exprTypes[portCall]

                if case let .memberCall(portReceiverExpr, _, _, _, _) = ast.arena.expr(portCall) {
                    let portReceiverType = sema.bindings.exprTypes[portReceiverExpr]
                    #expect(portReceiverType == builderType, "Expected host() result used as port() receiver to stay Config.Builder, got \(portReceiverType.map(sema.types.renderType) ?? "nil"); diagnostics: \(diagnostics)")
                } else {
                    Issue.record("Expected port call expression to be a memberCall")
                }

                #expect(sema.bindings.callBinding(for: hostCall)?.chosenCallee != nil, "Expected host() call to resolve")
                #expect(hostExprType == builderType, "Expected host() to return Config.Builder, got \(hostExprType.map(sema.types.renderType) ?? "nil"); diagnostics: \(diagnostics)")
                #expect(portExprType == builderType, "Expected port() to return Config.Builder, got \(portExprType.map(sema.types.renderType) ?? "nil"); diagnostics: \(diagnostics)")
                #expect(sema.bindings.callBinding(for: portCall)?.chosenCallee != nil, "Expected port() call to resolve; diagnostics: \(diagnostics)")
            }

            // testLegacyAtomicTypeAliasStillResolves
            do {
                let samplePath = paths[3]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "Legacy kotlin.concurrent.AtomicInt alias should still resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testExperimentalAtomicOptInMarkerIsResolved
            do {
                let samplePath = paths[4]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "ExperimentalAtomicApi marker should resolve under OptIn: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicReferenceInAtomicsPackageIsResolved
            do {
                let samplePath = paths[5]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "ExperimentalAtomicApi marker should resolve under OptIn: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicLongInConcurrentPackageIsResolved
            do {
                let samplePath = paths[6]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "AtomicLong in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicIntArrayInConcurrentPackageIsResolved
            do {
                let samplePath = paths[7]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "AtomicIntArray in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicLongArrayInConcurrentPackageIsResolved
            do {
                let samplePath = paths[8]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "AtomicLongArray in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testExperimentalAtomicArraysInAtomicsPackageAreResolved
            do {
                let samplePath = paths[9]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "Experimental atomic arrays in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicArrayIndexOperatorsResolveWithoutExplicitImport
            do {
                let samplePath = paths[10]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "Atomic-array get/set operators should resolve via bundled extensions: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testCopyActionContextInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[11]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "CopyActionContext in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicNativePtrInAtomicsPackageSurfaceIsResolved
            do {
                let samplePath = paths[12]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "AtomicNativePtr in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testCopyActionResultInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[13]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "CopyActionResult entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testOnErrorResultInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[19]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "OnErrorResult entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testPathWalkOptionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[20]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "PathWalkOption entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testMemoryOrderInAtomicsPackageIsResolved
            do {
                let samplePath = paths[21]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "MemoryOrder in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }
        }
    }
}

@Suite
struct CommandRunnerErrorPathTests {
    @Test
    func testRunReturnsStdoutOnSuccess() throws {
        let result = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: ["sh", "-c", "printf 'ok'"]
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "ok")
    }

    @Test
    func testRunThrowsNonZeroExitWithCapturedStderr() throws {
        do {
            _ = try CommandRunner.run(
                executable: "/usr/bin/env",
                arguments: ["sh", "-c", "printf 'err' >&2; exit 7"]
            )
            Issue.record("expected throw")
        } catch {
            guard case let CommandRunnerError.nonZeroExit(result) = error else {
                Issue.record("Expected nonZeroExit, got \(error)")
                return
            }
            #expect(result.exitCode == 7)
            #expect(result.stderr == "err")
        }
    }

    @Test
    func testRunThrowsLaunchFailedForMissingExecutable() throws {
        do {
            _ = try CommandRunner.run(
                executable: "/definitely/missing/executable",
                arguments: []
            )
            Issue.record("expected throw")
        } catch {
            guard case let CommandRunnerError.launchFailed(message) = error else {
                Issue.record("Expected launchFailed, got \(error)")
                return
            }
            #expect(message.contains("Failed to launch"))
        }
    }
}
