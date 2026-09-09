#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CoroutineSyntheticStubTests {

    // MARK: - Path-aware expression search helpers

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

    @Test
    func testCoroutineSyntheticStubs() throws {
        let sources: [String] = [
            // source 0
            """
            package sample0
            fun noop() {}
            """,
            // source 1
            """
            package sample1

                    import kotlin.coroutines.EmptyCoroutineContext
                    import kotlinx.coroutines.withContext

                    suspend fun probe() {
                        withContext(EmptyCoroutineContext) { 42 }
                    }

            """,
            // source 2
            """
            package sample2

                    import kotlin.coroutines.CoroutineContext
                    import kotlin.coroutines.coroutineContext

                    suspend fun probe(): CoroutineContext {
                        return coroutineContext
                    }

            """,
            // source 3
            """
            package sample3

                    fun suspendCoroutineUninterceptedOrReturn(block: (Any?) -> Any?): Any? = block(null)

                    fun probe(): Any? {
                        return suspendCoroutineUninterceptedOrReturn { value -> value }
                    }

            """,
            // source 4
            """
            package sample4

                    import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

                    suspend fun probe(): Any? {
                        return suspendCoroutineUninterceptedOrReturn { cont ->
                            cont
                        }
                    }

            """,
            // source 5
            """
            package sample5

                    import kotlin.coroutines.*

                    suspend fun probe(): Int {
                        return suspendCoroutine<Int> { cont: Continuation<Int> ->
                            cont.resume(42)
                        }
                    }

            """,
            // source 6
            """
            package sample6

                    import kotlin.coroutines.*

                    suspend fun probe(): Int {
                        return suspendCoroutine<Int> { cont: Continuation<Int> ->
                            cont.resumeWithException(Exception())
                        }
                    }

            """,
            // source 7
            """
            package sample7

                    import kotlin.coroutines.*

                    suspend fun probe(): Int {
                        return suspendCoroutine<Int> { cont: Continuation<Int> ->
                            val context = cont.context
                            cont.resume(42)
                        }
                    }

            """,
            // source 8
            """
            package sample8

                    import kotlin.coroutines.*

                    suspend fun probe(): Int {
                        return suspendCoroutine<Int> { cont: Continuation<Int> ->
                            cont.resumeWith(runCatching { 42 })
                        }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = (ast, sema, interner)

            // testEmptyCoroutineContextIsRegisteredAsSyntheticObject
            do {


                let coroutineContextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
                let coroutineContextSymbol = try #require(
                    sema.symbols.lookup(fqName: coroutineContextFQName),
                    "Expected kotlin.coroutines.CoroutineContext to be registered"
                )
                #expect(sema.symbols.symbol(coroutineContextSymbol)?.kind == .interface)

                let emptyCoroutineContextFQName = ["kotlin", "coroutines", "EmptyCoroutineContext"].map { interner.intern($0) }
                let emptyCoroutineContextSymbol = try #require(
                    sema.symbols.lookup(fqName: emptyCoroutineContextFQName),
                    "Expected kotlin.coroutines.EmptyCoroutineContext to be registered"
                )
                let emptyCoroutineContextInfo = try #require(sema.symbols.symbol(emptyCoroutineContextSymbol))
                #expect(emptyCoroutineContextInfo.kind == .object)
                #expect(emptyCoroutineContextInfo.flags.contains(.synthetic))

                let expectedEmptyCoroutineContextType = sema.types.make(.classType(ClassType(
                    classSymbol: emptyCoroutineContextSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                #expect(
                    sema.symbols.propertyType(for: emptyCoroutineContextSymbol) ==
                    expectedEmptyCoroutineContextType
                )
                #expect(
                    sema.symbols.directSupertypes(for: emptyCoroutineContextSymbol) ==
                    [coroutineContextSymbol]
                )
            }

            // testCoroutineSuspendedTopLevelValIsRegistered
            do {

                let fqName = [
                    "kotlin",
                    "coroutines",
                    "intrinsics",
                    "COROUTINE_SUSPENDED",
                ].map { interner.intern($0) }

                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED to be registered"
                )
                let semanticSymbol = try #require(sema.symbols.symbol(symbol))
                #expect(semanticSymbol.kind == .property)
                #expect(semanticSymbol.visibility == .public)
                #expect(semanticSymbol.flags.contains(.synthetic))
                #expect(sema.symbols.propertyType(for: symbol) == sema.types.nullableAnyType)
                #expect(
                    sema.symbols.externalLinkName(for: symbol) ==
                    "kk_coroutine_suspended"
                )
            }

            // testCoroutineContextTopLevelPropertyIsRegistered
            do {

                let fqName = ["kotlin", "coroutines", "coroutineContext"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "Expected kotlin.coroutines.coroutineContext to be registered"
                )
                let info = try #require(sema.symbols.symbol(symbol))
                #expect(info.kind == .property)
                #expect(info.visibility == .public)
                #expect(info.flags.contains(.synthetic))
                #expect(sema.symbols.externalLinkName(for: symbol) == "kk_coroutine_current_context")

                let coroutineContextSymbol = try #require(
                    sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) })
                )
                guard case let .classType(propertyType) = sema.types.kind(of: try #require(sema.symbols.propertyType(for: symbol))) else {
                    Issue.record("Expected coroutineContext property type to be CoroutineContext"); return
                }
                #expect(propertyType.classSymbol == coroutineContextSymbol)
                #expect(propertyType.args.isEmpty)
            }

            // testSuspendCoroutineUninterceptedOrReturnStubIsRegistered
            do {

                let fqName = ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                let info = try #require(sema.symbols.symbol(symbol))
                #expect(info.kind == .function)
                #expect(info.flags.contains(.synthetic))
                #expect(info.flags.contains(.inlineFunction))
                #expect(info.flags.contains(.suspendFunction))

                let signature = try #require(sema.symbols.functionSignature(for: symbol))
                #expect(signature.isSuspend)
                #expect(signature.typeParameterSymbols.count == 1)
                #expect(signature.parameterTypes.count == 1)

                let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
                let continuationSymbol = try #require(sema.symbols.lookup(fqName: continuationFQName))
                #expect(sema.types.nominalTypeParameterSymbols(for: continuationSymbol).count == 1)
                let typeParamSymbol = try #require(signature.typeParameterSymbols.first)
                let typeParamType = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbol,
                    nullability: .nonNull
                )))
                let continuationType = sema.types.make(.classType(ClassType(
                    classSymbol: continuationSymbol,
                    args: [.invariant(typeParamType)],
                    nullability: .nonNull
                )))
                let expectedBlockType = sema.types.make(.functionType(FunctionType(
                    params: [continuationType],
                    returnType: sema.types.nullableAnyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))

                #expect(signature.parameterTypes.first == expectedBlockType)
                #expect(signature.returnType == typeParamType)
            }

            // testSuspendCoroutineAndContinuationSignatures
            do {


                let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
                let continuationSymbol = try #require(
                    sema.symbols.lookup(fqName: continuationFQName),
                    "Expected kotlin.coroutines.Continuation to be registered"
                )
                #expect(sema.symbols.symbol(continuationSymbol)?.kind == .interface)

                let continuationTypeParams = sema.types.nominalTypeParameterSymbols(for: continuationSymbol)
                #expect(continuationTypeParams.count == 1)
                #expect(sema.types.nominalTypeParameterVariances(for: continuationSymbol) == [.invariant])

                _ = try #require(sema.symbols.propertyType(for: continuationSymbol))

                let contextSymbol = try #require(
                    sema.symbols.lookup(fqName: ["kotlin", "coroutines", "Continuation", "context"].map { interner.intern($0) })
                )
                #expect(sema.symbols.externalLinkName(for: contextSymbol) == "kk_coroutine_continuation_context")
                guard case let .classType(contextType) = sema.types.kind(of: try #require(sema.symbols.propertyType(for: contextSymbol))) else {
                    Issue.record("Expected continuation.context to be a class type"); return
                }
                #expect(
                    try contextType.classSymbol ==
                    #require(sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }))
                )
                #expect(contextType.args.isEmpty)

                let resumeWithFQName = ["kotlin", "coroutines", "Continuation", "resumeWith"].map { interner.intern($0) }
                let resumeWithSymbol = try #require(sema.symbols.lookup(fqName: resumeWithFQName))
                let resumeWithSignature = try #require(sema.symbols.functionSignature(for: resumeWithSymbol))
                #expect(sema.symbols.externalLinkName(for: resumeWithSymbol) == "kk_coroutine_continuation_resume_with")
                guard case let .classType(resumeWithReceiverType) = sema.types.kind(of: try #require(resumeWithSignature.receiverType)) else {
                    Issue.record("Expected resumeWith receiver to be Continuation<T>"); return
                }
                #expect(resumeWithReceiverType.classSymbol == continuationSymbol)
                #expect(resumeWithReceiverType.args.count == 1)
                #expect(resumeWithSignature.parameterTypes.count == 1)
                #expect(resumeWithSignature.returnType == sema.types.unitType)
                #expect(resumeWithSignature.classTypeParameterCount == 1)

                let resultSymbol = try #require(sema.symbols.lookup(fqName: ["kotlin", "Result"].map { interner.intern($0) }))
                guard case let .classType(resumeWithParameterType) = sema.types.kind(of: resumeWithSignature.parameterTypes[0]) else {
                    Issue.record("Expected resumeWith parameter to be Result<T>"); return
                }
                #expect(resumeWithParameterType.classSymbol == resultSymbol)
                #expect(resumeWithParameterType.args.count == 1)

                let resumeFQName = ["kotlin", "coroutines", "resume"].map { interner.intern($0) }
                let resumeSymbol = try #require(sema.symbols.lookup(fqName: resumeFQName))
                let resumeSignature = try #require(sema.symbols.functionSignature(for: resumeSymbol))
                #expect(sema.symbols.externalLinkName(for: resumeSymbol) == "kk_coroutine_continuation_resume")
                guard case let .classType(resumeReceiverType) = sema.types.kind(of: try #require(resumeSignature.receiverType)) else {
                    Issue.record("Expected resume receiver to be Continuation<T>"); return
                }
                #expect(resumeReceiverType.classSymbol == continuationSymbol)
                #expect(resumeReceiverType.args.count == 1)
                let resumeParameterType = try #require(resumeSignature.parameterTypes.first)
                guard case let .typeParam(resumeTypeParam) = sema.types.kind(of: resumeParameterType) else {
                    Issue.record("Expected resume parameter to be the continuation type parameter, got \(sema.types.renderType(resumeParameterType))"); return
                }
                #expect(resumeTypeParam.symbol.rawValue != -1)
                #expect(resumeSignature.returnType == sema.types.unitType)
                #expect(resumeSignature.classTypeParameterCount == 1)

                let resumeWithExceptionFQName = ["kotlin", "coroutines", "resumeWithException"].map { interner.intern($0) }
                let resumeWithExceptionSymbol = try #require(sema.symbols.lookup(fqName: resumeWithExceptionFQName))
                let resumeWithExceptionSignature = try #require(sema.symbols.functionSignature(for: resumeWithExceptionSymbol))
                #expect(sema.symbols.externalLinkName(for: resumeWithExceptionSymbol) == "kk_coroutine_continuation_resume_with_exception")
                guard case let .classType(resumeWithExceptionReceiverType) = sema.types.kind(of: try #require(resumeWithExceptionSignature.receiverType)) else {
                    Issue.record("Expected resumeWithException receiver to be Continuation<T>"); return
                }
                #expect(resumeWithExceptionReceiverType.classSymbol == continuationSymbol)
                #expect(resumeWithExceptionReceiverType.args.count == 1)
                #expect(resumeWithExceptionSignature.parameterTypes.count == 1)
                #expect(resumeWithExceptionSignature.returnType == sema.types.unitType)
                #expect(resumeWithExceptionSignature.classTypeParameterCount == 1)

                let suspendCoroutineFQName = ["kotlin", "coroutines", "suspendCoroutine"].map { interner.intern($0) }
                let suspendCoroutineSymbol = try #require(sema.symbols.lookup(fqName: suspendCoroutineFQName))
                let suspendCoroutineSignature = try #require(sema.symbols.functionSignature(for: suspendCoroutineSymbol))
                #expect(sema.symbols.symbol(suspendCoroutineSymbol)?.flags.contains(.synthetic) == true)
                #expect(sema.symbols.symbol(suspendCoroutineSymbol)?.flags.contains(.inlineFunction) == true)
                #expect(sema.symbols.externalLinkName(for: suspendCoroutineSymbol) == "kk_suspend_coroutine")
                #expect(suspendCoroutineSignature.isSuspend)
                #expect(suspendCoroutineSignature.typeParameterSymbols.count == 1)
                #expect(suspendCoroutineSignature.returnType == sema.types.make(.typeParam(TypeParamType(
                    symbol: suspendCoroutineSignature.typeParameterSymbols[0],
                    nullability: .nonNull
                ))))
            }

            // testCancellationExceptionClassAndConstructorsAreRegistered
            do {


                let cancellationFQName = ["kotlin", "coroutines", "cancellation", "CancellationException"].map {
                    interner.intern($0)
                }
                let cancellationSymbol = try #require(
                    sema.symbols.lookup(fqName: cancellationFQName),
                    "Expected kotlin.coroutines.cancellation.CancellationException to be registered"
                )
                #expect(sema.symbols.symbol(cancellationSymbol)?.kind == .class)
                #expect(sema.symbols.symbol(cancellationSymbol)?.flags.contains(.synthetic) == false)

                let illegalStateExceptionSymbol = try #require(
                    sema.symbols.lookup(fqName: ["kotlin", "IllegalStateException"].map { interner.intern($0) })
                )
                #expect(sema.symbols.directSupertypes(for: cancellationSymbol).contains(illegalStateExceptionSymbol))

                let throwableSymbol = try #require(
                    sema.symbols.lookup(fqName: ["kotlin", "Throwable"].map { interner.intern($0) })
                )

                let ctorFQName = cancellationFQName + [interner.intern("<init>")]
                let constructors = sema.symbols.lookupAll(fqName: ctorFQName)
                #expect(constructors.count == 4)

                let nullableThrowableType = sema.types.make(.classType(ClassType(
                    classSymbol: throwableSymbol,
                    args: [],
                    nullability: .nullable
                )))
                let nullableStringType = sema.types.makeNullable(sema.types.stringType)
                let expectedParameterTypes: Set<[TypeID]> = [
                    [],
                    [nullableStringType],
                    [nullableThrowableType],
                    [nullableStringType, nullableThrowableType],
                ]
                let actualParameterTypes = Set(constructors.compactMap { sema.symbols.functionSignature(for: $0)?.parameterTypes })
                #expect(actualParameterTypes == expectedParameterTypes)

                let expectedLinks: [[TypeID]: String] = [
                    []: "__kk_cancellation_exception_new",
                    [nullableStringType]: "__kk_cancellation_exception_new_message",
                    [nullableThrowableType]: "__kk_cancellation_exception_new_cause",
                    [nullableStringType, nullableThrowableType]: "__kk_cancellation_exception_new_message_cause",
                ]
                for (parameterTypes, expectedLink) in expectedLinks {
                    let constructor = try #require(constructors.first { symbol in
                        sema.symbols.functionSignature(for: symbol)?.parameterTypes == parameterTypes
                    })
                    #expect(sema.symbols.externalLinkName(for: constructor) == expectedLink)
                }
            }

            // testCancellationExceptionCauseConstructorIsRegistered
            do {


                let cancellationFQName = ["kotlin", "coroutines", "cancellation", "CancellationException"].map {
                    interner.intern($0)
                }
                let cancellationSymbol = try #require(sema.symbols.lookup(fqName: cancellationFQName))
                let throwableSymbol = try #require(
                    sema.symbols.lookup(fqName: ["kotlin", "Throwable"].map { interner.intern($0) })
                )
                let nullableThrowableType = sema.types.make(.classType(ClassType(
                    classSymbol: throwableSymbol,
                    args: [],
                    nullability: .nullable
                )))

                let constructors = sema.symbols.lookupAll(fqName: cancellationFQName + [interner.intern("<init>")])
                let causeConstructor = try #require(constructors.first { symbol in
                    sema.symbols.functionSignature(for: symbol)?.parameterTypes == [nullableThrowableType]
                })
                let causeSignature = try #require(sema.symbols.functionSignature(for: causeConstructor))
                #expect(causeSignature.returnType == sema.symbols.propertyType(for: cancellationSymbol))
                #expect(sema.symbols.externalLinkName(for: causeConstructor) == "__kk_cancellation_exception_new_cause")
            }

            // testEmptyCoroutineContextResolvesThroughWithContext
            do {
                let samplePath = paths[1]
                _ = samplePath
                #expect(ctx.diagnostics.diagnostics.isEmpty)
            }

            // testCoroutineContextTopLevelPropertyResolvesInSuspendSource
            do {
                let samplePath = paths[2]
                _ = samplePath
                #expect(ctx.diagnostics.diagnostics.isEmpty)
            }

            // testSuspendCoroutineIntrinsicCanBeShadowedByUserFunction
            do {
                let samplePath = paths[3]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError))
                let callExpr = try #require(firstExprIDInPath(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return interner.resolve(calleeName) == "suspendCoroutineUninterceptedOrReturn"
                })

                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let chosenInfo = try #require(sema.symbols.symbol(chosenCallee))
                #expect(!(chosenInfo.flags.contains(.synthetic)))
            }

            // testSuspendCoroutineIntrinsicResolvesThroughImport
            do {
                let samplePath = paths[4]
                _ = samplePath
                #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
                let suspendCall = try #require(firstExprIDInPath(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return interner.resolve(calleeName) == "suspendCoroutineUninterceptedOrReturn"
                })
                let chosenCallee = try #require(sema.bindings.callBinding(for: suspendCall)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            }

            // testSuspendCoroutineResolvesInSource
            do {
                let samplePath = paths[5]
                _ = samplePath
                #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
                let suspendCall = try #require(firstExprIDInPath(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return interner.resolve(calleeName) == "suspendCoroutine"
                })
                let chosenSuspendCoroutine = try #require(sema.bindings.callBinding(for: suspendCall)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: chosenSuspendCoroutine) == "kk_suspend_coroutine")
            }

            // testResumeWithExceptionResolvesInSource
            do {
                let samplePath = paths[6]
                _ = samplePath
                #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
                _ = try #require(firstExprIDInPath(in: ast, path: samplePath, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                        return false
                    }
                    return interner.resolve(calleeName) == "resumeWithException"
                })
            }

            // testContinuationContextResolvesInSource
            do {
                let samplePath = paths[7]
                _ = samplePath
                #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
            }

            // testResumeWithResolvesInSource
            do {
                let samplePath = paths[8]
                _ = samplePath
                #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
            }
        }
    }

    @Test
    func testSourceBackedCancellationExceptionConstructorsResolveInCalls() throws {
        let source = """
        package sample

        import kotlin.coroutines.cancellation.CancellationException

        fun noArg(): CancellationException = CancellationException()
        fun message(message: String?): CancellationException = CancellationException(message)
        fun cause(cause: Throwable?): CancellationException = CancellationException(cause)
        fun messageAndCause(message: String?, cause: Throwable?): CancellationException =
            CancellationException(message, cause)
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
