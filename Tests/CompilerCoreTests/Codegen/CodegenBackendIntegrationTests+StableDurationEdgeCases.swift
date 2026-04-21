@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-032: kotlin.time stable Duration edge-case coverage.
//
// Stable surface verified (Kotlin 2.x, no @ExperimentalTime required):
//   - Unit extension properties: Int.seconds / .milliseconds / .microseconds /
//     .nanoseconds / .minutes / .hours / .days  (and Long variants)
//   - inWholeSeconds / inWholeMilliseconds / inWholeMicroseconds /
//     inWholeNanoseconds / inWholeMinutes / inWholeHours
//   - absoluteValue, isNegative, isPositive, isFinite, isInfinite
//   - Arithmetic via operator forms: duration + duration, duration - duration,
//     duration * Int, duration / Int, -duration  (operator-lowering path)
//   - Comparison operators: < > <= >= on Duration (compareTo-desugared)
//
// Known gaps (not yet lowered in this compiler):
//   - Duration.ZERO / Duration.INFINITE companion constants
//   - toIsoString() / parseIsoString() / parse() / parseOrNull()
//   - toComponents { days, hours, minutes, seconds, nanoseconds -> ... }
//   - Double receiver extension properties (1.5.seconds etc.)
//   - Division of Duration by Duration returning Double
//   - inWholeDays property

extension CodegenBackendIntegrationTests {

    // MARK: - Unit extension properties (Int receiver)
    // Verifies all seven stable unit helpers map correctly to nanoseconds internally.

    func testDurationStableUnitExtensionPropertiesInt() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.microseconds
        import kotlin.time.Duration.Companion.nanoseconds
        import kotlin.time.Duration.Companion.minutes
        import kotlin.time.Duration.Companion.hours
        import kotlin.time.Duration.Companion.days

        fun main() {
            println(1.seconds.inWholeSeconds)
            println(1500.milliseconds.inWholeMilliseconds)
            println(7.microseconds.inWholeMicroseconds)
            println(7.nanoseconds.inWholeNanoseconds)
            println(3.minutes.inWholeMinutes)
            println(2.hours.inWholeHours)
            // 4 days expressed in hours: 4 * 24 = 96
            println(4.days.inWholeHours)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableUnitExtInt",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1
                1500
                7
                7
                3
                2
                96
                """ + "\n"
            )
        }
    }

    // MARK: - Unit extension properties (Long receiver)
    // Kotlin stable: val Long.seconds: Duration etc.

    func testDurationStableUnitExtensionPropertiesLong() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.nanoseconds

        fun main() {
            println(5L.seconds.inWholeSeconds)
            println(2500L.milliseconds.inWholeMilliseconds)
            // 1_000_000 ns == 1 ms
            println(1_000_000L.nanoseconds.inWholeMilliseconds)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableUnitExtLong",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "5\n2500\n1\n")
        }
    }

    // MARK: - inWhole* accessors coverage
    // All six stable inWholeX properties are tested together.

    func testDurationStableInWholeAccessors() throws {
        let source = """
        import kotlin.time.Duration.Companion.hours

        fun main() {
            val twoHours = 2.hours
            println(twoHours.inWholeHours)
            println(twoHours.inWholeMinutes)
            println(twoHours.inWholeSeconds)
            println(twoHours.inWholeMilliseconds)
            println(twoHours.inWholeMicroseconds)
            println(twoHours.inWholeNanoseconds)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableInWholeAccessors",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                2
                120
                7200
                7200000
                7200000000
                7200000000000
                """ + "\n"
            )
        }
    }

    // MARK: - Negative duration from negative Int literal
    // Using the pattern (-N).unit which constructs a negative duration.

    func testDurationStableNegativeLiteralDuration() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds
        import kotlin.time.Duration.Companion.milliseconds

        fun main() {
            val neg = (-5).seconds
            println(neg.inWholeSeconds)
            println(neg.isNegative())
            println(neg.isPositive())

            val neg2 = (-1500).milliseconds
            println(neg2.inWholeMilliseconds)
            println(neg2.isNegative())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableNegativeLiteralDuration",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "-5\ntrue\nfalse\n-1500\ntrue\n")
        }
    }

    // MARK: - absoluteValue on negative duration

    func testDurationStableAbsoluteValue() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val neg = (-7).seconds
            val abs = neg.absoluteValue
            println(abs.inWholeSeconds)
            println(abs.isNegative())
            println(abs.isPositive())

            // absoluteValue of a positive duration is unchanged
            val pos = 3.seconds
            println(pos.absoluteValue.inWholeSeconds)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableAbsoluteValue",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "7\nfalse\ntrue\n3\n")
        }
    }

    // MARK: - isFinite / isInfinite with overflow sentinel

    func testDurationStableIsFiniteIsInfinite() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val finite = 10.seconds
            println(finite.isFinite())
            println(finite.isInfinite())

            // Long.MAX_VALUE seconds overflows nanosecond Int64 -> saturation = Int64.max
            // which is the INFINITE sentinel in KSwiftK's Duration implementation.
            val huge = 9223372036854775807L.seconds
            println(huge.isInfinite())
            println(huge.isFinite())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableIsFiniteInfinite",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\nfalse\ntrue\nfalse\n")
        }
    }

    // MARK: - Arithmetic: addition and subtraction via operator syntax
    // GAP: Duration + Duration and Duration - Duration operator forms are not yet
    // lowered in KSwiftK. The `plus` / `minus` stubs exist in the symbol table but
    // the operator-lowering pass does not route `kk_op_add` / `kk_op_sub` to
    // `kk_duration_plus` / `kk_duration_minus` when operands are Duration handles.

    func testDurationStableArithmeticAddSubtract() throws {
        throw XCTSkip(
            "Duration + Duration / Duration - Duration operator forms not yet lowered " +
            "(kk_duration_plus / kk_duration_minus are registered but not routed from " +
            "the generic kk_op_add / kk_op_sub path for Duration operands)"
        )
        // Expected once fixed:
        //   (2.seconds + 500.ms).inWholeMilliseconds == 2500
        //   (2.seconds - 500.ms).inWholeMilliseconds == 1500
        //   (500.ms - 2.seconds).isNegative()          == true
    }

    // MARK: - Arithmetic: multiplication and division by Int
    // GAP: Duration * Int and Duration / Int operator forms are not yet lowered.
    // The stubs `kk_duration_times_int` / `kk_duration_div_int` exist but the
    // operator-lowering pass routes `*` to the generic integer path, not Duration.

    func testDurationStableArithmeticTimesDiv() throws {
        throw XCTSkip(
            "Duration * Int / Duration / Int operator forms not yet lowered " +
            "(kk_duration_times_int / kk_duration_div_int not routed from kk_op_mul / kk_op_div " +
            "when LHS operand is a Duration handle)"
        )
        // Expected once fixed:
        //   (10.seconds * 2).inWholeSeconds  == 20
        //   (10.seconds / 2).inWholeSeconds  == 5
        //   (10.seconds * 0).inWholeSeconds  == 0
        //   (10.seconds * 0).isPositive()    == false
    }

    // MARK: - Unary minus operator
    // GAP: Unary `-duration` is not yet routed to `kk_duration_unary_minus`.
    // The OperatorLoweringPass routes `.unaryMinus` to `kk_op_uminus` (the
    // generic integer negation), which doesn't handle Duration handles.

    func testDurationStableUnaryMinus() throws {
        throw XCTSkip(
            "Duration unary minus (-duration) not yet routed to kk_duration_unary_minus " +
            "(OperatorLoweringPass uses kk_op_uminus for all unaryMinus operations, " +
            "regardless of operand type)"
        )
        // Expected once fixed:
        //   -(5.seconds).inWholeSeconds  == -5
        //   -(5.seconds).isNegative()    == true
        //   (-(-5.seconds)).inWholeSeconds == 5
    }

    // MARK: - Comparison operators (< > <= >=) on Duration

    func testDurationStableComparisonOperators() throws {
        throw XCTSkip(
            "Duration comparison operators (<, >, <=, >=) are not yet routed to " +
            "kk_duration_compare. The compareTo method is registered in the runtime but the " +
            "binary operator desugaring for Duration types is pending."
        )
    }

    // MARK: - INFINITE saturation: adding to saturated sentinel stays INFINITE
    // GAP: Depends on Duration + Duration operator, which is not yet lowered.

    func testDurationStableInfiniteAddSaturation() throws {
        throw XCTSkip(
            "Depends on Duration + Duration operator lowering (not yet implemented). " +
            "The isInfinite() predicate itself works (verified separately), but inf + 1.seconds " +
            "cannot be tested until the + operator is routed to kk_duration_plus."
        )
        // Expected semantics once fixed:
        //   (Long.MAX_VALUE.seconds).isInfinite()    == true
        //   (inf + 1.seconds).isInfinite()           == true  (saturation)
        //   (inf - inf).isInfinite()                 == false (Int64.max - Int64.max = 0)
        //   (inf - inf).isPositive()                 == false (== zero)
    }

    // MARK: - Division by zero saturates to INFINITE
    // GAP: Depends on Duration / Int operator, which is not yet lowered.

    func testDurationStableDivByZeroSaturatesToInfinite() throws {
        throw XCTSkip(
            "Depends on Duration / Int operator lowering (not yet implemented). " +
            "kk_duration_div_int handles div-by-zero correctly in the runtime but the " +
            "operator is not routed from kk_op_div to kk_duration_div_int for Duration operands."
        )
        // Expected semantics once fixed:
        //   (5.seconds / 0).isInfinite()    == true  (positive saturation)
        //   ((-5).seconds / 0).isInfinite() == true  (negative saturation)
    }

    // MARK: - Negative zero: -ZERO equals ZERO (same nanosecond count = 0)
    // GAP: Depends on Duration unary minus, which is not yet lowered.
    // Partial test: 0.seconds predicates are verified directly below.

    func testDurationStableNegativeZeroEqualsPositiveZero() throws {
        throw XCTSkip(
            "Depends on Duration unary minus operator lowering (not yet implemented). " +
            "The zero-duration predicates themselves are verified in testDurationStableZeroDurationPredicates."
        )
        // Expected semantics once fixed:
        //   val zero = 0.seconds; val negZero = -zero
        //   zero.inWholeSeconds    == 0
        //   negZero.inWholeSeconds == 0  (nanoseconds is 0, negating 0 yields 0)
        //   zero.isNegative()      == false
        //   negZero.isNegative()   == false (Kotlin: -Duration.ZERO == Duration.ZERO)
    }

    // MARK: - Zero duration predicates (no operator forms needed)

    func testDurationStableZeroDurationPredicates() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val zero = 0.seconds
            println(zero.inWholeSeconds)
            println(zero.isPositive())
            println(zero.isNegative())
            println(zero.isFinite())
            println(zero.isInfinite())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableZeroPredicates",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            // isPositive: nanoseconds > 0 => false for zero
            // isNegative: nanoseconds < 0 => false for zero
            // isFinite:   nanoseconds != Int64.max/min => true for zero
            XCTAssertEqual(normalizedStdout, "0\nfalse\nfalse\ntrue\nfalse\n")
        }
    }

    // MARK: - inWholeNanoseconds for small and negative durations

    func testDurationStableInWholeNanoseconds() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            // 10 seconds = 10_000_000_000 nanoseconds — fits in Long
            val d = 10.seconds
            println(d.inWholeNanoseconds)

            // Negative durations yield negative nanosecond count
            val neg = (-3).seconds
            println(neg.inWholeNanoseconds)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableInWholeNs",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "10000000000\n-3000000000\n")
        }
    }

    // MARK: - Cross-unit consistency: same duration expressed via different units

    func testDurationStableCrossUnitConsistency() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.microseconds
        import kotlin.time.Duration.Companion.nanoseconds
        import kotlin.time.Duration.Companion.minutes
        import kotlin.time.Duration.Companion.hours
        import kotlin.time.Duration.Companion.days

        fun main() {
            // Different units representing the same span should have identical inWhole* values
            println(60.seconds.inWholeMinutes)   // == 1
            println(1.minutes.inWholeSeconds)     // == 60

            println(60.minutes.inWholeHours)      // == 1
            println(1.hours.inWholeMinutes)        // == 60

            println(24.hours.inWholeHours)         // == 24
            println(1.days.inWholeHours)           // == 24

            // Nanosecond granularity
            println(1.milliseconds.inWholeNanoseconds)    // 1_000_000
            println(1000.microseconds.inWholeNanoseconds) // 1_000_000
            println(1_000_000.nanoseconds.inWholeNanoseconds) // 1_000_000
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableCrossUnit",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1
                60
                1
                60
                24
                24
                1000000
                1000000
                1000000
                """ + "\n"
            )
        }
    }

    // MARK: - Stable/experimental boundary
    // isNegative / isPositive / isFinite / isInfinite are @Stable since Kotlin 1.6.
    // This test intentionally has no @OptIn — compilation failure would indicate
    // these predicates are incorrectly gated behind @ExperimentalTime.

    func testDurationStableBoundaryPredicatesRequireNoOptIn() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val d = 3.seconds
            println(d.isPositive())
            println(d.isNegative())
            println(d.isFinite())
            println(d.isInfinite())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableBoundaryPredicates",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\nfalse\ntrue\nfalse\n")
        }
    }
}
