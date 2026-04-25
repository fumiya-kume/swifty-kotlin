@testable import CompilerCore
import XCTest

final class RangeSyntheticInterfaceTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testClosedRangeAndClosedFloatingPointRangeSymbolsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let rangesFQName = ["kotlin", "ranges"].map { interner.intern($0) }
        let closedRangeFQName = rangesFQName + [interner.intern("ClosedRange")]
        let closedFloatingPointRangeFQName = rangesFQName + [interner.intern("ClosedFloatingPointRange")]
        let comparableFQName = ["kotlin", "Comparable"].map { interner.intern($0) }

        let closedRangeSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: closedRangeFQName),
            "Expected kotlin.ranges.ClosedRange to be registered"
        )
        let closedFloatingPointRangeSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: closedFloatingPointRangeFQName),
            "Expected kotlin.ranges.ClosedFloatingPointRange to be registered"
        )
        let comparableSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: comparableFQName),
            "Expected kotlin.Comparable to be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(closedRangeSymbol)?.kind, .interface)
        XCTAssertEqual(sema.symbols.symbol(closedFloatingPointRangeSymbol)?.kind, .interface)

        let closedRangeTypeParamSymbol = try XCTUnwrap(sema.types.nominalTypeParameterSymbols(for: closedRangeSymbol).first)
        let closedFloatingPointRangeTypeParamSymbol = try XCTUnwrap(
            sema.types.nominalTypeParameterSymbols(for: closedFloatingPointRangeSymbol).first
        )
        let closedRangeTypeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: closedRangeTypeParamSymbol,
            nullability: .nonNull
        )))
        let closedFloatingPointRangeTypeParamType = sema.types.make(.typeParam(TypeParamType(
            symbol: closedFloatingPointRangeTypeParamSymbol,
            nullability: .nonNull
        )))

        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: closedRangeSymbol), [.invariant])
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: closedFloatingPointRangeSymbol), [.invariant])

        let expectedComparableBoundForClosedRange = sema.types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.in(closedRangeTypeParamType)],
            nullability: .nonNull
        )))
        let expectedComparableBoundForFloatingPointRange = sema.types.make(.classType(ClassType(
            classSymbol: comparableSymbol,
            args: [.in(closedFloatingPointRangeTypeParamType)],
            nullability: .nonNull
        )))

        XCTAssertEqual(
            sema.symbols.typeParameterUpperBounds(for: closedRangeTypeParamSymbol),
            [expectedComparableBoundForClosedRange]
        )
        XCTAssertEqual(
            sema.symbols.typeParameterUpperBounds(for: closedFloatingPointRangeTypeParamSymbol),
            [expectedComparableBoundForFloatingPointRange]
        )

        XCTAssertEqual(
            sema.symbols.directSupertypes(for: closedFloatingPointRangeSymbol),
            [closedRangeSymbol]
        )
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: closedFloatingPointRangeSymbol, supertype: closedRangeSymbol),
            [.invariant(closedFloatingPointRangeTypeParamType)]
        )

        let closedRangeInterfaceType = sema.types.make(.classType(ClassType(
            classSymbol: closedRangeSymbol,
            args: [.invariant(closedRangeTypeParamType)],
            nullability: .nonNull
        )))
        let closedFloatingPointRangeInterfaceType = sema.types.make(.classType(ClassType(
            classSymbol: closedFloatingPointRangeSymbol,
            args: [.invariant(closedFloatingPointRangeTypeParamType)],
            nullability: .nonNull
        )))

        let startFQName = closedRangeFQName + [interner.intern("start")]
        let endFQName = closedRangeFQName + [interner.intern("endInclusive")]
        let containsFQName = closedRangeFQName + [interner.intern("contains")]
        let isEmptyFQName = closedRangeFQName + [interner.intern("isEmpty")]
        let floatingStartFQName = closedFloatingPointRangeFQName + [interner.intern("start")]
        let floatingEndFQName = closedFloatingPointRangeFQName + [interner.intern("endInclusive")]
        let floatingContainsFQName = closedFloatingPointRangeFQName + [interner.intern("contains")]
        let floatingIsEmptyFQName = closedFloatingPointRangeFQName + [interner.intern("isEmpty")]
        let lessThanOrEqualsFQName = closedFloatingPointRangeFQName + [interner.intern("lessThanOrEquals")]

        let startSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: startFQName))
        let endSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: endFQName))
        let containsSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: containsFQName))
        let isEmptySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: isEmptyFQName))
        let floatingStartSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: floatingStartFQName))
        let floatingEndSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: floatingEndFQName))
        let floatingContainsSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: floatingContainsFQName))
        let floatingIsEmptySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: floatingIsEmptyFQName))
        let lessThanOrEqualsSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: lessThanOrEqualsFQName))

        XCTAssertEqual(sema.symbols.propertyType(for: startSymbol), closedRangeTypeParamType)
        XCTAssertEqual(sema.symbols.propertyType(for: endSymbol), closedRangeTypeParamType)
        XCTAssertEqual(sema.symbols.propertyType(for: floatingStartSymbol), closedFloatingPointRangeTypeParamType)
        XCTAssertEqual(sema.symbols.propertyType(for: floatingEndSymbol), closedFloatingPointRangeTypeParamType)

        let containsSignature = try XCTUnwrap(sema.symbols.functionSignature(for: containsSymbol))
        XCTAssertEqual(containsSignature.receiverType, closedRangeInterfaceType)
        XCTAssertEqual(containsSignature.parameterTypes, [closedRangeTypeParamType])
        XCTAssertEqual(containsSignature.returnType, sema.types.booleanType)
        let floatingContainsSignature = try XCTUnwrap(sema.symbols.functionSignature(for: floatingContainsSymbol))
        XCTAssertEqual(floatingContainsSignature.receiverType, closedFloatingPointRangeInterfaceType)
        XCTAssertEqual(floatingContainsSignature.parameterTypes, [closedFloatingPointRangeTypeParamType])
        XCTAssertEqual(floatingContainsSignature.returnType, sema.types.booleanType)

        let isEmptySignature = try XCTUnwrap(sema.symbols.functionSignature(for: isEmptySymbol))
        XCTAssertEqual(isEmptySignature.receiverType, closedRangeInterfaceType)
        XCTAssertEqual(isEmptySignature.parameterTypes, [])
        XCTAssertEqual(isEmptySignature.returnType, sema.types.booleanType)
        let floatingIsEmptySignature = try XCTUnwrap(sema.symbols.functionSignature(for: floatingIsEmptySymbol))
        XCTAssertEqual(floatingIsEmptySignature.receiverType, closedFloatingPointRangeInterfaceType)
        XCTAssertEqual(floatingIsEmptySignature.parameterTypes, [])
        XCTAssertEqual(floatingIsEmptySignature.returnType, sema.types.booleanType)

        let lessThanOrEqualsSignature = try XCTUnwrap(sema.symbols.functionSignature(for: lessThanOrEqualsSymbol))
        XCTAssertEqual(lessThanOrEqualsSignature.receiverType, closedFloatingPointRangeInterfaceType)
        XCTAssertEqual(lessThanOrEqualsSignature.parameterTypes, [closedFloatingPointRangeTypeParamType, closedFloatingPointRangeTypeParamType])
        XCTAssertEqual(lessThanOrEqualsSignature.returnType, sema.types.booleanType)
    }

    func testClosedRangeAndClosedFloatingPointRangeResolveInSource() throws {
        let source = """
        fun inspectClosedRange(range: ClosedRange<Int>): Boolean {
            return range.start <= range.endInclusive && range.contains(3) && !range.isEmpty()
        }

        fun inspectClosedFloatingPointRange(): Boolean {
            val range = 1.0..4.0
            return range.start <= range.endInclusive &&
                range.contains(3.0) &&
                !range.isEmpty()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected ClosedRange and ClosedFloatingPointRange surface to resolve cleanly, got: \(diagnosticSummary)"
            )
        }
    }
}
