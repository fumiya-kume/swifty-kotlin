@testable import CompilerCore
import XCTest

/// STDLIB-TIME-FN-012: Validates the kotlin.time.DurationUnit to
/// java.util.concurrent.TimeUnit conversion surface.
final class DurationUnitToTimeUnitFunctionTests: XCTestCase {
    func testDurationUnitToTimeUnitSyntheticFunctionIsRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)

        let functionFQName = ["kotlin", "time", "toTimeUnit"].map { ctx.interner.intern($0) }
        let functionSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: functionFQName).first {
                sema.symbols.externalLinkName(for: $0) == "kk_duration_unit_to_time_unit"
            },
            "kotlin.time.toTimeUnit must link to kk_duration_unit_to_time_unit"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
        XCTAssertTrue(signature.parameterTypes.isEmpty)

        let durationUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("time"),
            ctx.interner.intern("DurationUnit"),
        ]))
        let timeUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            ctx.interner.intern("java"),
            ctx.interner.intern("util"),
            ctx.interner.intern("concurrent"),
            ctx.interner.intern("TimeUnit"),
        ]))

        guard case .classType(let receiverType) = sema.types.kind(of: signature.receiverType) else {
            XCTFail("toTimeUnit receiver must be kotlin.time.DurationUnit")
            return
        }
        XCTAssertEqual(receiverType.classSymbol, durationUnitSymbol)

        guard case .classType(let returnType) = sema.types.kind(of: signature.returnType) else {
            XCTFail("toTimeUnit return type must be java.util.concurrent.TimeUnit")
            return
        }
        XCTAssertEqual(returnType.classSymbol, timeUnitSymbol)
    }

    func testDurationUnitToTimeUnitResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import java.util.concurrent.TimeUnit
        import kotlin.time.DurationUnit

        fun convert(unit: DurationUnit): TimeUnit {
            return unit.toTimeUnit()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected DurationUnit.toTimeUnit() to type-check, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
