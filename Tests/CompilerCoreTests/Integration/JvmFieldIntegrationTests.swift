@testable import CompilerCore
import XCTest

final class JvmFieldIntegrationTests: XCTestCase {
    func testJvmFieldCompanionPropertyResolvesViaOwnerClass() throws {
        let source = """
        class Counter {
            companion object {
                @JvmField
                var count: Int = 0
            }
        }

        fun main() {
            Counter.count = Counter.count + 1
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
            "Expected no sema errors for @JvmField companion property access, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    func testJvmFieldCompanionPropertyKeepsOwnerClassPropertySymbolInKIR() throws {
        let source = """
        class Counter {
            companion object {
                @JvmField
                var count: Int = 0
            }
        }

        fun main(): Int {
            Counter.count = Counter.count + 1
            return Counter.count
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let module = try XCTUnwrap(ctx.kir)
        let interner = ctx.interner

        let countProperty = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .property
                && Array(symbol.fqName.suffix(3).map { interner.resolve($0) }) == ["Counter", "Companion", "count"]
        })?.id)

        let globals = module.arena.declarations.compactMap { decl -> KIRGlobal? in
            guard case let .global(global) = decl else { return nil }
            return global
        }

        XCTAssertTrue(globals.contains(where: { $0.symbol == countProperty }))
    }
}
