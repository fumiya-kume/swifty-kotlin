@testable import CompilerCore
import Foundation
import XCTest

final class ContinuationSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testContinuationAndCoroutineContextStubsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
        let continuationSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: continuationFQName),
            "Expected kotlin.coroutines.Continuation to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(continuationSymbol)?.kind, .interface)
        XCTAssertTrue(sema.symbols.symbol(continuationSymbol)?.flags.contains(.synthetic) == true)

        let continuationTypeParameterSymbols = sema.types.nominalTypeParameterSymbols(for: continuationSymbol)
        XCTAssertEqual(continuationTypeParameterSymbols.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: continuationSymbol), [.invariant])

        let continuationTParamSymbol = try XCTUnwrap(continuationTypeParameterSymbols.first)
        let continuationTType = sema.types.make(.typeParam(TypeParamType(
            symbol: continuationTParamSymbol,
            nullability: .nonNull
        )))
        let continuationType = sema.types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(continuationTType)],
            nullability: .nonNull
        )))

        let coroutineContextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
        let coroutineContextSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: coroutineContextFQName),
            "Expected kotlin.coroutines.CoroutineContext to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(coroutineContextSymbol)?.kind, .interface)
        XCTAssertTrue(sema.symbols.symbol(coroutineContextSymbol)?.flags.contains(.synthetic) == true)
        let coroutineContextType = sema.types.make(.classType(ClassType(
            classSymbol: coroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))

        let resultFQName = ["kotlin", "Result"].map { interner.intern($0) }
        let resultSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: resultFQName),
            "Expected kotlin.Result to be registered"
        )
        let resultOfContinuationTType = sema.types.make(.classType(ClassType(
            classSymbol: resultSymbol,
            args: [.out(continuationTType)],
            nullability: .nonNull
        )))

        let contextSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: continuationFQName + [interner.intern("context")]),
            "Expected Continuation.context to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(contextSymbol)?.kind, .property)
        XCTAssertEqual(sema.symbols.propertyType(for: contextSymbol), coroutineContextType)

        let resumeWithSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: continuationFQName + [interner.intern("resumeWith")]),
            "Expected Continuation.resumeWith to be registered"
        )
        let resumeWithSignature = try XCTUnwrap(sema.symbols.functionSignature(for: resumeWithSymbol))
        XCTAssertEqual(resumeWithSignature.receiverType, continuationType)
        XCTAssertEqual(resumeWithSignature.parameterTypes, [resultOfContinuationTType])
        XCTAssertEqual(resumeWithSignature.returnType, sema.types.unitType)
        XCTAssertEqual(resumeWithSignature.typeParameterSymbols, [continuationTParamSymbol])
        XCTAssertEqual(resumeWithSignature.classTypeParameterCount, 1)

        // Sanity-check the Result<T> shape used by the parameter type.
        XCTAssertEqual(
            resultOfContinuationTType,
            sema.types.make(.classType(ClassType(
                classSymbol: resultSymbol,
                args: [.out(continuationTType)],
                nullability: .nonNull
            )))
        )

        let interceptorFQName = ["kotlin", "coroutines", "ContinuationInterceptor"].map { interner.intern($0) }
        let interceptorSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: interceptorFQName),
            "Expected kotlin.coroutines.ContinuationInterceptor to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(interceptorSymbol)?.kind, .interface)
        let dispatcherFQName = ["kotlinx", "coroutines", "CoroutineDispatcher"].map { interner.intern($0) }
        let dispatcherSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: dispatcherFQName),
            "Expected kotlinx.coroutines.CoroutineDispatcher to be registered"
        )
        XCTAssertTrue(
            sema.symbols.directSupertypes(for: dispatcherSymbol).contains(interceptorSymbol),
            "CoroutineDispatcher should be a ContinuationInterceptor"
        )

        let interceptedFQName = ["kotlin", "coroutines", "intrinsics", "intercepted"].map { interner.intern($0) }
        let interceptedSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: interceptedFQName),
            "Expected kotlin.coroutines.intrinsics.intercepted to be registered"
        )
        let interceptedSignature = try XCTUnwrap(sema.symbols.functionSignature(for: interceptedSymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: interceptedSymbol), "kk_continuation_intercepted")
        XCTAssertEqual(interceptedSignature.receiverType, continuationType)
        XCTAssertEqual(interceptedSignature.returnType, continuationType)
        XCTAssertEqual(interceptedSignature.typeParameterSymbols, [continuationTParamSymbol])
        XCTAssertEqual(interceptedSignature.classTypeParameterCount, 1)

        let interceptContinuationFQName = ["kotlin", "coroutines", "ContinuationInterceptor", "interceptContinuation"].map { interner.intern($0) }
        let interceptContinuationSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: interceptContinuationFQName),
            "Expected kotlin.coroutines.ContinuationInterceptor.interceptContinuation to be registered"
        )
        let interceptContinuationSignature = try XCTUnwrap(sema.symbols.functionSignature(for: interceptContinuationSymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: interceptContinuationSymbol), "kk_continuation_interceptor_intercept_continuation")
        let interceptorType = sema.types.make(.classType(ClassType(
            classSymbol: interceptorSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(interceptContinuationSignature.receiverType, interceptorType)
        XCTAssertEqual(interceptContinuationSignature.parameterTypes, [continuationType])
        XCTAssertEqual(interceptContinuationSignature.returnType, continuationType)
        XCTAssertEqual(interceptContinuationSignature.typeParameterSymbols, [continuationTParamSymbol])
    }

    func testCreateCoroutineUninterceptedOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let createCoroutineFQName = ["kotlin", "coroutines", "intrinsics", "createCoroutineUnintercepted"].map { interner.intern($0) }
        let createCoroutineSymbols = sema.symbols.lookupAll(fqName: createCoroutineFQName)
        XCTAssertEqual(createCoroutineSymbols.count, 2)

        let signatures = createCoroutineSymbols.compactMap { sema.symbols.functionSignature(for: $0) }
        XCTAssertEqual(signatures.count, 2)
        XCTAssertTrue(signatures.allSatisfy { $0.receiverType != nil })
        XCTAssertTrue(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
        XCTAssertTrue(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))
    }

    func testCreateCoroutineOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let createCoroutineFQName = ["kotlin", "coroutines", "createCoroutine"].map { interner.intern($0) }
        let createCoroutineSymbols = sema.symbols.lookupAll(fqName: createCoroutineFQName)
        XCTAssertEqual(createCoroutineSymbols.count, 2)

        let signatures = createCoroutineSymbols.compactMap { sema.symbols.functionSignature(for: $0) }
        XCTAssertEqual(signatures.count, 2)
        XCTAssertTrue(createCoroutineSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        XCTAssertTrue(signatures.allSatisfy { $0.receiverType != nil })
        XCTAssertTrue(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
        XCTAssertTrue(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))
    }

    func testStartCoroutineOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let startCoroutineFQName = ["kotlin", "coroutines", "startCoroutine"].map { interner.intern($0) }
        let startCoroutineSymbols = sema.symbols.lookupAll(fqName: startCoroutineFQName)
        XCTAssertEqual(startCoroutineSymbols.count, 2)

        let signatures = startCoroutineSymbols.compactMap { sema.symbols.functionSignature(for: $0) }
        XCTAssertEqual(signatures.count, 2)
        XCTAssertTrue(startCoroutineSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        XCTAssertTrue(signatures.allSatisfy { $0.receiverType != nil })
        XCTAssertTrue(signatures.allSatisfy { $0.returnType == sema.types.unitType })
        XCTAssertTrue(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
        XCTAssertTrue(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))
    }

    func testContinuationInterceptedResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.intrinsics.intercepted

        fun probe(c: Continuation<Int>): Continuation<Int> {
            return c.intercepted()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "intercepted"
            })
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected intercepted() to resolve"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_continuation_intercepted"
            )
        }
    }

    func testStartCoroutineNoReceiverResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.startCoroutine

        fun probe(block: suspend () -> Int, completion: Continuation<Int>) {
            block.startCoroutine(completion)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "startCoroutine"
            })
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected startCoroutine() to resolve"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), nil)
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.unitType)
        }
    }

    func testCreateCoroutineNoReceiverResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.createCoroutine

        fun probe(block: suspend () -> Int, completion: Continuation<Int>): Continuation<Unit> {
            return block.createCoroutine(completion)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "createCoroutine"
            })
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected createCoroutine() to resolve"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), nil)
        }
    }

    func testStartCoroutineWithReceiverResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.startCoroutine

        fun probe(block: suspend String.() -> Int, completion: Continuation<Int>) {
            block.startCoroutine("swift", completion)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "startCoroutine"
            })
            let chosenCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected receiver startCoroutine() to resolve"
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), nil)
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.unitType)
        }
    }
}
