#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct MathAPITargetInventoryTests {
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
            "fun Double.IEEErem(Double): Double",
            "fun Float.IEEErem(Float): Float",
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

    // KSP-635: migrated to Sources/CompilerCore/Stdlib/kotlin/math/Math.kt.
    private static let sourceBackedSignatures: Set<String> = Set([
        "val E: Double",
        "val PI: Double",
        "val Double.absoluteValue: Double",
        "val Float.absoluteValue: Float",
        "val Int.absoluteValue: Int",
        "val Long.absoluteValue: Long",
        "val Double.sign: Double",
        "val Float.sign: Float",
        "val Int.sign: Int",
        "val Long.sign: Int",
        "fun abs(Double): Double",
        "fun abs(Float): Float",
        "fun abs(Int): Int",
        "fun abs(Long): Long",
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
        "fun sign(Double): Double",
        "fun sign(Float): Float",
        "val Double.ulp: Double",
        "val Float.ulp: Float",
        "fun Double.nextDown(): Double",
        "fun Float.nextDown(): Float",
        "fun Double.nextUp(): Double",
        "fun Float.nextUp(): Float",
        "fun Double.roundToInt(): Int",
        "fun Float.roundToInt(): Int",
        "fun Double.roundToLong(): Long",
        "fun Float.roundToLong(): Long",
        "fun ceil(Double): Double",
        "fun ceil(Float): Float",
        "fun floor(Double): Double",
        "fun floor(Float): Float",
        "fun round(Double): Double",
        "fun round(Float): Float",
        "fun truncate(Double): Double",
        "fun truncate(Float): Float",
        "fun Double.withSign(Double): Double",
        "fun Double.withSign(Int): Double",
        "fun Float.withSign(Float): Float",
        "fun Float.withSign(Int): Float",
        "fun Double.IEEErem(Double): Double",
        "fun Float.IEEErem(Float): Float",
        "fun Double.nextTowards(Double): Double",
        "fun Float.nextTowards(Float): Float",
        "fun Double.pow(Double): Double",
        "fun Float.pow(Float): Float",
        "fun Double.pow(Int): Double",
        "fun Float.pow(Int): Float",
        "fun expm1(Double): Double",
        "fun expm1(Float): Float",
        "fun ln1p(Double): Double",
        "fun ln1p(Float): Float",
    ]
    + unaryFloatingSignatures([
        "acos", "acosh", "asin", "asinh", "atan", "atanh",
        "cbrt", "cos", "cosh", "exp", "ln", "log10", "log2",
        "sin", "sinh", "sqrt", "tan", "tanh",
    ])
    + binaryFloatingSignatures(["atan2", "hypot", "log"])
    )

    private static let implementedLinksBySignature: [String: String] = [:]

    private static let knownGapSignaturesByTodo: [String: Set<String>] = [:]

    private static let unofficialRoundingHelperNames: Set<String> = [
        "roundUp", "roundDown", "roundCeiling", "roundFloor",
        "roundHalfUp", "roundHalfDown", "roundHalfEven", "roundUnnecessary",
    ]

    @Test func testTargetInventoryHasExpectedShape() {
        #expect(Self.targetSignatureList.count == Self.targetSignatures.count)
        #expect(Self.targetSignatures.count == 104)
        #expect(Self.targetSignatures.filter { $0.hasPrefix("val ") }.count == 12)
    }

    @Test func testCurrentSyntheticMathNamesAreOfficialTargets() throws {
        let (sema, interner) = try sharedSema()
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

        let publicNames = currentNames.filter { symbolName in
            // Internal stdlib bridge helpers (e.g. __kkMathCeil) are not part
            // of the public kotlin.math surface and should not be counted.
            guard let symbol = Self.symbol(forName: symbolName, sema: sema, interner: interner) else { return true }
            return symbol.visibility == .public
        }
        #expect(publicNames.subtracting(Self.targetNames).sorted() == [])
    }

    private static func symbol(forName name: String, sema: SemaModule, interner: StringInterner) -> SemanticSymbol? {
        let mathPrefix = ["kotlin", "math"].map { interner.intern($0) }
        let symbolName = interner.intern(name)
        return sema.symbols.allSymbols().first { symbol in
            symbol.fqName == mathPrefix + [symbolName]
        }
    }

    @Test func testUnofficialRoundingHelpersAreNotPublished() throws {
        let (sema, interner) = try sharedSema()
        let mathPrefix = ["kotlin", "math"].map { interner.intern($0) }
        for name in Self.unofficialRoundingHelperNames.sorted() {
            let fqName = mathPrefix + [interner.intern(name)]
            let v = sema.symbols.lookupAll(fqName: fqName).isEmpty
            #expect(v,
                "\(name) should not be published as kotlin.math surface"
            )
        }
    }

    @Test func testImplementedInventoryEntriesResolveToSyntheticLinks() throws {
        let (sema, interner) = try sharedSema()
        let mathPrefix = ["kotlin", "math"].map { interner.intern($0) }
        for (signature, expectedLink) in Self.implementedLinksBySignature {
            let name = Self.declarationName(signature)
            let symbols = sema.symbols.lookupAll(fqName: mathPrefix + [interner.intern(name)])
            let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            #expect(
                links.contains(expectedLink),
                "Expected \(signature) to resolve to \(expectedLink), got \(links.sorted())"
            )
        }
    }

    @Test func testSourceBackedInventoryEntriesHaveNoRuntimeMathLink() throws {
        let (sema, interner) = try sharedSema()
        let mathPrefix = ["kotlin", "math"].map { interner.intern($0) }
        for signature in Self.sourceBackedSignatures.sorted() {
            let name = Self.declarationName(signature)
            let symbols = sema.symbols.lookupAll(fqName: mathPrefix + [interner.intern(name)])
            #expect(!symbols.isEmpty, "Expected \(signature) to be declared by kotlin/math/Math.kt")
            let mathRuntimeLinks = symbols
                .compactMap { sema.symbols.externalLinkName(for: $0) }
                .filter { $0.hasPrefix("__kk_math_") }
            #expect(
                mathRuntimeLinks.isEmpty,
                "Expected \(signature) to stay Kotlin-source backed, got \(mathRuntimeLinks.sorted())"
            )
        }
    }

    @Test func testEIsPublicDoubleConstWithExactBitPattern() throws {
        let (sema, interner) = try sharedSema()
        let eFQName = ["kotlin", "math", "E"].map { interner.intern($0) }
        let eSymbol = try #require(sema.symbols.lookup(fqName: eFQName))
        let eInfo = try #require(sema.symbols.symbol(eSymbol))

        #expect(eInfo.kind == .property)
        #expect(eInfo.visibility == .public)
        #expect(!eInfo.flags.contains(.mutable))
        #expect(eInfo.flags.contains(.constValue))
        #expect(sema.symbols.propertyType(for: eSymbol) == sema.types.make(.primitive(.double, .nonNull)))

        guard case let .doubleLiteral(value) = sema.symbols.constValueExprKind(for: eSymbol) else {
            Issue.record("Expected kotlin.math.E to carry a double literal constant")
            return
        }
        #expect(value.bitPattern == 0x4005BF0A8B145769)
    }

    @Test func testPIIsPublicDoubleConstWithExactBitPattern() throws {
        let (sema, interner) = try sharedSema()
        let piFQName = ["kotlin", "math", "PI"].map { interner.intern($0) }
        let piSymbol = try #require(sema.symbols.lookup(fqName: piFQName))
        let piInfo = try #require(sema.symbols.symbol(piSymbol))

        #expect(piInfo.kind == .property)
        #expect(piInfo.visibility == .public)
        #expect(!piInfo.flags.contains(.mutable))
        #expect(piInfo.flags.contains(.constValue))
        #expect(sema.symbols.propertyType(for: piSymbol) == sema.types.make(.primitive(.double, .nonNull)))

        guard case let .doubleLiteral(value) = sema.symbols.constValueExprKind(for: piSymbol) else {
            Issue.record("Expected kotlin.math.PI to carry a double literal constant")
            return
        }
        #expect(value.bitPattern == 0x400921FB54442D18)
    }

    @Test func testKnownGapsCoverEveryUnimplementedTargetSignature() {
        let implemented = Set(Self.implementedLinksBySignature.keys).union(Self.sourceBackedSignatures)
        let gaps = Self.knownGapSignaturesByTodo.values.reduce(into: Set<String>()) { result, signatures in
            result.formUnion(signatures)
        }

        #expect(Self.targetSignatures.subtracting(implemented) == gaps)
        let v = Self.knownGapSignaturesByTodo.keys.allSatisfy { $0.hasPrefix("STDLIB-MATH-") }
        #expect(v)
    }

    private static var targetNames: Set<String> {
        Set(targetSignatures.map(declarationName))
    }

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

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }
}
#endif
