@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-MATH-001 / STDLIB-MATH-002
// Sema-level overload resolution tests for kotlin.math.
// Verifies that the correct overload is selected for each argument type
// (Double, Float, Int, Long) across every overload family.
// No runtime edits; these tests only exercise the sema pipeline.

final class MathOverloadResolutionTests: XCTestCase {

    // MARK: - Helpers

    private func resolvedLink(
        forCall callName: String,
        withSource source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String? {
        var result: String? = nil
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Unexpected sema error for '\(callName)'", file: file, line: line)
            let ast = try XCTUnwrap(ctx.ast, file: file, line: line)
            let sema = try XCTUnwrap(ctx.sema, file: file, line: line)
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID) else { continue }
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr),
                      ctx.interner.resolve(calleeName) == callName
                else { continue }
                if let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee {
                    result = sema.symbols.externalLinkName(for: chosenCallee)
                }
                break
            }
        }
        return result
    }

    private func resolvedLinkForFirstMatchingCall(
        names: Set<String>,
        withSource source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: String] {
        var results: [String: String] = [:]
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Unexpected sema error", file: file, line: line)
            let ast = try XCTUnwrap(ctx.ast, file: file, line: line)
            let sema = try XCTUnwrap(ctx.sema, file: file, line: line)
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID) else { continue }
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { continue }
                let name = ctx.interner.resolve(calleeName)
                guard names.contains(name), results[name] == nil else { continue }
                if let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee {
                    if let link = sema.symbols.externalLinkName(for: chosenCallee) {
                        results[name] = link
                    }
                }
            }
        }
        return results
    }

    // MARK: - abs family (Int / Long / Double / Float)

    func testAbsIntOverload() throws {
        let source = "fun f(x: Int): Int = abs(x)"
        let link = try resolvedLink(forCall: "abs", withSource: source)
        XCTAssertEqual(link, "kk_math_abs_int")
    }

    func testAbsLongOverload() throws {
        let source = "fun f(x: Long): Long = abs(x)"
        let link = try resolvedLink(forCall: "abs", withSource: source)
        XCTAssertEqual(link, "kk_math_abs_long")
    }

    func testAbsDoubleOverload() throws {
        let source = "fun f(x: Double): Double = abs(x)"
        let link = try resolvedLink(forCall: "abs", withSource: source)
        XCTAssertEqual(link, "kk_math_abs")
    }

    func testAbsFloatOverload() throws {
        let source = "fun f(x: Float): Float = abs(x)"
        let link = try resolvedLink(forCall: "abs", withSource: source)
        XCTAssertEqual(link, "kk_math_abs_float")
    }

    // MARK: - sqrt family (Double / Float)

    func testSqrtDoubleOverload() throws {
        let source = "fun f(x: Double): Double = sqrt(x)"
        let link = try resolvedLink(forCall: "sqrt", withSource: source)
        XCTAssertEqual(link, "kk_math_sqrt")
    }

    func testSqrtFloatOverload() throws {
        let source = "fun f(x: Float): Float = sqrt(x)"
        let link = try resolvedLink(forCall: "sqrt", withSource: source)
        XCTAssertEqual(link, "kk_math_sqrt_float")
    }

    // MARK: - pow family (Double / Float, floating and Int exponents)

    func testPowDoubleOverload() throws {
        let source = "fun f(x: Double, y: Double): Double = pow(x, y)"
        let link = try resolvedLink(forCall: "pow", withSource: source)
        XCTAssertEqual(link, "kk_math_pow")
    }

    func testPowRemainingOverloads() throws {
        let cases: [(source: String, expectedLink: String)] = [
            ("fun f(x: Float, y: Float): Float = pow(x, y)", "kk_math_pow_float"),
            ("fun f(x: Double, n: Int): Double = pow(x, n)", "kk_math_pow_int"),
            ("fun f(x: Float, n: Int): Float = pow(x, n)", "kk_math_pow_float_int"),
        ]

        for testCase in cases {
            let link = try resolvedLink(forCall: "pow", withSource: testCase.source)
            XCTAssertEqual(link, testCase.expectedLink)
        }
    }

    func testIEEEremNextTowardsAndWithSignOverloads() throws {
        let cases: [(name: String, source: String, expectedLink: String)] = [
            ("IEEErem", "fun f(x: Double, y: Double): Double = IEEErem(x, y)", "kk_math_IEEErem"),
            ("IEEErem", "fun f(x: Float, y: Float): Float = IEEErem(x, y)", "kk_math_IEEErem_float"),
            ("nextTowards", "fun f(x: Double, y: Double): Double = nextTowards(x, y)", "kk_math_nextTowards"),
            ("nextTowards", "fun f(x: Float, y: Float): Float = nextTowards(x, y)", "kk_math_nextTowards_float"),
            ("withSign", "fun f(x: Double, y: Double): Double = withSign(x, y)", "kk_math_withSign"),
            ("withSign", "fun f(x: Double, sign: Int): Double = withSign(x, sign)", "kk_math_withSign_int"),
            ("withSign", "fun f(x: Float, y: Float): Float = withSign(x, y)", "kk_math_withSign_float"),
            ("withSign", "fun f(x: Float, sign: Int): Float = withSign(x, sign)", "kk_math_withSign_float_int"),
        ]

        for testCase in cases {
            let link = try resolvedLink(forCall: testCase.name, withSource: testCase.source)
            XCTAssertEqual(link, testCase.expectedLink)
        }
    }

    // MARK: - round / ceil / floor family (Double / Float)

    func testRoundDoubleOverload() throws {
        let source = "fun f(x: Double): Double = round(x)"
        let link = try resolvedLink(forCall: "round", withSource: source)
        XCTAssertEqual(link, "kk_math_round")
    }

    func testRoundFloatOverload() throws {
        let source = "fun f(x: Float): Float = round(x)"
        let link = try resolvedLink(forCall: "round", withSource: source)
        XCTAssertEqual(link, "kk_math_round_float")
    }

    func testCeilDoubleOverload() throws {
        let source = "fun f(x: Double): Double = ceil(x)"
        let link = try resolvedLink(forCall: "ceil", withSource: source)
        XCTAssertEqual(link, "kk_math_ceil")
    }

    func testCeilFloatOverload() throws {
        let source = "fun f(x: Float): Float = ceil(x)"
        let link = try resolvedLink(forCall: "ceil", withSource: source)
        XCTAssertEqual(link, "kk_math_ceil_float")
    }

    func testFloorDoubleOverload() throws {
        let source = "fun f(x: Double): Double = floor(x)"
        let link = try resolvedLink(forCall: "floor", withSource: source)
        XCTAssertEqual(link, "kk_math_floor")
    }

    func testFloorFloatOverload() throws {
        let source = "fun f(x: Float): Float = floor(x)"
        let link = try resolvedLink(forCall: "floor", withSource: source)
        XCTAssertEqual(link, "kk_math_floor_float")
    }

    // MARK: - Trig family (Double / Float): sin / cos / tan / asin / acos / atan

    func testTrigDoubleFamilyOverloads() throws {
        let source = """
        fun f(x: Double): Double {
            val a = sin(x)
            val b = cos(x)
            val c = tan(x)
            val d = asin(x)
            val e = acos(x)
            val f = atan(x)
            return a + b + c + d + e + f
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["sin", "cos", "tan", "asin", "acos", "atan"],
            withSource: source
        )
        XCTAssertEqual(links["sin"], "kk_math_sin")
        XCTAssertEqual(links["cos"], "kk_math_cos")
        XCTAssertEqual(links["tan"], "kk_math_tan")
        XCTAssertEqual(links["asin"], "kk_math_asin")
        XCTAssertEqual(links["acos"], "kk_math_acos")
        XCTAssertEqual(links["atan"], "kk_math_atan")
    }

    func testTrigFloatFamilyOverloads() throws {
        let source = """
        fun f(x: Float): Float {
            val a = sin(x)
            val b = cos(x)
            val c = tan(x)
            val d = asin(x)
            val e = acos(x)
            val f = atan(x)
            return a + b + c + d + e + f
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["sin", "cos", "tan", "asin", "acos", "atan"],
            withSource: source
        )
        XCTAssertEqual(links["sin"], "kk_math_sin_float")
        XCTAssertEqual(links["cos"], "kk_math_cos_float")
        XCTAssertEqual(links["tan"], "kk_math_tan_float")
        XCTAssertEqual(links["asin"], "kk_math_asin_float")
        XCTAssertEqual(links["acos"], "kk_math_acos_float")
        XCTAssertEqual(links["atan"], "kk_math_atan_float")
    }

    // MARK: - atan2 family (Double / Float)

    func testAtan2DoubleOverload() throws {
        let source = "fun f(y: Double, x: Double): Double = atan2(y, x)"
        let link = try resolvedLink(forCall: "atan2", withSource: source)
        XCTAssertEqual(link, "kk_math_atan2")
    }

    func testAtan2FloatOverload() throws {
        let source = "fun f(y: Float, x: Float): Float = atan2(y, x)"
        let link = try resolvedLink(forCall: "atan2", withSource: source)
        XCTAssertEqual(link, "kk_math_atan2_float")
    }

    // MARK: - Hyperbolic family (Double / Float): sinh / cosh / tanh

    func testHyperbolicDoubleFamilyOverloads() throws {
        let source = """
        fun f(x: Double): Double {
            val a = sinh(x)
            val b = cosh(x)
            val c = tanh(x)
            return a + b + c
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["sinh", "cosh", "tanh"],
            withSource: source
        )
        XCTAssertEqual(links["sinh"], "kk_math_sinh")
        XCTAssertEqual(links["cosh"], "kk_math_cosh")
        XCTAssertEqual(links["tanh"], "kk_math_tanh")
    }

    func testHyperbolicFloatFamilyOverloads() throws {
        let source = """
        fun f(x: Float): Float {
            val a = sinh(x)
            val b = cosh(x)
            val c = tanh(x)
            return a + b + c
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["sinh", "cosh", "tanh"],
            withSource: source
        )
        XCTAssertEqual(links["sinh"], "kk_math_sinh_float")
        XCTAssertEqual(links["cosh"], "kk_math_cosh_float")
        XCTAssertEqual(links["tanh"], "kk_math_tanh_float")
    }

    // MARK: - Inverse hyperbolic family (Double / Float): acosh / asinh / atanh

    func testInverseHyperbolicDoubleFamilyOverloads() throws {
        let source = """
        fun f(x: Double): Double {
            val a = acosh(x)
            val b = asinh(x)
            val c = atanh(x)
            return a + b + c
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["acosh", "asinh", "atanh"],
            withSource: source
        )
        XCTAssertEqual(links["acosh"], "kk_math_acosh")
        XCTAssertEqual(links["asinh"], "kk_math_asinh")
        XCTAssertEqual(links["atanh"], "kk_math_atanh")
    }

    func testInverseHyperbolicFloatFamilyOverloads() throws {
        let source = """
        fun f(x: Float): Float {
            val a = acosh(x)
            val b = asinh(x)
            val c = atanh(x)
            return a + b + c
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["acosh", "asinh", "atanh"],
            withSource: source
        )
        XCTAssertEqual(links["acosh"], "kk_math_acosh_float")
        XCTAssertEqual(links["asinh"], "kk_math_asinh_float")
        XCTAssertEqual(links["atanh"], "kk_math_atanh_float")
    }

    // MARK: - log / exp family (Double / Float)

    func testLogExpDoubleFamilyOverloads() throws {
        let source = """
        fun f(x: Double): Double {
            val a = exp(x)
            val b = ln(x)
            val c = log2(x)
            val d = log10(x)
            val e = expm1(x)
            val f = ln1p(x)
            return a + b + c + d + e + f
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["exp", "ln", "log2", "log10", "expm1", "ln1p"],
            withSource: source
        )
        XCTAssertEqual(links["exp"], "kk_math_exp")
        XCTAssertEqual(links["ln"], "kk_math_ln")
        XCTAssertEqual(links["log2"], "kk_math_log2")
        XCTAssertEqual(links["log10"], "kk_math_log10")
        XCTAssertEqual(links["expm1"], "kk_math_expm1")
        XCTAssertEqual(links["ln1p"], "kk_math_ln1p")
    }

    func testLogExpFloatFamilyOverloads() throws {
        let source = """
        fun f(x: Float): Float {
            val a = exp(x)
            val b = ln(x)
            val c = log2(x)
            val d = log10(x)
            val e = expm1(x)
            val f = ln1p(x)
            return a + b + c + d + e + f
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["exp", "ln", "log2", "log10", "expm1", "ln1p"],
            withSource: source
        )
        XCTAssertEqual(links["exp"], "kk_math_exp_float")
        XCTAssertEqual(links["ln"], "kk_math_ln_float")
        XCTAssertEqual(links["log2"], "kk_math_log2_float")
        XCTAssertEqual(links["log10"], "kk_math_log10_float")
        XCTAssertEqual(links["expm1"], "kk_math_expm1_float")
        XCTAssertEqual(links["ln1p"], "kk_math_ln1p_float")
    }

    func testLogTwoArgDoubleOverload() throws {
        let source = "fun f(x: Double, base: Double): Double = log(x, base)"
        let link = try resolvedLink(forCall: "log", withSource: source)
        XCTAssertEqual(link, "kk_math_log")
    }

    func testLogTwoArgFloatOverload() throws {
        let source = "fun f(x: Float, base: Float): Float = log(x, base)"
        let link = try resolvedLink(forCall: "log", withSource: source)
        XCTAssertEqual(link, "kk_math_log_float")
    }

    // MARK: - hypot family (Double / Float)

    func testHypotDoubleOverload() throws {
        let source = "fun f(x: Double, y: Double): Double = hypot(x, y)"
        let link = try resolvedLink(forCall: "hypot", withSource: source)
        XCTAssertEqual(link, "kk_math_hypot")
    }

    func testHypotFloatOverload() throws {
        let source = "fun f(x: Float, y: Float): Float = hypot(x, y)"
        let link = try resolvedLink(forCall: "hypot", withSource: source)
        XCTAssertEqual(link, "kk_math_hypot_float")
    }

    // MARK: - min / max family (Double / Float / Int / Long / UInt / ULong)

    func testMinMaxOverloadMatrix() throws {
        let cases: [(name: String, type: String, expectedLink: String)] = [
            ("max", "Double", "kk_math_max"),
            ("max", "Float", "kk_math_max_float"),
            ("max", "Int", "kk_math_max_int"),
            ("max", "Long", "kk_math_max_long"),
            ("max", "UInt", "kk_math_max_uint"),
            ("max", "ULong", "kk_math_max_ulong"),
            ("min", "Double", "kk_math_min"),
            ("min", "Float", "kk_math_min_float"),
            ("min", "Int", "kk_math_min_int"),
            ("min", "Long", "kk_math_min_long"),
            ("min", "UInt", "kk_math_min_uint"),
            ("min", "ULong", "kk_math_min_ulong"),
        ]

        for testCase in cases {
            let source = "fun f(a: \(testCase.type), b: \(testCase.type)): \(testCase.type) = \(testCase.name)(a, b)"
            let link = try resolvedLink(forCall: testCase.name, withSource: source)
            XCTAssertEqual(
                link,
                testCase.expectedLink,
                "\(testCase.name)(\(testCase.type), \(testCase.type)) should resolve to \(testCase.expectedLink)"
            )
        }
    }

    // MARK: - cbrt family (Double / Float)

    func testCbrtDoubleOverload() throws {
        let source = "fun f(x: Double): Double = cbrt(x)"
        let link = try resolvedLink(forCall: "cbrt", withSource: source)
        XCTAssertEqual(link, "kk_math_cbrt")
    }

    func testCbrtFloatOverload() throws {
        let source = "fun f(x: Float): Float = cbrt(x)"
        let link = try resolvedLink(forCall: "cbrt", withSource: source)
        XCTAssertEqual(link, "kk_math_cbrt_float")
    }

    // MARK: - sign family (Double / Float)

    func testSignDoubleOverload() throws {
        let source = "fun f(x: Double): Double = sign(x)"
        let link = try resolvedLink(forCall: "sign", withSource: source)
        XCTAssertEqual(link, "kk_math_sign")
    }

    func testSignFloatOverload() throws {
        let source = "fun f(x: Float): Float = sign(x)"
        let link = try resolvedLink(forCall: "sign", withSource: source)
        XCTAssertEqual(link, "kk_math_sign_float")
    }

    // MARK: - truncate family (Double / Float)

    func testTruncateDoubleOverload() throws {
        let source = "fun f(x: Double): Double = truncate(x)"
        let link = try resolvedLink(forCall: "truncate", withSource: source)
        XCTAssertEqual(link, "kk_math_truncate")
    }

    func testTruncateFloatOverload() throws {
        let source = "fun f(x: Float): Float = truncate(x)"
        let link = try resolvedLink(forCall: "truncate", withSource: source)
        XCTAssertEqual(link, "kk_math_truncate_float")
    }

    // MARK: - roundToInt / roundToLong (Double / Float)

    func testRoundToIntDoubleOverload() throws {
        let source = "fun f(x: Double): Int = roundToInt(x)"
        let link = try resolvedLink(forCall: "roundToInt", withSource: source)
        XCTAssertEqual(link, "kk_double_roundToInt")
    }

    func testRoundToIntFloatOverload() throws {
        let source = "fun f(x: Float): Int = roundToInt(x)"
        let link = try resolvedLink(forCall: "roundToInt", withSource: source)
        XCTAssertEqual(link, "kk_float_roundToInt")
    }

    func testRoundToLongDoubleOverload() throws {
        let source = "fun f(x: Double): Long = roundToLong(x)"
        let link = try resolvedLink(forCall: "roundToLong", withSource: source)
        XCTAssertEqual(link, "kk_double_roundToLong")
    }

    func testRoundToLongFloatOverload() throws {
        let source = "fun f(x: Float): Long = roundToLong(x)"
        let link = try resolvedLink(forCall: "roundToLong", withSource: source)
        XCTAssertEqual(link, "kk_float_roundToLong")
    }

    // MARK: - IEEE 754 rounding mode convenience helpers (Double / Float)

    func testIEEERoundingModeDoubleOverloads() throws {
        let source = """
        fun f(x: Double): Double {
            val a = roundUp(x)
            val b = roundDown(x)
            val c = roundHalfEven(x)
            return a + b + c
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["roundUp", "roundDown", "roundHalfEven"],
            withSource: source
        )
        XCTAssertEqual(links["roundUp"], "kk_math_round_up")
        XCTAssertEqual(links["roundDown"], "kk_math_round_down")
        XCTAssertEqual(links["roundHalfEven"], "kk_math_round_half_even")
    }

    func testIEEERoundingModeFloatOverloads() throws {
        let source = """
        fun f(x: Float): Float {
            val a = roundUp(x)
            val b = roundDown(x)
            val c = roundHalfEven(x)
            return a + b + c
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["roundUp", "roundDown", "roundHalfEven"],
            withSource: source
        )
        XCTAssertEqual(links["roundUp"], "kk_math_round_up_float")
        XCTAssertEqual(links["roundDown"], "kk_math_round_down_float")
        XCTAssertEqual(links["roundHalfEven"], "kk_math_round_half_even_float")
    }

    // MARK: - Mixed-type overload disambiguation (Int vs Double vs Float in same scope)

    func testAbsSelectsDistinctOverloadsForDifferentTypes() throws {
        let source = """
        fun f(i: Int, l: Long, d: Double, flt: Float) {
            val ai = abs(i)
            val al = abs(l)
            val ad = abs(d)
            val af = abs(flt)
        }
        """
        var results: [(String, Int)] = []
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError)
            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr),
                      ctx.interner.resolve(calleeName) == "abs",
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let link = sema.symbols.externalLinkName(for: chosenCallee)
                else { continue }
                results.append((link, exprIndex))
            }
        }
        let links = results.map(\.0)
        XCTAssertTrue(links.contains("kk_math_abs_int"), "Int abs should resolve to kk_math_abs_int")
        XCTAssertTrue(links.contains("kk_math_abs_long"), "Long abs should resolve to kk_math_abs_long")
        XCTAssertTrue(links.contains("kk_math_abs"), "Double abs should resolve to kk_math_abs")
        XCTAssertTrue(links.contains("kk_math_abs_float"), "Float abs should resolve to kk_math_abs_float")
        // All 4 calls must pick distinct link names
        XCTAssertEqual(Set(links).count, 4, "Each abs overload should resolve to a different runtime symbol")
    }

    func testSqrtSelectsDistinctOverloadsForDoubleAndFloat() throws {
        let source = """
        fun f(d: Double, flt: Float) {
            val sd = sqrt(d)
            val sf = sqrt(flt)
        }
        """
        var links: [String] = []
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError)
            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr),
                      ctx.interner.resolve(calleeName) == "sqrt",
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let link = sema.symbols.externalLinkName(for: chosenCallee)
                else { continue }
                links.append(link)
            }
        }
        XCTAssertTrue(links.contains("kk_math_sqrt"), "Double sqrt should resolve to kk_math_sqrt")
        XCTAssertTrue(links.contains("kk_math_sqrt_float"), "Float sqrt should resolve to kk_math_sqrt_float")
        XCTAssertEqual(links.count, 2)
    }
}
