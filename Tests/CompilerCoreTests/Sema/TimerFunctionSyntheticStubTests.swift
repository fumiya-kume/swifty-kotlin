@testable import CompilerCore
import Foundation
import XCTest

/// Tests for `kotlin.concurrent.timer` synthetic stubs (STDLIB-CONC-FN-008).
final class TimerFunctionSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    // MARK: - java.util.Timer / TimerTask / Date registration

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

    func testJavaUtilDateClassIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let dateFQName = ["java", "util", "Date"].map { interner.intern($0) }
        let dateSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: dateFQName),
            "Expected java.util.Date to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(dateSymbol)?.kind, .class)
    }

    // MARK: - timer overload 1: timer(name, daemon, initialDelay, period, action)

    func testTimerDelayOverloadSignature() throws {
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
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)

        let timerFnFQName = ["kotlin", "concurrent", "timer"].map { interner.intern($0) }
        let timerDelaySymbol = sema.symbols.lookupAll(fqName: timerFnFQName).first(where: { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == nil
                && sig.parameterTypes == [
                    nullableStringType,
                    sema.types.booleanType,
                    sema.types.longType,
                    sema.types.longType,
                    actionType,
                ]
                && sig.returnType == timerType
        })

        let timerSymbolFn = try XCTUnwrap(
            timerDelaySymbol,
            "Expected kotlin.concurrent.timer(name, daemon, initialDelay, period, action) to be registered"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: timerSymbolFn),
            "kk_timer_create_delay",
            "timer(name, daemon, initialDelay, period, action) should link to kk_timer_create_delay"
        )
        XCTAssertTrue(sema.symbols.symbol(timerSymbolFn)?.flags.contains(.synthetic) == true)

        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: timerSymbolFn))
        XCTAssertEqual(
            sig.valueParameterHasDefaultValues,
            [true, true, true, false, false],
            "name, daemon, initialDelay have defaults; period and action do not"
        )
    }

    // MARK: - timer overload 2: timer(name, daemon, startAt, period, action)

    func testTimerDateOverloadSignature() throws {
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

        let dateFQName = ["java", "util", "Date"].map { interner.intern($0) }
        let dateSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: dateFQName))
        let dateType = sema.types.make(.classType(ClassType(
            classSymbol: dateSymbol, args: [], nullability: .nonNull
        )))

        let actionType = sema.types.make(.functionType(FunctionType(
            receiver: timerTaskType,
            params: [],
            returnType: sema.types.unitType
        )))
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)

        let timerFnFQName = ["kotlin", "concurrent", "timer"].map { interner.intern($0) }
        let timerDateSymbol = sema.symbols.lookupAll(fqName: timerFnFQName).first(where: { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == nil
                && sig.parameterTypes == [
                    nullableStringType,
                    sema.types.booleanType,
                    dateType,
                    sema.types.longType,
                    actionType,
                ]
                && sig.returnType == timerType
        })

        let timerSymbolFn = try XCTUnwrap(
            timerDateSymbol,
            "Expected kotlin.concurrent.timer(name, daemon, startAt, period, action) to be registered"
        )
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: timerSymbolFn),
            "kk_timer_create_date",
            "timer(name, daemon, startAt, period, action) should link to kk_timer_create_date"
        )
        XCTAssertTrue(sema.symbols.symbol(timerSymbolFn)?.flags.contains(.synthetic) == true)

        let sig = try XCTUnwrap(sema.symbols.functionSignature(for: timerSymbolFn))
        XCTAssertEqual(
            sig.valueParameterHasDefaultValues,
            [true, true, false, false, false],
            "name and daemon have defaults; startAt, period, and action do not"
        )
    }

    // MARK: - Source-level resolution

    func testTimerDelayOverloadResolvesInSource() throws {
        let source = """
        import kotlin.concurrent.timer

        fun probe() {
            timer(period = 1000L) {}
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected timer(period, action) to resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }
}
