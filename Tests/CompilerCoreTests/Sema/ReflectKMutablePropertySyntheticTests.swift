@testable import CompilerCore
import XCTest

final class ReflectKMutablePropertySyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected KMutableProperty surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKMutablePropertySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }

        let kPropertySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty")]
        ))
        let kMutablePropertySymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))

        let kMutablePropertyInfo = try XCTUnwrap(sema.symbols.symbol(kMutablePropertySymbol))
        XCTAssertEqual(kMutablePropertyInfo.kind, .interface)
        XCTAssertTrue(kMutablePropertyInfo.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kMutablePropertySymbol)
        XCTAssertEqual(typeParams.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: kMutablePropertySymbol), [.invariant])

        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        XCTAssertTrue(sema.symbols.directSupertypes(for: kMutablePropertySymbol).contains(kPropertySymbol))
        XCTAssertEqual(
            sema.symbols.supertypeTypeArgs(for: kMutablePropertySymbol, supertype: kPropertySymbol),
            [.invariant(valueType)]
        )
    }

    func testKMutablePropertyTypeReferencesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KMutableProperty

        fun <V> propertyName(property: KMutableProperty<V>): String = property.name
        """

        _ = try makeSema(source: source)
    }
}
