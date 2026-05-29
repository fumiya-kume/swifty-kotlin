@testable import CompilerCore
import XCTest

/// STDLIB-TIME-FN-006: Validates the java.util.concurrent.TimeUnit to
/// kotlin.time.DurationUnit conversion surface.
final class TimeUnitToDurationUnitFunctionTests: XCTestCase {
    func testTimeUnitToDurationUnitSyntheticFunctionIsRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)

        let functionFQName = ["kotlin", "time", "toDurationUnit"].map { ctx.interner.intern($0) }
        let functionSymbols = sema.symbols.lookupAll(fqName: functionFQName)
        let functionSymbol = try XCTUnwrap(
            functionSymbols.first {
                sema.symbols.externalLinkName(for: $0) == "kk_time_unit_to_duration_unit"
            },
            "kotlin.time.toDurationUnit must link to kk_time_unit_to_duration_unit"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
        XCTAssertTrue(signature.parameterTypes.isEmpty)

        let timeUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            ctx.interner.intern("java"),
            ctx.interner.intern("util"),
            ctx.interner.intern("concurrent"),
            ctx.interner.intern("TimeUnit"),
        ]))
        let durationUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("time"),
            ctx.interner.intern("DurationUnit"),
        ]))

        guard case .classType(let receiverType) = sema.types.kind(of: signature.receiverType) else {
            XCTFail("toDurationUnit receiver must be java.util.concurrent.TimeUnit")
            return
        }
        XCTAssertEqual(receiverType.classSymbol, timeUnitSymbol)

        guard case .classType(let returnType) = sema.types.kind(of: signature.returnType) else {
            XCTFail("toDurationUnit return type must be kotlin.time.DurationUnit")
            return
        }
        XCTAssertEqual(returnType.classSymbol, durationUnitSymbol)
    }

    func testTimeUnitToDurationUnitResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import java.util.concurrent.TimeUnit
        import kotlin.time.DurationUnit

        fun convert(unit: TimeUnit): DurationUnit {
            return unit.toDurationUnit()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected TimeUnit.toDurationUnit() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
