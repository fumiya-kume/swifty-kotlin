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
        XCTAssertTrue(sema.types.nominalTypeParameterVariances(for: continuationSymbol).isEmpty)

        let continuationTParamSymbol = try XCTUnwrap(continuationTypeParams.first)
        let continuationTType = sema.types.make(.typeParam(TypeParamType(
            symbol: continuationTParamSymbol,
            nullability: .nonNull
        )))
        let continuationType = sema.types.make(.classType(ClassType(
            classSymbol: continuationSymbol,
            args: [.invariant(continuationTType)],
            nullability: .nonNull
        )))

        let contextSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "coroutines", "Continuation", "context"].map { interner.intern($0) })
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: contextSymbol), "kk_coroutine_continuation_context")

        let contextType = sema.types.make(.classType(ClassType(
            classSymbol: try XCTUnwrap(sema.symbols.lookup(fqName: ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) })),
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: contextSymbol), contextType)

        let resumeWithFQName = ["kotlin", "coroutines", "Continuation", "resumeWith"].map { interner.intern($0) }
        let resumeWithSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: resumeWithFQName))
        let resumeWithSignature = try XCTUnwrap(sema.symbols.functionSignature(for: resumeWithSymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: resumeWithSymbol), "kk_coroutine_continuation_resume_with")
        XCTAssertEqual(resumeWithSignature.receiverType, continuationType)
        XCTAssertEqual(resumeWithSignature.parameterTypes.count, 1)
        XCTAssertEqual(resumeWithSignature.returnType, sema.types.unitType)
        XCTAssertEqual(resumeWithSignature.classTypeParameterCount, 1)

        let resultSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: ["kotlin", "Result"].map { interner.intern($0) }))
        let resultTParamSymbol = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: resultSymbol).first)
        let resultTType = sema.types.make(.typeParam(TypeParamType(
            symbol: resultTParamSymbol,
            nullability: .nonNull
        )))
        let resultType = sema.types.make(.classType(ClassType(
            classSymbol: resultSymbol,
            args: [.out(resultTType)],
            nullability: .nonNull
        )))
        XCTAssertEqual(resumeWithSignature.parameterTypes[0], resultType)

        let resumeFQName = ["kotlin", "coroutines", "resume"].map { interner.intern($0) }
        let resumeSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: resumeFQName))
        let resumeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: resumeSymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: resumeSymbol), "kk_coroutine_continuation_resume")
        XCTAssertEqual(resumeSignature.receiverType, continuationType)
        XCTAssertEqual(resumeSignature.parameterTypes, [continuationTType])
        XCTAssertEqual(resumeSignature.returnType, sema.types.unitType)
        XCTAssertEqual(resumeSignature.classTypeParameterCount, 1)

        let resumeWithExceptionFQName = ["kotlin", "coroutines", "resumeWithException"].map { interner.intern($0) }
        let resumeWithExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: resumeWithExceptionFQName))
        let resumeWithExceptionSignature = try XCTUnwrap(sema.symbols.functionSignature(for: resumeWithExceptionSymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: resumeWithExceptionSymbol), "kk_coroutine_continuation_resume_with_exception")
        XCTAssertEqual(resumeWithExceptionSignature.receiverType, continuationType)
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
        let suspendCoroutineTParamSymbol = suspendCoroutineSignature.typeParameterSymbols[0]
        let suspendCoroutineTType = sema.types.make(.typeParam(TypeParamType(
            symbol: suspendCoroutineTParamSymbol,
            nullability: .nonNull
        )))
        XCTAssertEqual(suspendCoroutineSignature.returnType, suspendCoroutineTType)

            let blockType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.make(.classType(ClassType(
                    classSymbol: continuationSymbol,
                    args: [.invariant(suspendCoroutineTType)],
                    nullability: .nonNull
                )))],
            returnType: sema.types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        XCTAssertEqual(suspendCoroutineSignature.parameterTypes, [blockType])
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
