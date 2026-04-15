@testable import CompilerCore
import Foundation
import XCTest

final class CoroutineSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testEmptyCoroutineContextIsRegisteredAsSyntheticObject() throws {
        let (sema, interner) = try makeSema()

        let coroutineContextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
        let coroutineContextSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: coroutineContextFQName),
            "Expected kotlin.coroutines.CoroutineContext to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(coroutineContextSymbol)?.kind, .interface)

        let emptyCoroutineContextFQName = ["kotlin", "coroutines", "EmptyCoroutineContext"].map { interner.intern($0) }
        let emptyCoroutineContextSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: emptyCoroutineContextFQName),
            "Expected kotlin.coroutines.EmptyCoroutineContext to be registered"
        )
        let emptyCoroutineContextInfo = try XCTUnwrap(sema.symbols.symbol(emptyCoroutineContextSymbol))
        XCTAssertEqual(emptyCoroutineContextInfo.kind, .object)
        XCTAssertTrue(emptyCoroutineContextInfo.flags.contains(.synthetic))

        let expectedEmptyCoroutineContextType = sema.types.make(.classType(ClassType(
            classSymbol: emptyCoroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(
            sema.symbols.propertyType(for: emptyCoroutineContextSymbol),
            expectedEmptyCoroutineContextType
        )
        XCTAssertEqual(
            sema.symbols.directSupertypes(for: emptyCoroutineContextSymbol),
            [coroutineContextSymbol]
        )
    }

    func testEmptyCoroutineContextResolvesThroughWithContext() throws {
        let source = """
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlinx.coroutines.withContext

        suspend fun probe() {
            withContext(EmptyCoroutineContext) { 42 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty)
        }
    }

    func testCoroutineSuspendedTopLevelValIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = [
            "kotlin",
            "coroutines",
            "intrinsics",
            "COROUTINE_SUSPENDED",
        ].map { interner.intern($0) }

        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED to be registered"
        )
        let semanticSymbol = try XCTUnwrap(sema.symbols.symbol(symbol))
        XCTAssertEqual(semanticSymbol.kind, .property)
        XCTAssertEqual(semanticSymbol.visibility, .public)
        XCTAssertTrue(semanticSymbol.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.propertyType(for: symbol), sema.types.nullableAnyType)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: symbol),
            "kk_coroutine_suspended"
        )
    }

    func testSuspendCoroutineUninterceptedOrReturnStubIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))
        XCTAssertEqual(info.kind, .function)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.inlineFunction))
        XCTAssertTrue(info.flags.contains(.suspendFunction))

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        XCTAssertTrue(signature.isSuspend)
        XCTAssertEqual(signature.typeParameterSymbols.count, 1)
        XCTAssertEqual(signature.parameterTypes.count, 1)

        let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
        let continuationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: continuationFQName))
        XCTAssertEqual(sema.types.nominalTypeParameterSymbols(for: continuationSymbol).count, 1)
        let typeParamSymbol = try XCTUnwrap(signature.typeParameterSymbols.first)
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

        XCTAssertEqual(signature.parameterTypes.first, expectedBlockType)
        XCTAssertEqual(signature.returnType, typeParamType)
    }

    func testSuspendCoroutineAndContinuationSignatures() throws {
        let (sema, interner) = try makeSema()

        let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
        let continuationSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: continuationFQName),
            "Expected kotlin.coroutines.Continuation to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(continuationSymbol)?.kind, .interface)

        let continuationTypeParams = sema.types.nominalTypeParameterSymbols(for: continuationSymbol)
        XCTAssertEqual(continuationTypeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: continuationSymbol), [.invariant])

        _ = try XCTUnwrap(sema.symbols.propertyType(for: continuationSymbol))

        let contextSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "Continuation", "context"].map { interner.intern($0) })
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: contextSymbol), "kk_coroutine_continuation_context")
        guard case let .classType(contextType) = sema.types.kind(of: try XCTUnwrap(sema.symbols.propertyType(for: contextSymbol))) else {
            return XCTFail("Expected continuation.context to be a class type")
        }
        XCTAssertEqual(
            contextType.classSymbol,
            try XCTUnwrap(sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }))
        )
        XCTAssertTrue(contextType.args.isEmpty)

        let resumeWithFQName = ["kotlin", "coroutines", "Continuation", "resumeWith"].map { interner.intern($0) }
        let resumeWithSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: resumeWithFQName))
        let resumeWithSignature = try XCTUnwrap(sema.symbols.functionSignature(for: resumeWithSymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: resumeWithSymbol), "kk_coroutine_continuation_resume_with")
        guard case let .classType(resumeWithReceiverType) = sema.types.kind(of: try XCTUnwrap(resumeWithSignature.receiverType)) else {
            return XCTFail("Expected resumeWith receiver to be Continuation<T>")
        }
        XCTAssertEqual(resumeWithReceiverType.classSymbol, continuationSymbol)
        XCTAssertEqual(resumeWithReceiverType.args.count, 1)
        XCTAssertEqual(resumeWithSignature.parameterTypes.count, 1)
        XCTAssertEqual(resumeWithSignature.returnType, sema.types.unitType)
        XCTAssertEqual(resumeWithSignature.classTypeParameterCount, 1)

        let resultSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: ["kotlin", "Result"].map { interner.intern($0) }))
        guard case let .classType(resumeWithParameterType) = sema.types.kind(of: resumeWithSignature.parameterTypes[0]) else {
            return XCTFail("Expected resumeWith parameter to be Result<T>")
        }
        XCTAssertEqual(resumeWithParameterType.classSymbol, resultSymbol)
        XCTAssertEqual(resumeWithParameterType.args.count, 1)

        let resumeFQName = ["kotlin", "coroutines", "resume"].map { interner.intern($0) }
        let resumeSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: resumeFQName))
        let resumeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: resumeSymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: resumeSymbol), "kk_coroutine_continuation_resume")
        guard case let .classType(resumeReceiverType) = sema.types.kind(of: try XCTUnwrap(resumeSignature.receiverType)) else {
            return XCTFail("Expected resume receiver to be Continuation<T>")
        }
        XCTAssertEqual(resumeReceiverType.classSymbol, continuationSymbol)
        XCTAssertEqual(resumeReceiverType.args.count, 1)
        let resumeParameterType = try XCTUnwrap(resumeSignature.parameterTypes.first)
        guard case let .typeParam(resumeTypeParam) = sema.types.kind(of: resumeParameterType) else {
            return XCTFail("Expected resume parameter to be the continuation type parameter, got \(sema.types.renderType(resumeParameterType))")
        }
        XCTAssertNotEqual(resumeTypeParam.symbol.rawValue, -1)
        XCTAssertEqual(resumeSignature.returnType, sema.types.unitType)
        XCTAssertEqual(resumeSignature.classTypeParameterCount, 1)

        let resumeWithExceptionFQName = ["kotlin", "coroutines", "resumeWithException"].map { interner.intern($0) }
        let resumeWithExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: resumeWithExceptionFQName))
        let resumeWithExceptionSignature = try XCTUnwrap(sema.symbols.functionSignature(for: resumeWithExceptionSymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: resumeWithExceptionSymbol), "kk_coroutine_continuation_resume_with_exception")
        guard case let .classType(resumeWithExceptionReceiverType) = sema.types.kind(of: try XCTUnwrap(resumeWithExceptionSignature.receiverType)) else {
            return XCTFail("Expected resumeWithException receiver to be Continuation<T>")
        }
        XCTAssertEqual(resumeWithExceptionReceiverType.classSymbol, continuationSymbol)
        XCTAssertEqual(resumeWithExceptionReceiverType.args.count, 1)
        XCTAssertEqual(resumeWithExceptionSignature.parameterTypes.count, 1)
        XCTAssertEqual(resumeWithExceptionSignature.returnType, sema.types.unitType)
        XCTAssertEqual(resumeWithExceptionSignature.classTypeParameterCount, 1)

        let suspendCoroutineFQName = ["kotlin", "coroutines", "suspendCoroutine"].map { interner.intern($0) }
        let suspendCoroutineSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: suspendCoroutineFQName))
        let suspendCoroutineSignature = try XCTUnwrap(sema.symbols.functionSignature(for: suspendCoroutineSymbol))
        XCTAssertTrue(sema.symbols.symbol(suspendCoroutineSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertTrue(sema.symbols.symbol(suspendCoroutineSymbol)?.flags.contains(.inlineFunction) == true)
        XCTAssertEqual(sema.symbols.externalLinkName(for: suspendCoroutineSymbol), "kk_suspend_coroutine")
        XCTAssertTrue(suspendCoroutineSignature.isSuspend)
        XCTAssertEqual(suspendCoroutineSignature.typeParameterSymbols.count, 1)
        XCTAssertEqual(suspendCoroutineSignature.returnType, sema.types.make(.typeParam(TypeParamType(
            symbol: suspendCoroutineSignature.typeParameterSymbols[0],
            nullability: .nonNull
        ))))
    }

    func testSuspendCoroutineIntrinsicCanBeShadowedByUserFunction() throws {
        let source = """
        fun suspendCoroutineUninterceptedOrReturn(block: (Any?) -> Any?): Any? = block(null)

        fun probe(): Any? {
            return suspendCoroutineUninterceptedOrReturn { value -> value }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(ctx.diagnostics.hasError)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "suspendCoroutineUninterceptedOrReturn"
            })

            XCTAssertNil(sema.bindings.stdlibSpecialCallKind(for: callExpr))
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let chosenInfo = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
            XCTAssertFalse(chosenInfo.flags.contains(.synthetic))
        }
    }

    func testSuspendCoroutineIntrinsicResolvesThroughImport() throws {
        let source = """
        import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

        suspend fun probe(): Any? {
            return suspendCoroutineUninterceptedOrReturn { cont ->
                cont
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let suspendCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "suspendCoroutineUninterceptedOrReturn"
            })
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: suspendCall)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), nil)
        }
    }

    func testSuspendCoroutineResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resume(42)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let suspendCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "suspendCoroutine"
            })
            let chosenSuspendCoroutine = try XCTUnwrap(sema.bindings.callBinding(for: suspendCall)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenSuspendCoroutine), "kk_suspend_coroutine")
        }
    }

    func testResumeWithExceptionResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resumeWithException(Exception())
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try XCTUnwrap(ctx.ast)

            _ = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "resumeWithException"
            })
        }
    }

    func testContinuationContextResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                val context = cont.context
                cont.resume(42)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
        }
    }

    func testResumeWithResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.*

        suspend fun probe(): Int {
            return suspendCoroutine<Int> { cont: Continuation<Int> ->
                cont.resumeWith(runCatching { 42 })
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
