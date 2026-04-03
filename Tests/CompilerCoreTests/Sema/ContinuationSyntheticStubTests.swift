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

    func testContinuationSymbolsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
        let continuationSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: continuationFQName),
            "Expected kotlin.coroutines.Continuation to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(continuationSymbol)?.kind, .interface)

        let continuationTypeParameters = sema.types.nominalTypeParameterSymbols(for: continuationSymbol)
        XCTAssertEqual(continuationTypeParameters.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: continuationSymbol), [.invariant])

        _ = try XCTUnwrap(continuationTypeParameters.first)
        guard case let .classType(continuationType) = sema.types.kind(of: try XCTUnwrap(sema.symbols.propertyType(for: continuationSymbol))) else {
            return XCTFail("Expected Continuation to have a class type")
        }
        XCTAssertEqual(continuationType.classSymbol, continuationSymbol)
        XCTAssertEqual(continuationType.args.count, 1)

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
        guard case let .classType(interceptedReceiverType) = sema.types.kind(of: try XCTUnwrap(interceptedSignature.receiverType)) else {
            return XCTFail("Expected intercepted receiver to be Continuation<T>")
        }
        XCTAssertEqual(interceptedReceiverType.classSymbol, continuationSymbol)
        XCTAssertEqual(interceptedReceiverType.args.count, 1)
        guard case let .classType(interceptedReturnType) = sema.types.kind(of: interceptedSignature.returnType) else {
            return XCTFail("Expected intercepted return type to be Continuation<T>")
        }
        XCTAssertEqual(interceptedReturnType.classSymbol, continuationSymbol)
        XCTAssertEqual(interceptedReturnType.args.count, 1)
        XCTAssertEqual(interceptedSignature.typeParameterSymbols.count, 1)
        XCTAssertEqual(interceptedSignature.classTypeParameterCount, 1)

        let interceptContinuationFQName = ["kotlin", "coroutines", "ContinuationInterceptor", "interceptContinuation"].map { interner.intern($0) }
        let interceptContinuationSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: interceptContinuationFQName),
            "Expected kotlin.coroutines.ContinuationInterceptor.interceptContinuation to be registered"
        )
        let interceptContinuationSignature = try XCTUnwrap(sema.symbols.functionSignature(for: interceptContinuationSymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: interceptContinuationSymbol), "kk_continuation_interceptor_intercept_continuation")
        guard case let .classType(interceptContinuationReceiverType) = sema.types.kind(of: try XCTUnwrap(interceptContinuationSignature.receiverType)) else {
            return XCTFail("Expected interceptContinuation receiver to be ContinuationInterceptor")
        }
        XCTAssertEqual(interceptContinuationReceiverType.classSymbol, interceptorSymbol)
        XCTAssertTrue(interceptContinuationReceiverType.args.isEmpty)
        guard case let .classType(interceptContinuationParamType) = sema.types.kind(of: try XCTUnwrap(interceptContinuationSignature.parameterTypes.first)) else {
            return XCTFail("Expected interceptContinuation parameter to be Continuation<T>")
        }
        XCTAssertEqual(interceptContinuationParamType.classSymbol, continuationSymbol)
        XCTAssertEqual(interceptContinuationParamType.args.count, 1)
        guard case let .classType(interceptContinuationReturnType) = sema.types.kind(of: interceptContinuationSignature.returnType) else {
            return XCTFail("Expected interceptContinuation return type to be Continuation<T>")
        }
        XCTAssertEqual(interceptContinuationReturnType.classSymbol, continuationSymbol)
        XCTAssertEqual(interceptContinuationReturnType.args.count, 1)
        XCTAssertEqual(interceptContinuationSignature.typeParameterSymbols.count, 1)
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
}
