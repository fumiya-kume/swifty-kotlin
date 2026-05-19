@testable import CompilerCore
import XCTest

final class JsPromiseExternalClassTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Promise external class surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testPromiseClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "Promise"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.Promise must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .class)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertTrue(info.flags.contains(.openType))
    }

    func testPromiseDeclaresCovariantTypeParameter() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "Promise"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let typeParams = sema.types.nominalTypeParameterSymbols(for: symbol)

        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: symbol), [.out])

        let typeParam = try XCTUnwrap(sema.symbols.symbol(typeParams[0]))
        XCTAssertEqual(typeParam.kind, .typeParameter)
        XCTAssertEqual(typeParam.name, interner.intern("T"))
    }

    func testPromiseThenOnFulfilledIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let promiseFQName = ["kotlin", "js", "Promise"].map { interner.intern($0) }
        let promiseSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: promiseFQName))
        let promiseTypeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: promiseSymbol).first)
        let promiseTypeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: promiseTypeParameter,
            nullability: .nonNull
        )))
        let promiseReceiverType = try XCTUnwrap(sema.symbols.propertyType(for: promiseSymbol))
        let thenFQName = promiseFQName + [interner.intern("then")]
        let then = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: thenFQName).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol),
                      signature.receiverType == promiseReceiverType,
                      signature.parameterTypes.count == 1,
                      signature.typeParameterSymbols.count == 1,
                      case let .functionType(onFulfilledType) = sema.types.kind(of: signature.parameterTypes[0]),
                      case let .classType(returnType) = sema.types.kind(of: signature.returnType)
                else {
                    return false
                }
                return onFulfilledType.params == [promiseTypeParameterType]
                    && onFulfilledType.returnType == sema.types.make(.typeParam(TypeParamType(
                        symbol: signature.typeParameterSymbols[0],
                        nullability: .nonNull
                    )))
                    && returnType.classSymbol == promiseSymbol
                    && returnType.args.count == 1
            },
            "Promise.then(onFulfilled) member must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(then))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: then))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.valueParameterIsVararg, [false])
        XCTAssertNil(sema.symbols.externalLinkName(for: then))
    }

    func testPromiseThenOnFulfilledOnRejectedIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let promiseFQName = ["kotlin", "js", "Promise"].map { interner.intern($0) }
        let promiseSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: promiseFQName))
        let promiseTypeParameter = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: promiseSymbol).first)
        let promiseTypeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: promiseTypeParameter,
            nullability: .nonNull
        )))
        let throwableSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "Throwable"].map { interner.intern($0) })
        )
        let throwableType = try XCTUnwrap(sema.symbols.propertyType(for: throwableSymbol))
        let promiseReceiverType = try XCTUnwrap(sema.symbols.propertyType(for: promiseSymbol))
        let thenFQName = promiseFQName + [interner.intern("then")]
        let then = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: thenFQName).first { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol),
                      signature.receiverType == promiseReceiverType,
                      signature.parameterTypes.count == 2,
                      signature.typeParameterSymbols.count == 1,
                      case let .functionType(onFulfilledType) = sema.types.kind(of: signature.parameterTypes[0]),
                      case let .functionType(onRejectedType) = sema.types.kind(of: signature.parameterTypes[1]),
                      case let .classType(returnType) = sema.types.kind(of: signature.returnType)
                else {
                    return false
                }
                let resultType = sema.types.make(.typeParam(TypeParamType(
                    symbol: signature.typeParameterSymbols[0],
                    nullability: .nonNull
                )))
                return onFulfilledType.params == [promiseTypeParameterType]
                    && onFulfilledType.returnType == resultType
                    && onRejectedType.params == [throwableType]
                    && onRejectedType.returnType == resultType
                    && returnType.classSymbol == promiseSymbol
                    && returnType.args.count == 1
            },
            "Promise.then(onFulfilled, onRejected) member must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(then))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: then))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, false])
        XCTAssertEqual(signature.valueParameterIsVararg, [false, false])
        XCTAssertNil(sema.symbols.externalLinkName(for: then))
    }
}
