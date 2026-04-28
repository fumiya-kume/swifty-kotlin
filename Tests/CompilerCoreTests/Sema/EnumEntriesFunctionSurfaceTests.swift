@testable import CompilerCore
import XCTest

final class EnumEntriesFunctionSurfaceTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "enumEntries surface should resolve without diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testEnumEntriesFunctionIsRegisteredUnderKotlinEnums() throws {
        let (sema, interner) = try makeSema()
        let enumEntriesSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("enumEntries"),
        ]))
        XCTAssertEqual(sema.symbols.symbol(enumEntriesSymbol)?.kind, .function)
        XCTAssertNil(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enumEntries"),
        ]))
    }

    func testEnumEntriesFunctionIsDefaultImportedFromKotlinEnums() throws {
        let source = """
        enum class Color { RED, BLUE }
        fun entries() = enumEntries<Color>()
        """
        let (sema, interner) = try makeSema(source: source)
        let enumEntriesSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("enumEntries"),
        ]))
        let entriesFunction = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("entries"),
        ]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: entriesFunction))
        guard case .classType = sema.types.kind(of: signature.returnType) else {
            return XCTFail("enumEntries<Color>() should return an EnumEntries-like class type")
        }
        XCTAssertTrue(
            sema.bindings.callBindings.contains(where: { $0.value.chosenCallee == enumEntriesSymbol }),
            "Unqualified enumEntries<Color>() should bind to kotlin.enums.enumEntries"
        )
    }
}
