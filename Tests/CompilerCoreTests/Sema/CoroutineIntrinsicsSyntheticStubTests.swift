@testable import CompilerCore
import Foundation
import XCTest

final class CoroutineIntrinsicsSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testCoroutineIntrinsicsStubsAreRegisteredWithExpectedShapes() throws {
        let (sema, interner) = try makeSema()

        let continuationFQName = ["kotlin", "coroutines", "Continuation"].map { interner.intern($0) }
        let continuationSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: continuationFQName),
            "Expected kotlin.coroutines.Continuation to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(continuationSymbol)?.kind, .interface)
        let continuationTypeParams = sema.types.nominalTypeParameterSymbols(for: continuationSymbol)
        XCTAssertEqual(continuationTypeParams.count, 1)

        let coroutineSuspendedFQName = ["kotlin", "coroutines", "intrinsics", "COROUTINE_SUSPENDED"].map { interner.intern($0) }
        let coroutineSuspendedSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: coroutineSuspendedFQName),
            "Expected COROUTINE_SUSPENDED to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(coroutineSuspendedSymbol)?.kind, .property)
        XCTAssertEqual(sema.symbols.externalLinkName(for: coroutineSuspendedSymbol), "kk_coroutine_suspended")
        XCTAssertEqual(sema.symbols.propertyType(for: coroutineSuspendedSymbol), sema.types.nullableAnyType)

        let suspendIntrinsicFQName = ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"].map { interner.intern($0) }
        let suspendIntrinsicSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: suspendIntrinsicFQName),
            "Expected suspendCoroutineUninterceptedOrReturn to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(suspendIntrinsicSymbol)?.kind, .function)
        XCTAssertEqual(sema.symbols.externalLinkName(for: suspendIntrinsicSymbol), nil)

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: suspendIntrinsicSymbol))
        XCTAssertEqual(signature.isSuspend, true)
        XCTAssertEqual(signature.parameterTypes.count, 1)
        XCTAssertEqual(signature.typeParameterSymbols.count, 1)

        let functionTypeParam = try XCTUnwrap(signature.typeParameterSymbols.first)
        let functionTypeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: functionTypeParam,
            nullability: .nonNull
        )))
        let functionContinuationType = sema.types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(functionTypeParamType)],
            nullability: .nonNull
        )))
        let blockType = sema.types.make(.functionType(FunctionType(
            params: [functionContinuationType],
            returnType: sema.types.nullableAnyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        XCTAssertEqual(signature.parameterTypes, [blockType])
        XCTAssertEqual(signature.returnType, functionTypeParamType)
    }

    func testSuspendCoroutineIntrinsicsResolveInSource() throws {
        let source = """
        import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
        import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

        suspend fun probe(): Int {
            return suspendCoroutineUninterceptedOrReturn { continuation ->
                COROUTINE_SUSPENDED
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

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

            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .suspendCoroutineUninterceptedOrReturn)
            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                nil
            )
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
        }
    }

    func testStartCoroutineUninterceptedOrReturnOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "coroutines", "intrinsics", "startCoroutineUninterceptedOrReturn"].map {
            interner.intern($0)
        }
        let symbols = sema.symbols.lookupAll(fqName: fqName)
        XCTAssertEqual(symbols.count, 2)

        let signatures = symbols.compactMap { sema.symbols.functionSignature(for: $0) }
        XCTAssertEqual(signatures.count, 2)
        XCTAssertTrue(symbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil })
        XCTAssertTrue(symbols.allSatisfy { sema.symbols.symbol($0)?.flags.contains(.inlineFunction) == true })
        XCTAssertTrue(signatures.allSatisfy { $0.receiverType != nil })
        XCTAssertTrue(signatures.allSatisfy { $0.returnType == sema.types.nullableAnyType })
        XCTAssertTrue(signatures.contains(where: { $0.parameterTypes.count == 1 && $0.typeParameterSymbols.count == 1 }))
        XCTAssertTrue(signatures.contains(where: { $0.parameterTypes.count == 2 && $0.typeParameterSymbols.count == 2 }))
    }

    func testStartCoroutineUninterceptedOrReturnResolvesInSource() throws {
        let source = """
        import kotlin.coroutines.Continuation
        import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn

        fun probe(block: suspend () -> Int, completion: Continuation<Int>): Any? {
            return block.startCoroutineUninterceptedOrReturn(completion)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, memberName, _, _, _) = expr else { return false }
                return ctx.interner.resolve(memberName) == "startCoroutineUninterceptedOrReturn"
            })

            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(sema.symbols.externalLinkName(for: chosenCallee), nil)
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.nullableAnyType)
        }
    }
}
