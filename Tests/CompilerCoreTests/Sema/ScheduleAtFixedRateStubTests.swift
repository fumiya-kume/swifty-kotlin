@testable import CompilerCore
import Foundation
import XCTest

/// Tests for STDLIB-CONC-FN-006: `kotlin.concurrent.scheduleAtFixedRate` synthetic stubs.
final class ScheduleAtFixedRateStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testTimerClassIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let timerFQName = ["java", "util", "Timer"].map { interner.intern($0) }
        let timerSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: timerFQName),
            "Expected java.util.Timer to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(timerSymbol)?.kind, .class)
    }

    func testTimerTaskClassIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let timerTaskFQName = ["java", "util", "TimerTask"].map { interner.intern($0) }
        let timerTaskSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: timerTaskFQName),
            "Expected java.util.TimerTask to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(timerTaskSymbol)?.kind, .class)
    }

    func testScheduleAtFixedRateDelayOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let timerFQName = ["java", "util", "Timer"].map { interner.intern($0) }
        let timerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerFQName))
        let timerType = sema.types.make(.classType(ClassType(
            classSymbol: timerSymbol,
            args: [],
            nullability: .nonNull
        )))

        let timerTaskFQName = ["java", "util", "TimerTask"].map { interner.intern($0) }
        let timerTaskSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerTaskFQName))
        let timerTaskType = sema.types.make(.classType(ClassType(
            classSymbol: timerTaskSymbol,
            args: [],
            nullability: .nonNull
        )))

        let actionType = sema.types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: sema.types.unitType
        )))

        let schedFQName = ["kotlin", "concurrent", "scheduleAtFixedRate"].map { interner.intern($0) }
        let matchingOverload = sema.symbols.lookupAll(fqName: schedFQName).first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == timerType
                && sig.parameterTypes == [sema.types.longType, sema.types.longType, actionType]
                && sig.returnType == timerTaskType
        }
        let overloadSymbol = try XCTUnwrap(
            matchingOverload,
            "Expected scheduleAtFixedRate(delay: Long, period: Long, action: TimerTask.() -> Unit) to be registered"
        )

        XCTAssertTrue(sema.symbols.symbol(overloadSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertTrue(sema.symbols.symbol(overloadSymbol)?.flags.contains(.inlineFunction) == true)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: overloadSymbol),
            "kk_timer_schedule_at_fixed_rate_delay"
        )
    }

    func testScheduleAtFixedRateTimeOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let timerFQName = ["java", "util", "Timer"].map { interner.intern($0) }
        let timerSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerFQName))
        let timerType = sema.types.make(.classType(ClassType(
            classSymbol: timerSymbol,
            args: [],
            nullability: .nonNull
        )))

        let timerTaskFQName = ["java", "util", "TimerTask"].map { interner.intern($0) }
        let timerTaskSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timerTaskFQName))
        let timerTaskType = sema.types.make(.classType(ClassType(
            classSymbol: timerTaskSymbol,
            args: [],
            nullability: .nonNull
        )))

        let dateFQName = ["java", "util", "Date"].map { interner.intern($0) }
        let dateSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: dateFQName),
            "Expected java.util.Date to be registered"
        )
        let dateType = sema.types.make(.classType(ClassType(
            classSymbol: dateSymbol,
            args: [],
            nullability: .nonNull
        )))

        let actionType = sema.types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: sema.types.unitType
        )))

        let schedFQName = ["kotlin", "concurrent", "scheduleAtFixedRate"].map { interner.intern($0) }
        let matchingOverload = sema.symbols.lookupAll(fqName: schedFQName).first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == timerType
                && sig.parameterTypes == [dateType, sema.types.longType, actionType]
                && sig.returnType == timerTaskType
        }
        let overloadSymbol = try XCTUnwrap(
            matchingOverload,
            "Expected scheduleAtFixedRate(time: Date, period: Long, action: TimerTask.() -> Unit) to be registered"
        )

        XCTAssertTrue(sema.symbols.symbol(overloadSymbol)?.flags.contains(.synthetic) == true)
        XCTAssertTrue(sema.symbols.symbol(overloadSymbol)?.flags.contains(.inlineFunction) == true)
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: overloadSymbol),
            "kk_timer_schedule_at_fixed_rate_time"
        )
    }

    func testScheduleAtFixedRateDelayOverloadResolvesInSource() throws {
        let source = """
        import java.util.Timer
        import java.util.TimerTask
        import kotlin.concurrent.scheduleAtFixedRate

        fun probe(timer: Timer): Unit {
            timer.scheduleAtFixedRate(1000L, 500L) {
                // periodic action
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected scheduleAtFixedRate(delay:period:action:) to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testScheduleAtFixedRateTimeOverloadResolvesInSource() throws {
        let source = """
        import java.util.Date
        import java.util.Timer
        import java.util.TimerTask
        import kotlin.concurrent.scheduleAtFixedRate

        fun probe(timer: Timer, time: Date): Unit {
            timer.scheduleAtFixedRate(time, 500L) {
                // periodic action
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected scheduleAtFixedRate(time:period:action:) to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }
}
