import XCTest
@testable import CompilerCore

final class OverloadResolverTests: XCTestCase {
    func testResolveCallReturnsNoViableDiagnosticAfterAllCandidateFilters() {
        let setup = makeSemaContext()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))
        let call = CallExpr(
            range: makeRange(start: 10, end: 20),
            calleeName: interner.intern("foo"),
            args: [CallArg(type: intType)]
        )

        var candidates: [SymbolID] = [SymbolID(rawValue: 999)]

        let notCallable = defineSymbol(
            kind: .property,
            name: "foo",
            suffix: "property",
            symbols: symbols,
            interner: interner
        )
        candidates.append(notCallable)

        let noSignature = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "noSignature",
            symbols: symbols,
            interner: interner
        )
        candidates.append(noSignature)

        let wrongArity = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "wrongArity",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType, intType], returnType: intType),
            for: wrongArity
        )
        candidates.append(wrongArity)

        let typeMismatch = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "typeMismatch",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [boolType], returnType: intType),
            for: typeMismatch
        )
        candidates.append(typeMismatch)

        let expectedTypeMismatch = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "expectedMismatch",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: expectedTypeMismatch
        )
        candidates.append(expectedTypeMismatch)

        let resolved = resolver.resolveCall(
            candidates: candidates,
            call: call,
            expectedType: boolType,
            ctx: setup.ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.substitutedTypeArguments, [:])
        XCTAssertEqual(resolved.parameterMapping, [:])
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0002")
    }

    func testResolveCallReturnsAmbiguousDiagnosticForMultipleViableCandidates() {
        let setup = makeSemaContext()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

        let intType = types.make(.primitive(.int, .nonNull))
        let call = CallExpr(
            range: makeRange(start: 30, end: 35),
            calleeName: interner.intern("foo"),
            args: [CallArg(type: intType)]
        )

        let first = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "first",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: first
        )

        let second = defineSymbol(
            kind: .function,
            name: "foo",
            suffix: "second",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: second
        )

        let resolved = resolver.resolveCall(
            candidates: [first, second],
            call: call,
            expectedType: nil,
            ctx: setup.ctx
        )

        XCTAssertNil(resolved.chosenCallee)
        XCTAssertEqual(resolved.diagnostic?.code, "KSWIFTK-SEMA-0003")
    }

    func testResolveCallReturnsChosenCandidateAndIdentityMapping() {
        let setup = makeSemaContext()
        let resolver = OverloadResolver()
        let types = setup.types
        let symbols = setup.symbols
        let interner = setup.interner

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        let constructor = defineSymbol(
            kind: .constructor,
            name: "Ctor",
            suffix: "ctor",
            symbols: symbols,
            interner: interner
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType, boolType], returnType: boolType),
            for: constructor
        )

        let call = CallExpr(
            range: makeRange(start: 40, end: 48),
            calleeName: interner.intern("Ctor"),
            args: [CallArg(type: intType), CallArg(type: boolType)]
        )

        let resolved = resolver.resolveCall(
            candidates: [constructor],
            call: call,
            expectedType: boolType,
            ctx: setup.ctx
        )

        XCTAssertEqual(resolved.chosenCallee, constructor)
        XCTAssertNil(resolved.diagnostic)
        XCTAssertEqual(resolved.parameterMapping, [0: 0, 1: 1])
        XCTAssertEqual(resolved.substitutedTypeArguments, [:])
    }

    private func defineSymbol(
        kind: SymbolKind,
        name: String,
        suffix: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        symbols.define(
            kind: kind,
            name: interner.intern(name),
            fqName: [interner.intern("test"), interner.intern(suffix)],
            declSite: nil,
            visibility: .public,
            flags: []
        )
    }
}
