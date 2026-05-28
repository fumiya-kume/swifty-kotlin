@testable import CompilerCore
import Foundation
import XCTest

/// Tests for `kotlin.concurrent.schedule` synthetic stubs (STDLIB-CONC-FN-005).
final class TimerScheduleSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    // MARK: - java.util.Timer / TimerTask registration

    func testJavaUtilTimerClassIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let timerFQName = ["java", "util", "Timer"].map { interner.intern($0) }
        let timerSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: timerFQName),
            "Expected java.util.Timer to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(timerSymbol)?.kind, .class)
    }

    func testJavaUtilTimerTaskClassIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let timerTaskFQName = ["java", "util", "TimerTask"].map { interner.intern($0) }
        let timerTaskSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: timerTaskFQName),
            "Expected java.util.TimerTask to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(timerTaskSymbol)?.kind, .class)
    }

    // MARK: - schedule overload 1: Timer.schedule(delay, action)

    func testScheduleDelayOverloadSignature() throws {
        let (sema, interner) = try makeSema()

        let timerFQName = ["java", "util", "Timer"].map { interner.intern($0) }
        let timerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerFQName))
        let timerType = sema.types.make(.classType(ClassType(
            classSymbol: timerSymbol, args: [], nullability: .nonNull
        )))

        let timerTaskFQName = ["java", "util", "TimerTask"].map { interner.intern($0) }
        let timerTaskSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerTaskFQName))
        let timerTaskType = sema.types.make(.classType(ClassType(
            classSymbol: timerTaskSymbol, args: [], nullability: .nonNull
        )))

        let actionType = sema.types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: sema.types.unitType
        )))

        let scheduleFQName = ["kotlin", "concurrent", "schedule"].map { interner.intern($0) }
        let scheduleDelaySymbol = sema.symbols.lookupAll(fqName: scheduleFQName).first(where: { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == timerType
                && sig.parameterTypes == [sema.types.longType, actionType]
                && sig.returnType == timerTaskType
        })

        let scheduleSymbol = try XCTUnwrap(
            scheduleDelaySymbol,
            "Expected kotlin.concurrent.schedule(delay, action) to be registered"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: scheduleSymbol),
            "kk_concurrent_schedule_delay",
            "schedule(delay, action) should link to kk_concurrent_schedule_delay"
        )
        XCTAssertTrue(sema.symbols.symbol(scheduleSymbol)?.flags.contains(.synthetic) == true)
    }

    // MARK: - schedule overload 2: Timer.schedule(delay, period, action)

    func testSchedulePeriodOverloadSignature() throws {
        let (sema, interner) = try makeSema()

        let timerFQName = ["java", "util", "Timer"].map { interner.intern($0) }
        let timerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerFQName))
        let timerType = sema.types.make(.classType(ClassType(
            classSymbol: timerSymbol, args: [], nullability: .nonNull
        )))

        let timerTaskFQName = ["java", "util", "TimerTask"].map { interner.intern($0) }
        let timerTaskSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerTaskFQName))
        let timerTaskType = sema.types.make(.classType(ClassType(
            classSymbol: timerTaskSymbol, args: [], nullability: .nonNull
        )))

        let actionType = sema.types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: sema.types.unitType
        )))

        let scheduleFQName = ["kotlin", "concurrent", "schedule"].map { interner.intern($0) }
        let schedulePeriodSymbol = sema.symbols.lookupAll(fqName: scheduleFQName).first(where: { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == timerType
                && sig.parameterTypes == [sema.types.longType, sema.types.longType, actionType]
                && sig.returnType == timerTaskType
        })

        let scheduleSymbol = try XCTUnwrap(
            schedulePeriodSymbol,
            "Expected kotlin.concurrent.schedule(delay, period, action) to be registered"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: scheduleSymbol),
            "kk_concurrent_schedule_period",
            "schedule(delay, period, action) should link to kk_concurrent_schedule_period"
        )
        XCTAssertTrue(sema.symbols.symbol(scheduleSymbol)?.flags.contains(.synthetic) == true)
    }

    // MARK: - Source-level resolution

    func testScheduleDelayResolvesInSource() throws {
        let source = """
        import kotlin.concurrent.schedule
        import java.util.Timer

        fun probe() {
            val t = Timer()
            t.schedule(500L) {}
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected schedule(delay, action) to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }
}
