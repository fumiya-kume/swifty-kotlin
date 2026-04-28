@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesMathOverloadEdgeCases() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            val sqrtFloat: Float = sqrt(9.0f)
            val sqrtDouble: Double = sqrt(9.0)
            println(sqrtFloat)
            println(sqrtDouble)

            val absInt: Int = abs(-7)
            val absLong: Long = abs(-9L)
            val absFloat: Float = abs(-3.5f)
            val absDouble: Double = abs(-4.5)
            println(absInt)
            println(absLong)
            println(absFloat)
            println(absDouble)

            val atan2Float: Float = atan2(1.0f, 1.0f)
            val atan2Double: Double = atan2(1.0, 1.0)
            println(atan2Float > 0.78f && atan2Float < 0.79f)
            println(atan2Double > 0.78 && atan2Double < 0.79)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MathOverloadEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                3.0
                3.0
                7
                9
                3.5
                4.5
                true
                true
                """
                + "\n"
            )
        }
    }

    func testCodegenMathExtensionPropertiesLowerToRuntimeHelpers() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            val i: Int = -7
            val l: Long = -9L
            val f: Float = -3.5f
            val d: Double = -4.5
            val oneF: Float = 1.0f
            val oneD: Double = 1.0
            val ai: Int = i.absoluteValue
            val al: Long = l.absoluteValue
            val af: Float = f.absoluteValue
            val ad: Double = d.absoluteValue
            val si: Int = i.sign
            val sl: Int = l.sign
            val sf: Float = f.sign
            val sd: Double = d.sign
            val uf: Float = oneF.ulp
            val ud: Double = oneD.ulp
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "MathExtensionProperties", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> (String, Int)? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                    return nil
                }
                return (ctx.interner.resolve(callee), arguments.count)
            }

            for expected in [
                "kk_math_abs_int",
                "kk_math_abs_long",
                "kk_math_abs_float",
                "kk_math_abs",
                "kk_math_sign_int",
                "kk_math_sign_long",
                "kk_math_sign_float",
                "kk_math_sign",
                "kk_float_ulp",
                "kk_double_ulp",
            ] {
                XCTAssertTrue(
                    calls.contains(where: { $0 == expected && $1 == 1 }),
                    "Expected \(expected) to lower with one receiver argument, got \(calls)"
                )
            }
        }
    }

    func testCodegenMathMinMaxOverloadsLowerToRuntimeHelpers() throws {
        let source = """
        import kotlin.math.*

        fun sample(
            d1: Double, d2: Double,
            f1: Float, f2: Float,
            i1: Int, i2: Int,
            l1: Long, l2: Long,
            ui1: UInt, ui2: UInt,
            ul1: ULong, ul2: ULong
        ) {
            val maxD = max(d1, d2)
            val maxF = max(f1, f2)
            val maxI = max(i1, i2)
            val maxL = max(l1, l2)
            val maxUI = max(ui1, ui2)
            val maxUL = max(ul1, ul2)
            val minD = min(d1, d2)
            val minF = min(f1, f2)
            val minI = min(i1, i2)
            val minL = min(l1, l2)
            val minUI = min(ui1, ui2)
            val minUL = min(ul1, ul2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "MathMinMaxOverloads", emit: .kirDump)
            try runToLowering(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "sample", in: module, interner: ctx.interner)
            let calls = body.compactMap { instruction -> (String, Int)? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                    return nil
                }
                return (ctx.interner.resolve(callee), arguments.count)
            }

            for expected in [
                "kk_math_max",
                "kk_math_max_float",
                "kk_math_max_int",
                "kk_math_max_long",
                "kk_math_max_uint",
                "kk_math_max_ulong",
                "kk_math_min",
                "kk_math_min_float",
                "kk_math_min_int",
                "kk_math_min_long",
                "kk_math_min_uint",
                "kk_math_min_ulong",
            ] {
                XCTAssertTrue(
                    calls.contains(where: { $0 == expected && $1 == 2 }),
                    "Expected \(expected) to lower with two arguments, got \(calls)"
                )
            }
        }
    }
}
