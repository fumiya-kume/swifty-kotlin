@testable import CompilerCore
import XCTest

final class JsRegExpMatchExternalInterfaceTests: XCTestCase {
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
                "Expected RegExpMatch external interface surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testRegExpMatchInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "RegExpMatch"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.RegExpMatch must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .interface)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testRegExpMatchPropertiesAreRegistered() throws {
        let (sema, interner) = try makeSema()

        try assertProperty(
            named: "index",
            hasType: sema.types.intType,
            sema: sema,
            interner: interner
        )
        try assertProperty(
            named: "input",
            hasType: sema.types.stringType,
            sema: sema,
            interner: interner
        )
        try assertProperty(
            named: "length",
            hasType: sema.types.intType,
            sema: sema,
            interner: interner
        )
    }

    private func assertProperty(
        named name: String,
        hasType expectedType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) throws {
        let fqName = ["kotlin", "js", "RegExpMatch", name].map { interner.intern($0) }
        let property = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fqName).first { symbol in
                sema.symbols.symbol(symbol)?.kind == .property
            },
            "RegExpMatch.\(name) property must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(property))

        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.propertyType(for: property), expectedType)
        XCTAssertNil(sema.symbols.externalLinkName(for: property))
    }
}
