@testable import CompilerCore
import XCTest

extension OverloadResolverTests {
    func testResolveCallPrefersNonNullReceiverExtensionOverNullable() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))
        let nullableStringType = types.make(.primitive(.string, .nullable))

        let nonNullExt = defineSymbol(
            kind: .function, name: "tag", suffix: "tagNonNull", symbols: symbols, interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: stringType,
                parameterTypes: [],
                returnType: intType
            ),
            for: nonNullExt
        )

        let nullableExt = defineSymbol(
            kind: .function, name: "tag", suffix: "tagNullable", symbols: symbols, interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nullableStringType,
                parameterTypes: [],
                returnType: intType
            ),
            for: nullableExt
        )

        let call = CallExpr(
            range: makeRange(start: 706, end: 715),
            calleeName: interner.intern("tag"),
            args: []
        )
        let resolved = resolver.resolveCall(
            candidates: [nullableExt, nonNullExt],
            call: call,
            expectedType: nil,
            implicitReceiverType: stringType,
            ctx: ctx
        )

        XCTAssertEqual(resolved.chosenCallee, nonNullExt)
        XCTAssertNil(resolved.diagnostic)
    }

    func testResolveCallExtensionFunctionWithParameters() {
        let (resolver, types, symbols, interner, ctx) = makeEnv()

        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.make(.primitive(.string, .nonNull))

        let ext = defineSymbol(kind: .function, name: "extWithParams", suffix: "extWithParams", symbols: symbols, interner: interner)
        let paramX = defineSymbol(kind: .valueParameter, name: "x", suffix: "extWithParams_x", symbols: symbols, interner: interner)
        let paramY = defineSymbol(kind: .valueParameter, name: "y", suffix: "extWithParams_y", symbols: symbols, interner: interner)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: stringType,
                parameterTypes: [intType, intType],
                returnType: intType,
                valueParameterSymbols: [paramX, paramY]
            ),
            for: ext
        )

        let call = CallExpr(
            range: makeRange(start: 706, end: 720),
            calleeName: interner.intern("extWithParams"),
            args: [CallArg(type: intType), CallArg(type: intType)]
        )
        let resolved = resolver.resolveCall(
            candidates: [ext],
            call: call,
            expectedType: nil,
            implicitReceiverType: stringType,
            ctx: ctx
        )
        XCTAssertEqual(resolved.chosenCallee, ext)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1])
    }
}
