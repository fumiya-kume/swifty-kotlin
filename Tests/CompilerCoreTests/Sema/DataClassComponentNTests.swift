@testable import CompilerCore
import Foundation
import XCTest

final class DataClassComponentNTests: XCTestCase {
    func testComponentNUsesOwnerVisibilityForPrivateDataClass() throws {
        let source = """
        package test

        private data class Secret(val value: Int)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "DataClassComponentN")
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let componentFQName = [
                interner.intern("test"),
                interner.intern("Secret"),
                interner.intern("component1"),
            ]

            let componentSymbolID = try XCTUnwrap(sema.symbols.lookupAll(fqName: componentFQName).first)
            let componentSymbol = try XCTUnwrap(sema.symbols.symbol(componentSymbolID))

            XCTAssertEqual(componentSymbol.visibility, .private)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }
}
