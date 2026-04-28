@testable import CompilerCore
import XCTest

final class MathAPITargetInventoryTests: XCTestCase {
    private static let targetSignatureList: [String] =
        [
            "val Double.absoluteValue: Double",
            "val Float.absoluteValue: Float",
            "val Int.absoluteValue: Int",
            "val Long.absoluteValue: Long",
            "val E: Double",
            "val PI: Double",
            "val Double.sign: Double",
            "val Float.sign: Float",
            "val Int.sign: Int",
            "val Long.sign: Int",
            "val Double.ulp: Double",
            "val Float.ulp: Float",
            "fun abs(Double): Double",
            "fun abs(Float): Float",
            "fun abs(Int): Int",
            "fun abs(Long): Long",
            "fun IEEErem(Double, Double): Double",
            "fun IEEErem(Float, Float): Float",
            "fun max(Double, Double): Double",
            "fun max(Float, Float): Float",
            "fun max(Int, Int): Int",
            "fun max(Long, Long): Long",
            "fun max(UInt, UInt): UInt",
            "fun max(ULong, ULong): ULong",
            "fun min(Double, Double): Double",
            "fun min(Float, Float): Float",
            "fun min(Int, Int): Int",
            "fun min(Long, Long): Long",
            "fun min(UInt, UInt): UInt",
            "fun min(ULong, ULong): ULong",
            "fun Double.nextDown(): Double",
            "fun Float.nextDown(): Float",
            "fun Double.nextTowards(Double): Double",
            "fun Float.nextTowards(Float): Float",
            "fun Double.nextUp(): Double",
            "fun Float.nextUp(): Float",
            "fun Double.pow(Double): Double",
            "fun Float.pow(Float): Float",
            "fun Double.pow(Int): Double",
            "fun Float.pow(Int): Float",
            "fun Double.roundToInt(): Int",
            "fun Float.roundToInt(): Int",
            "fun Double.roundToLong(): Long",
            "fun Float.roundToLong(): Long",
            "fun sign(Double): Double",
            "fun sign(Float): Float",
            "fun Double.withSign(Double): Double",
            "fun Double.withSign(Int): Double",
            "fun Float.withSign(Float): Float",
            "fun Float.withSign(Int): Float",
        ]
        + unaryFloatingSignatures([
            "acos", "acosh", "asin", "asinh", "atan", "atanh",
            "cbrt", "ceil", "cos", "cosh", "exp", "expm1",
            "floor", "ln", "ln1p", "log10", "log2", "round",
            "sin", "sinh", "sqrt", "tan", "tanh", "truncate",
        ])
        + binaryFloatingSignatures(["atan2", "hypot", "log"])

    private static let targetSignatures = Set(targetSignatureList)

    private static let implementedLinksBySignature: [String: String] = {
        var result: [String: String] = [
            "val E: Double": "kk_math_E",
            "val PI: Double": "kk_math_PI",
            "val Double.absoluteValue: Double": "kk_math_abs",
            "val Float.absoluteValue: Float": "kk_math_abs_float",
            "val Int.absoluteValue: Int": "kk_math_abs_int",
            "val Long.absoluteValue: Long": "kk_math_abs_long",
            "val Double.sign: Double": "kk_math_sign",
            "val Float.sign: Float": "kk_math_sign_float",
            "val Int.sign: Int": "kk_math_sign_int",
            "val Long.sign: Int": "kk_math_sign_long",
            "val Double.ulp: Double": "kk_double_ulp",
            "val Float.ulp: Float": "kk_float_ulp",
            "fun abs(Double): Double": "kk_math_abs",
            "fun abs(Float): Float": "kk_math_abs_float",
            "fun abs(Int): Int": "kk_math_abs_int",
            "fun abs(Long): Long": "kk_math_abs_long",
            "fun IEEErem(Double, Double): Double": "kk_math_IEEErem",
            "fun IEEErem(Float, Float): Float": "kk_math_IEEErem_float",
            "fun max(Double, Double): Double": "kk_math_max",
            "fun max(Float, Float): Float": "kk_math_max_float",
            "fun max(Int, Int): Int": "kk_math_max_int",
            "fun max(Long, Long): Long": "kk_math_max_long",
            "fun max(UInt, UInt): UInt": "kk_math_max_uint",
            "fun max(ULong, ULong): ULong": "kk_math_max_ulong",
            "fun min(Double, Double): Double": "kk_math_min",
            "fun min(Float, Float): Float": "kk_math_min_float",
            "fun min(Int, Int): Int": "kk_math_min_int",
            "fun min(Long, Long): Long": "kk_math_min_long",
            "fun min(UInt, UInt): UInt": "kk_math_min_uint",
            "fun min(ULong, ULong): ULong": "kk_math_min_ulong",
            "fun Double.nextDown(): Double": "kk_double_nextDown",
            "fun Float.nextDown(): Float": "kk_float_nextDown",
            "fun Double.nextTowards(Double): Double": "kk_math_nextTowards",
            "fun Float.nextTowards(Float): Float": "kk_math_nextTowards_float",
            "fun Double.nextUp(): Double": "kk_double_nextUp",
            "fun Float.nextUp(): Float": "kk_float_nextUp",
            "fun Double.pow(Double): Double": "kk_math_pow",
            "fun Float.pow(Float): Float": "kk_math_pow_float",
            "fun Double.pow(Int): Double": "kk_math_pow_int",
            "fun Float.pow(Int): Float": "kk_math_pow_float_int",
            "fun expm1(Double): Double": "kk_math_expm1",
            "fun expm1(Float): Float": "kk_math_expm1_float",
            "fun ln1p(Double): Double": "kk_math_ln1p",
            "fun ln1p(Float): Float": "kk_math_ln1p_float",
            "fun Double.roundToInt(): Int": "kk_double_roundToInt",
            "fun Float.roundToInt(): Int": "kk_float_roundToInt",
            "fun Double.roundToLong(): Long": "kk_double_roundToLong",
            "fun Float.roundToLong(): Long": "kk_float_roundToLong",
            "fun sign(Double): Double": "kk_math_sign",
            "fun sign(Float): Float": "kk_math_sign_float",
            "fun Double.withSign(Double): Double": "kk_math_withSign",
            "fun Double.withSign(Int): Double": "kk_math_withSign_int",
            "fun Float.withSign(Float): Float": "kk_math_withSign_float",
            "fun Float.withSign(Int): Float": "kk_math_withSign_float_int",
        ]
        for (name, doubleLink, floatLink) in unaryFloatingLinks([
            ("acos", "kk_math_acos", "kk_math_acos_float"),
            ("acosh", "kk_math_acosh", "kk_math_acosh_float"),
            ("asin", "kk_math_asin", "kk_math_asin_float"),
            ("asinh", "kk_math_asinh", "kk_math_asinh_float"),
            ("atan", "kk_math_atan", "kk_math_atan_float"),
            ("atanh", "kk_math_atanh", "kk_math_atanh_float"),
            ("cbrt", "kk_math_cbrt", "kk_math_cbrt_float"),
            ("ceil", "kk_math_ceil", "kk_math_ceil_float"),
            ("cos", "kk_math_cos", "kk_math_cos_float"),
            ("cosh", "kk_math_cosh", "kk_math_cosh_float"),
            ("exp", "kk_math_exp", "kk_math_exp_float"),
            ("floor", "kk_math_floor", "kk_math_floor_float"),
            ("ln", "kk_math_ln", "kk_math_ln_float"),
            ("log10", "kk_math_log10", "kk_math_log10_float"),
            ("log2", "kk_math_log2", "kk_math_log2_float"),
            ("round", "kk_math_round", "kk_math_round_float"),
            ("sin", "kk_math_sin", "kk_math_sin_float"),
            ("sinh", "kk_math_sinh", "kk_math_sinh_float"),
            ("sqrt", "kk_math_sqrt", "kk_math_sqrt_float"),
            ("tan", "kk_math_tan", "kk_math_tan_float"),
            ("tanh", "kk_math_tanh", "kk_math_tanh_float"),
            ("truncate", "kk_math_truncate", "kk_math_truncate_float"),
        ]) {
            result["fun \(name)(Double): Double"] = doubleLink
            result["fun \(name)(Float): Float"] = floatLink
        }
        for (name, doubleLink, floatLink) in [
            ("atan2", "kk_math_atan2", "kk_math_atan2_float"),
            ("hypot", "kk_math_hypot", "kk_math_hypot_float"),
            ("log", "kk_math_log", "kk_math_log_float"),
        ] {
            result["fun \(name)(Double, Double): Double"] = doubleLink
            result["fun \(name)(Float, Float): Float"] = floatLink
        }
        return result
    }()

    private static let knownGapSignaturesByTodo: [String: Set<String>] = [:]

    private static let unofficialRoundingHelperNames: Set<String> = [
        "roundUp", "roundDown", "roundCeiling", "roundFloor",
        "roundHalfUp", "roundHalfDown", "roundHalfEven", "roundUnnecessary",
    ]

    func testTargetInventoryHasExpectedShape() {
        XCTAssertEqual(Self.targetSignatureList.count, Self.targetSignatures.count)
        XCTAssertEqual(Self.targetSignatures.count, 104)
        XCTAssertEqual(Self.targetSignatures.filter { $0.hasPrefix("val ") }.count, 12)
    }

    func testCurrentSyntheticMathNamesAreOfficialTargets() throws {
        let (sema, interner) = try makeSema()
        let mathPrefix = ["kotlin", "math"].map { interner.intern($0) }
        let currentNames = Set(sema.symbols.allSymbols().compactMap { symbol -> String? in
            guard symbol.kind == .function || symbol.kind == .property,
                  symbol.fqName.count == mathPrefix.count + 1,
                  Array(symbol.fqName.prefix(mathPrefix.count)) == mathPrefix
            else {
                return nil
            }
            return interner.resolve(symbol.name)
        })

        XCTAssertEqual(currentNames.subtracting(Self.targetNames).sorted(), [])
    }

    func testUnofficialRoundingHelpersAreNotPublished() throws {
        let (sema, interner) = try makeSema()
        let mathPrefix = ["kotlin", "math"].map { interner.intern($0) }
        for name in Self.unofficialRoundingHelperNames.sorted() {
            let fqName = mathPrefix + [interner.intern(name)]
            XCTAssertTrue(
                sema.symbols.lookupAll(fqName: fqName).isEmpty,
                "\(name) should not be published as kotlin.math surface"
            )
        }
    }

    func testImplementedInventoryEntriesResolveToSyntheticLinks() throws {
        let (sema, interner) = try makeSema()
        let mathPrefix = ["kotlin", "math"].map { interner.intern($0) }
        for (signature, expectedLink) in Self.implementedLinksBySignature {
            let name = Self.declarationName(signature)
            let symbols = sema.symbols.lookupAll(fqName: mathPrefix + [interner.intern(name)])
            let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            XCTAssertTrue(
                links.contains(expectedLink),
                "Expected \(signature) to resolve to \(expectedLink), got \(links.sorted())"
            )
        }
    }

    func testKnownGapsCoverEveryUnimplementedTargetSignature() {
        let implemented = Set(Self.implementedLinksBySignature.keys)
        let gaps = Self.knownGapSignaturesByTodo.values.reduce(into: Set<String>()) { result, signatures in
            result.formUnion(signatures)
        }

        XCTAssertEqual(Self.targetSignatures.subtracting(implemented), gaps)
        XCTAssertTrue(Self.knownGapSignaturesByTodo.keys.allSatisfy { $0.hasPrefix("STDLIB-MATH-") })
    }

    private static var targetNames: Set<String> {
        Set(targetSignatures.map(declarationName))
    }

    private static let propertyNames: Set<String> = ["absoluteValue", "E", "PI", "sign", "ulp"]

    private static func unaryFloatingSignatures(_ names: [String]) -> [String] {
        names.flatMap { name in
            ["fun \(name)(Double): Double", "fun \(name)(Float): Float"]
        }
    }

    private static func binaryFloatingSignatures(_ names: [String]) -> [String] {
        names.flatMap { name in
            ["fun \(name)(Double, Double): Double", "fun \(name)(Float, Float): Float"]
        }
    }

    private static func unaryFloatingLinks(_ entries: [(String, String, String)]) -> [(String, String, String)] {
        entries
    }

    private static func declarationName(_ signature: String) -> String {
        var remainder = signature
        if remainder.hasPrefix("val ") {
            remainder.removeFirst("val ".count)
            let declaration = remainder.split(separator: ":", maxSplits: 1)[0].trimmingCharacters(in: .whitespaces)
            return declaration.split(separator: ".").last.map(String.init) ?? declaration
        }
        if remainder.hasPrefix("fun ") {
            remainder.removeFirst("fun ".count)
            let declaration = remainder.split(separator: "(", maxSplits: 1)[0].trimmingCharacters(in: .whitespaces)
            return declaration.split(separator: ".").last.map(String.init) ?? declaration
        }
        return signature
    }

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }
}
