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
//   - toIsoString() / parseIsoString() / parseIsoStringOrNull()
//   - parse() / parseOrNull()
//   - toComponents { days, hours, minutes, seconds, nanoseconds -> ... }

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

    // MARK: - Companion constants (ZERO / INFINITE)

    func testDurationStableCompanionConstants() throws {
        let source = """
        import kotlin.time.Duration

        fun main() {
            println(Duration.ZERO.inWholeSeconds)
            println(Duration.ZERO.isFinite())
            println(Duration.INFINITE.isInfinite())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableCompanionConstants",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "0\ntrue\ntrue\n")
        }
    }

    // MARK: - Double receiver extension properties

    func testDurationStableDoubleReceiverExtensionProperties() throws {
        let source = """
        import kotlin.time.Duration.Companion.days
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            println(1.5.seconds.inWholeMilliseconds)
            println(1.25.days.inWholeHours)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableDoubleReceiverExtensions",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1500\n30\n")
        }
    }

    // MARK: - Duration / Duration -> Double

    func testDurationStableDurationDivisionReturnsDouble() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            println(3.seconds / 2.seconds)
            println(1.seconds / 4.seconds)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableDivisionReturnsDouble",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1.5\n0.25\n")
        }
    }

    // MARK: - inWholeDays accessor

    func testDurationStableInWholeDays() throws {
        let source = """
        import kotlin.time.Duration.Companion.days
        import kotlin.time.Duration.Companion.hours

        fun main() {
            println(2.days.inWholeDays)
            println(36.hours.inWholeDays)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableInWholeDays",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "2\n1\n")
        }
    }

    // MARK: - Arithmetic: addition and subtraction via operator syntax
    // Covers the operator-lowering path for Duration + Duration and Duration - Duration.

    func testDurationStableArithmeticAddSubtract() throws {
        let source = """
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            println((2.seconds + 500.milliseconds).inWholeMilliseconds)
            println((2.seconds - 500.milliseconds).inWholeMilliseconds)
            println((500.milliseconds - 2.seconds).isNegative())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableAddSubtract",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "2500\n1500\ntrue\n")
        }
    }

    // MARK: - Arithmetic: multiplication and division by Int
    // Covers Duration * Int and Duration / Int operator lowering.

    func testDurationStableArithmeticTimesDiv() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            println((10.seconds * 2).inWholeSeconds)
            println((10.seconds / 2).inWholeSeconds)
            println((10.seconds * 0).inWholeSeconds)
            println((10.seconds * 0).isPositive())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableTimesDiv",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "20\n5\n0\nfalse\n")
        }
    }

    // MARK: - Unary minus operator
    // Covers unary `-duration`.

    func testDurationStableUnaryMinus() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val neg = -(5.seconds)
            println(neg.inWholeSeconds)
            println(neg.isNegative())
            println((-neg).inWholeSeconds)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableUnaryMinus",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "-5\ntrue\n5\n")
        }
    }

    // MARK: - Comparison operators (< > <= >=) on Duration
    // Covers compareTo-desugared binary operators.

    func testDurationStableComparisonOperators() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val shorter = 1.seconds
            val longer = 2.seconds
            println(shorter < longer)
            println(longer > shorter)
            println(shorter <= shorter)
            println(shorter >= longer)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableComparisonOperators",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\ntrue\ntrue\nfalse\n")
        }
    }

    // MARK: - INFINITE saturation: adding to saturated sentinel stays INFINITE
    // Verifies saturation semantics once Duration + Duration is routed.

    func testDurationStableInfiniteAddSaturation() throws {
        let source = """
        import kotlin.time.Duration
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val inf = Duration.INFINITE
            println(inf.isInfinite())
            println((inf + 1.seconds).isInfinite())
            val diff = inf - inf
            println(diff.isInfinite())
            println(diff.isPositive())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableInfiniteAddSaturation",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\ntrue\nfalse\nfalse\n")
        }
    }

    // MARK: - Division by zero saturates to INFINITE
    // Verifies Duration / Int saturation behavior.

    func testDurationStableDivByZeroSaturatesToInfinite() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            println((5.seconds / 0).isInfinite())
            println(((-5).seconds / 0).isInfinite())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableDivByZero",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\ntrue\n")
        }
    }

    // MARK: - Negative zero: -ZERO equals ZERO (same nanosecond count = 0)
    // Covers the zero-preserving unary minus case.

    func testDurationStableNegativeZeroEqualsPositiveZero() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val zero = 0.seconds
            val negZero = -zero
            println(zero.inWholeSeconds)
            println(negZero.inWholeSeconds)
            println(zero.isNegative())
            println(negZero.isNegative())
            println(zero == negZero)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "DurationStableNegativeZeroEqualsPositiveZero",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "0\n0\nfalse\nfalse\ntrue\n")
        }
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
