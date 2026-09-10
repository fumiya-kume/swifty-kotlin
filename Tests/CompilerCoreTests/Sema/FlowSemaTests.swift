#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct FlowSemaTests {

    // MARK: - Shared Sema contexts

    private static let cleanSources: [String] = [
        """
        package sample0
        fun main() {
            runBlocking {
                flow {
                    emit(1)
                    emit(2)
                }.map { it * 2 }
                    .collect { println(it) }
            }
        }
        """,
        """
        package sample1
        fun main() {
            runBlocking {
                println(1)
            }
        }
        """,
        """
        package sample2
        fun twice(x: Int): Int = x * 2

        fun main() {
            runBlocking {
                flow {
                    emit(1)
                    emit(2)
                }.map(::twice)
                    .collect { println(it) }
            }
        }
        """,
        """
        package sample3
        fun main() {
            runBlocking {
                val stream = flow {
                    emit(1)
                    emit(2)
                }.map { it * 2 }
                stream.collect { println(it) }
                stream.collect { println(it) }
            }
        }
        """,
        """
        package sample4
        fun flow(block: () -> Int): Int = block()

        fun main() {
            val x: Int = flow { 1 }
            println(x)
        }
        """,
        """
        package sample5
        fun main() {
            runBlocking {
                val f = flow { emit(1) }
                f.collect { println(it) }
            }
        }
        """,
        """
        package sample6
        fun main() {
            runBlocking {
                val mapped = flow { emit(1) }.map { it * 2 }
                mapped.collect { println(it) }
            }
        }
        """,
        """
        package sample7
        fun main() {
            runBlocking {
                val f = flow { emit(1); emit(2) }.filter { it > 1 }
                f.collect { println(it) }
            }
        }
        """,
        """
        package sample8
        fun main() {
            runBlocking {
                val taken = flow { emit(1); emit(2); emit(3) }.take(2)
                taken.collect { println(it) }
            }
        }
        """,
        """
        package sample9
        import kotlinx.coroutines.*
        import kotlinx.coroutines.flow.*

        fun main() {
            runBlocking {
                flowOf(1, 2, 3).collect { println(it) }
                emptyFlow<Int>().collect { println(it) }
                listOf(1, 2, 3).asFlow().collect { println(it) }
            }
        }
        """,
        """
        package sample10
        fun failOnTwo(value: Int): Int {
            if (value == 2) throw RuntimeException("boom")
            return value
        }

        fun failAlways(value: Int): Int {
            throw RuntimeException("retry")
        }

        fun main() {
            runBlocking {
                flow {
                    emit(1)
                    emit(2)
                }.map(::failOnTwo)
                    .catch { _: Throwable -> println(-1) }
                    .collect { value: Int -> println(value) }

                val retried = flow {
                    emit(10)
                    emit(20)
                }.map(::failOnTwo)
                    .retry(1)
                println(retried.toList())

                val retriedWhen = flow {
                    emit(7)
                }.map(::failAlways)
                    .retryWhen { _: Throwable, attempt: Long -> attempt < 1L }
                println(retriedWhen.toList())
            }
        }
        """,
        """
        package sample11
        fun main() {
            runBlocking {
                flow {
                    val emit = { x: Int -> x + 1 }
                    val y: Int = emit(1)
                    println(y)
                }.collect { println(it) }
            }
        }
        """,
        """
        package sample12
        fun main() {
            runBlocking {
                val source = flow { emit(1); emit(2) }
                source.map { it + 1 }
                    .filter { it > 1 }
                    .take(1)
                    .toList()
                source.first()
                source.fold(0) { acc, value -> acc + value }
                source.reduce { acc, value -> acc + value }
            }
        }
        """
    ]

    private static let errorSources: [String] = [
        """
        package sample0
        fun main() {
            val value: Any = 1
            value.map { it }
        }
        """
    ]

    private static nonisolated(unsafe) var _cleanCtx: CompilationContext?
    private static nonisolated(unsafe) var _errorCtx: CompilationContext?

    private func cleanCtx() throws -> CompilationContext {
        if let cached = Self._cleanCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.cleanSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._cleanCtx = ctx
        return ctx
    }

    private func errorCtx() throws -> CompilationContext {
        if let cached = Self._errorCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.errorSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._errorCtx = ctx
        return ctx
    }

    @Test func testFlowBuilderAndChainTypeChecks() throws {
        let ctx = try cleanCtx()

        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func testRunBlockingLambdaAvoidsTypeConstraintFailure() throws {
        let ctx = try cleanCtx()

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func testFlowMapCallableReferenceDoesNotOverConstrain() throws {
        let ctx = try cleanCtx()

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test func testFlowStoredInLocalVariableKeepsFlowReceiverTyping() throws {
        let ctx = try cleanCtx()

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test func testFlowFallbackDoesNotApplyToArbitraryAnyReceiver() throws {
        let ctx = try errorCtx()

        let hasExpectedDiagnostic = ctx.diagnostics.diagnostics.contains(where: {
            ["KSWIFTK-SEMA-0002", "KSWIFTK-SEMA-0024"].contains($0.code)
        })
        #expect(
            hasExpectedDiagnostic,
            "Expected unresolved member diagnostic for non-flow Any receiver. Got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    @Test func testUserDefinedFlowFunctionShadowsBuiltinFlowFallback() throws {
        let ctx = try cleanCtx()

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    // MARK: - TYPE-113: Flow<T> type preservation tests

    @Test func testFlowBuilderExprTypeIsFlowClassType() throws {
        let ctx = try cleanCtx()
        let sema = try #require(ctx.sema)

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

        // Find the flow expression and verify its type is Flow<...> (a classType),
        // not Any.
        let flowExprs = sema.bindings.flowExprIDs
        #expect(!flowExprs.isEmpty, "Should have at least one flow expression")

        for flowExpr in flowExprs {
            guard let exprType = sema.bindings.exprType(for: flowExpr) else { continue }
            // The expression type should NOT be anyType or nullableAnyType
            #expect(exprType != sema.types.anyType,
                "Flow expression type should not be erased to Any")
            #expect(exprType != sema.types.nullableAnyType,
                "Flow expression type should not be erased to Any?")
            // It should be a classType (Flow<...>)
            if case .classType(let classType) = sema.types.kind(of: exprType) {
                let symbol = sema.symbols.symbol(classType.classSymbol)
                let name = symbol.map { ctx.interner.resolve($0.name) }
                #expect(name == "Flow", "Flow expression should have Flow class type")
                #expect(!classType.args.isEmpty, "Flow type should have type arguments")
            }
        }
    }

    @Test func testFlowMapResultTypeIsFlowClassType() throws {
        let ctx = try cleanCtx()
        let sema = try #require(ctx.sema)

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

        // The map result should also be a flow expression with a non-Any type
        let flowExprs = sema.bindings.flowExprIDs
        #expect(flowExprs.count >= 2,
            "Should have flow builder + map as flow expressions")

        for flowExpr in flowExprs {
            guard let exprType = sema.bindings.exprType(for: flowExpr) else { continue }
            #expect(exprType != sema.types.anyType,
                "Flow chain result should not be erased to Any")
        }
    }

    @Test func testFlowFilterPreservesElementType() throws {
        let ctx = try cleanCtx()

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

        let sema = try #require(ctx.sema)
        let flowExprs = sema.bindings.flowExprIDs
        #expect(flowExprs.count >= 2,
            "Should have flow builder + filter as flow expressions")
        // At least one flow expression (the filter result) should track element type
        let exprsWithElementType = flowExprs.filter { sema.bindings.flowElementType(forExpr: $0) != nil }
        #expect(!exprsWithElementType.isEmpty,
            "At least one flow expression should track element type after filter")
    }

    @Test func testFlowTakeResultTypeIsFlowClassType() throws {
        let ctx = try cleanCtx()
        let sema = try #require(ctx.sema)

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)

        let flowExprs = sema.bindings.flowExprIDs
        for flowExpr in flowExprs {
            guard let exprType = sema.bindings.exprType(for: flowExpr) else { continue }
            #expect(exprType != sema.types.anyType,
                "Flow.take() result should not be erased to Any")
        }
    }

    @Test func testAdditionalFlowBuildersTypeCheck() throws {
        let ctx = try cleanCtx()

        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func testBundledFlowOperatorsWinOverIntrinsicFallback() throws {
        let ctx = try cleanCtx()
        let sema = try #require(ctx.sema)
        let migratedOperators: Set = ["map", "filter", "take", "toList", "first", "fold", "reduce"]

        let chosenCallees = sema.bindings.callBindings.values.compactMap(\.chosenCallee).filter { callee in
            guard let symbol = sema.symbols.symbol(callee) else { return false }
            let fqName = symbol.fqName.map(ctx.interner.resolve).joined(separator: ".")
            return migratedOperators.contains(ctx.interner.resolve(symbol.name))
                && fqName.hasPrefix("kotlinx.coroutines.flow.")
        }
        let chosenNames = Set(chosenCallees.compactMap { callee in
            sema.symbols.symbol(callee).map { ctx.interner.resolve($0.name) }
        })
        #expect(migratedOperators.isSubset(of: chosenNames),
            "Expected every migrated Flow operator to be bound to bundled Kotlin")
        for callee in chosenCallees {
            #expect(sema.symbols.isSourceBackedSymbol(callee))
            #expect(CallLowerer.isSourceBackedLinkName(sema.symbols.externalLinkName(for: callee)))
        }
    }

    @Test func testFlowErrorHandlingMembersTypeCheck() throws {
        let ctx = try cleanCtx()

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0003", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func testUserDefinedEmitInsideFlowBuilderShadowsBuiltinEmitFallback() throws {
        let ctx = try cleanCtx()

        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test func testChannelFlowAndCallbackFlowTypeCheckWithProducerScope() throws {
        var result: CompilationContext?
        try withTemporaryFiles(contents: [
            """
            package flow_builders
            import kotlinx.coroutines.*
            import kotlinx.coroutines.flow.*

            fun main() {
                runBlocking {
                    channelFlow<Int> { send(1) }.collect { println(it) }
                    callbackFlow<Int> { trySend(1); close() }.collect { println(it) }
                }
            }
            """
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }

        let ctx = try #require(result)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }
}
#endif
