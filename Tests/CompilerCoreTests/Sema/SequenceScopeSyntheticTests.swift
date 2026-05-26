@testable import CompilerCore
import XCTest

final class SequenceScopeSyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected SequenceScope surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testSequenceScopeSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sequencePackage = ["kotlin", "sequences"].map { interner.intern($0) }
        let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

        let scopeSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("SequenceScope")]
        ))
        let sequenceSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("Sequence")]
        ))
        let iteratorSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("Iterator")]
        ))
        let iterableSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("Iterable")]
        ))
        XCTAssertEqual(sema.symbols.symbol(scopeSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.symbol(scopeSymbol)?.flags.contains(.synthetic) == true)

        let typeParams = sema.types.nominalTypeParameterSymbols(for: scopeSymbol)
        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: scopeSymbol), [.in])

        let elementType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
        let yieldSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("SequenceScope"), interner.intern("yield")]
        ))
        let yieldSignature = try XCTUnwrap(sema.symbols.functionSignature(for: yieldSymbol))
        XCTAssertEqual(yieldSignature.receiverType, receiverType)
        XCTAssertEqual(yieldSignature.parameterTypes, [elementType])
        XCTAssertEqual(yieldSignature.returnType, sema.types.unitType)

        let yieldAllSymbols = sema.symbols.lookupAll(
            fqName: sequencePackage + [interner.intern("SequenceScope"), interner.intern("yieldAll")]
        )
        XCTAssertEqual(yieldAllSymbols.count, 3)

        let expectedParameterTypes: Set<TypeID> = [
            sema.types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.out(elementType)],
                nullability: .nonNull
            ))),
            sema.types.make(.classType(ClassType(
                classSymbol: iterableSymbol,
                args: [.out(elementType)],
                nullability: .nonNull
            ))),
            sema.types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(elementType)],
                nullability: .nonNull
            ))),
        ]
        let actualParameterTypes = Set(try yieldAllSymbols.map { symbolID in
            try XCTUnwrap(sema.symbols.functionSignature(for: symbolID)).parameterTypes[0]
        })
        XCTAssertEqual(actualParameterTypes, expectedParameterTypes)
    }
}
