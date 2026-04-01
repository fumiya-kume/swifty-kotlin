@testable import CompilerCore
import Foundation
import XCTest

final class ThreadLocalSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testThreadLocalConstructorAndGetOrSetSignatures() throws {
        let (sema, interner) = try makeSema()

        let threadLocalFQName = ["java", "lang", "ThreadLocal"].map { interner.intern($0) }
        let threadLocalSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: threadLocalFQName),
            "Expected java.lang.ThreadLocal to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(threadLocalSymbol)?.kind, .class)

        let classTypeParameterSymbols = sema.types.nominalTypeParameterSymbols(for: threadLocalSymbol)
        XCTAssertEqual(classTypeParameterSymbols.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: threadLocalSymbol), [.invariant])

        let classTParamSymbol = try XCTUnwrap(classTypeParameterSymbols.first)
        let classTType = sema.types.make(.typeParam(TypeParamType(
            symbol: classTParamSymbol,
            nullability: .nonNull
        )))
        let threadLocalClassType = sema.types.make(.classType(ClassType(
            classSymbol: threadLocalSymbol,
            args: [.invariant(classTType)],
            nullability: .nonNull
        )))

        let initSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: threadLocalFQName + [interner.intern("<init>")]),
            "Expected java.lang.ThreadLocal.<init> to be registered"
        )
        let initSignature = try XCTUnwrap(sema.symbols.functionSignature(for: initSymbol))
        XCTAssertEqual(initSignature.receiverType, nil)
        XCTAssertEqual(initSignature.parameterTypes, [])
        XCTAssertEqual(initSignature.returnType, threadLocalClassType)
        XCTAssertEqual(initSignature.typeParameterSymbols, [classTParamSymbol])
        XCTAssertEqual(initSignature.classTypeParameterCount, 1)
        XCTAssertEqual(sema.symbols.externalLinkName(for: initSymbol), "kk_thread_local_new")

        let getOrSetFQName = ["kotlin", "concurrent", "getOrSet"].map { interner.intern($0) }
        let getOrSetSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: getOrSetFQName),
            "Expected kotlin.concurrent.getOrSet to be registered"
        )
        let getOrSetSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getOrSetSymbol))
        XCTAssertTrue(sema.symbols.symbol(getOrSetSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertTrue(sema.symbols.symbol(getOrSetSymbol)?.flags.contains(.inlineFunction) == true)
        XCTAssertEqual(sema.symbols.externalLinkName(for: getOrSetSymbol), "kk_thread_local_getOrSet")

        let functionTParamSymbol = try XCTUnwrap(getOrSetSignature.typeParameterSymbols.first)
        XCTAssertNotEqual(functionTParamSymbol, classTParamSymbol)

        let functionTType = sema.types.make(.typeParam(TypeParamType(
            symbol: functionTParamSymbol,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: threadLocalSymbol,
            args: [.invariant(functionTType)],
            nullability: .nonNull
        )))
        let defaultFunctionType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: functionTType
        )))

        XCTAssertEqual(getOrSetSignature.receiverType, receiverType)
        XCTAssertEqual(getOrSetSignature.parameterTypes, [defaultFunctionType])
        XCTAssertEqual(getOrSetSignature.returnType, functionTType)
        XCTAssertEqual(getOrSetSignature.typeParameterSymbols, [functionTParamSymbol])
        XCTAssertEqual(getOrSetSignature.classTypeParameterCount, 0)
    }

    func testThreadLocalGetOrSetResolvesInSource() throws {
        let source = """
        import java.lang.ThreadLocal
        import kotlin.concurrent.getOrSet

        fun probe(): Int {
            val tl = ThreadLocal<Int>()
            return tl.getOrSet { 42 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let constructorCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "ThreadLocal"
            })
            let constructorCallee = try XCTUnwrap(
                sema.bindings.callBinding(for: constructorCall)?.chosenCallee
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: constructorCallee),
                "kk_thread_local_new"
            )

            let getOrSetCall = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "getOrSet"
            })
            let chosenGetOrSet = try XCTUnwrap(
                sema.bindings.callBinding(for: getOrSetCall)?.chosenCallee
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenGetOrSet),
                "kk_thread_local_getOrSet"
            )
        }
    }
}
