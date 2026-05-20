@testable import CompilerCore
import XCTest

final class ReflectKVisibilitySyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected KVisibility surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKVisibilityEnumEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let enumFQName = reflectPackage + [interner.intern("KVisibility")]
        let enumSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: enumFQName),
            "Expected kotlin.reflect.KVisibility to be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(enumSymbol)?.kind, .enumClass)
        XCTAssertTrue(sema.symbols.symbol(enumSymbol)?.flags.contains(.synthetic) == true)

        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))
        for entry in ["PUBLIC", "PROTECTED", "INTERNAL", "PRIVATE"] {
            let entrySymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: enumFQName + [interner.intern(entry)]),
                "Expected KVisibility.\(entry) to be registered"
            )
            XCTAssertEqual(sema.symbols.parentSymbol(for: entrySymbol), enumSymbol)
            XCTAssertEqual(sema.symbols.propertyType(for: entrySymbol), enumType)
        }
    }

    func testKVisibilityEntriesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KVisibility

        fun visibility(): KVisibility = KVisibility.PUBLIC

        fun isPrivate(visibility: KVisibility): Boolean =
            visibility == KVisibility.PRIVATE
        """

        _ = try makeSema(source: source)
    }
}
