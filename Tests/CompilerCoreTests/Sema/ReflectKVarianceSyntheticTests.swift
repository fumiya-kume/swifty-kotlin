@testable import CompilerCore
import XCTest

final class ReflectKVarianceSyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected KVariance surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKVarianceEnumEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let enumFQName = ["kotlin", "reflect", "KVariance"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName))
        XCTAssertEqual(sema.symbols.symbol(enumSymbol)?.kind, .enumClass)
        XCTAssertTrue(sema.symbols.symbol(enumSymbol)?.flags.contains(.synthetic) == true)

        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))
        for entry in ["INVARIANT", "IN", "OUT"] {
            let entrySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName + [interner.intern(entry)]))
            XCTAssertEqual(sema.symbols.symbol(entrySymbol)?.kind, .field)
            XCTAssertEqual(sema.symbols.parentSymbol(for: entrySymbol), enumSymbol)
            XCTAssertEqual(sema.symbols.propertyType(for: entrySymbol), enumType)
        }
    }

    func testKVarianceEntriesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KVariance

        fun invariantVariance(): KVariance = KVariance.INVARIANT
        fun inVariance(): KVariance = KVariance.IN
        fun outVariance(): KVariance = KVariance.OUT
        """

        _ = try makeSema(source: source)
    }
}
