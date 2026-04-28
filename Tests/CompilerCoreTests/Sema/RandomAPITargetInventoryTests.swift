@testable import CompilerCore
import Foundation
import XCTest

final class RandomAPITargetInventoryTests: XCTestCase {
    private static let commonTargetSignatures: Set<String> = [
        "val Random.Default: Random",
        "fun Random(seed: Int): Random",
        "fun Random(seed: Long): Random",
        "fun Random.nextBits(Int): Int",
        "fun Random.nextBoolean(): Boolean",
        "fun Random.nextBytes(ByteArray): ByteArray",
        "fun Random.nextBytes(Int): ByteArray",
        "fun Random.nextBytes(ByteArray, Int, Int): ByteArray",
        "fun Random.nextDouble(): Double",
        "fun Random.nextDouble(Double): Double",
        "fun Random.nextDouble(Double, Double): Double",
        "fun Random.nextFloat(): Float",
        "fun Random.nextInt(): Int",
        "fun Random.nextInt(Int): Int",
        "fun Random.nextInt(Int, Int): Int",
        "fun Random.nextInt(IntRange): Int",
        "fun Random.nextLong(): Long",
        "fun Random.nextLong(Long): Long",
        "fun Random.nextLong(Long, Long): Long",
        "fun Random.nextLong(LongRange): Long",
        "fun Random.nextUBytes(Int): UByteArray",
        "fun Random.nextUBytes(UByteArray): UByteArray",
        "fun Random.nextUBytes(UByteArray, Int, Int): UByteArray",
        "fun Random.nextUInt(): UInt",
        "fun Random.nextUInt(UInt): UInt",
        "fun Random.nextUInt(UInt, UInt): UInt",
        "fun Random.nextUInt(UIntRange): UInt",
        "fun Random.nextULong(): ULong",
        "fun Random.nextULong(ULong): ULong",
        "fun Random.nextULong(ULong, ULong): ULong",
        "fun Random.nextULong(ULongRange): ULong",
    ]

    private static let implementedLinks: [String: String] = [
        "val Random.Default: Random": "kk_random_default",
        "fun Random(seed: Int): Random": "kk_random_create_seeded",
        "fun Random(seed: Long): Random": "kk_random_create_seeded",
        "fun Random.nextBits(Int): Int": "kk_random_nextBits",
        "fun Random.nextBoolean(): Boolean": "kk_random_nextBoolean",
        "fun Random.nextBytes(ByteArray): ByteArray": "kk_random_nextBytes",
        "fun Random.nextBytes(Int): ByteArray": "kk_random_nextBytes_size",
        "fun Random.nextBytes(ByteArray, Int, Int): ByteArray": "kk_random_nextBytes_range",
        "fun Random.nextDouble(): Double": "kk_random_nextDouble",
        "fun Random.nextDouble(Double): Double": "kk_random_nextDouble_until",
        "fun Random.nextDouble(Double, Double): Double": "kk_random_nextDouble_range",
        "fun Random.nextFloat(): Float": "kk_random_nextFloat",
        "fun Random.nextInt(): Int": "kk_random_nextInt",
        "fun Random.nextInt(Int): Int": "kk_random_nextInt_until",
        "fun Random.nextInt(Int, Int): Int": "kk_random_nextInt_range",
        "fun Random.nextInt(IntRange): Int": "kk_random_nextInt_intRange",
        "fun Random.nextLong(): Long": "kk_random_nextLong",
        "fun Random.nextLong(Long): Long": "kk_random_nextLong_until",
        "fun Random.nextLong(Long, Long): Long": "kk_random_nextLong_range",
        "fun Random.nextLong(LongRange): Long": "kk_random_nextLong_rangeObject",
        "fun Random.nextUBytes(Int): UByteArray": "kk_random_nextUBytes_size",
        "fun Random.nextUBytes(UByteArray): UByteArray": "kk_random_nextUBytes",
        "fun Random.nextUBytes(UByteArray, Int, Int): UByteArray": "kk_random_nextUBytes_range",
        "fun Random.nextULong(): ULong": "kk_random_nextULong",
        "fun Random.nextULong(ULong): ULong": "kk_random_nextULong_until",
        "fun Random.nextULong(ULong, ULong): ULong": "kk_random_nextULong_range",
        "fun Random.nextULong(ULongRange): ULong": "kk_random_nextULong_ulongRange",
    ]

    private static let knownGaps: [String: String] = [
        "fun Random.nextUInt(): UInt": "STDLIB-RANDOM-012",
        "fun Random.nextUInt(UInt): UInt": "STDLIB-RANDOM-012",
        "fun Random.nextUInt(UInt, UInt): UInt": "STDLIB-RANDOM-012",
        "fun Random.nextUInt(UIntRange): UInt": "STDLIB-RANDOM-012",
    ]

    private static let jvmOnlyTargets: Set<String> = [
        "fun Random.asJavaRandom(): java.util.Random",
        "fun java.util.Random.asKotlinRandom(): Random",
    ]

    private static let knownNonOfficialPublishedLinks: Set<String> = [
        "kk_random_nextFloat_until",
        "kk_random_nextFloat_range",
    ]

    func testTargetInventoryHasExpectedShape() {
        XCTAssertEqual(Self.commonTargetSignatures.count, 31)
        XCTAssertEqual(Self.implementedLinks.count, 27)
        XCTAssertEqual(Self.knownGaps.count, 4)
        XCTAssertEqual(Self.jvmOnlyTargets.count, 2)
    }

    func testKnownGapsCoverEveryUnimplementedCommonTargetSignature() {
        let implemented = Set(Self.implementedLinks.keys)
        let gaps = Set(Self.knownGaps.keys)
        XCTAssertTrue(implemented.isSubset(of: Self.commonTargetSignatures))
        XCTAssertTrue(gaps.isSubset(of: Self.commonTargetSignatures))

        let uncovered = Self.commonTargetSignatures
            .subtracting(implemented)
            .subtracting(gaps)
        XCTAssertTrue(
            uncovered.isEmpty,
            "Unclassified kotlin.random targets: \(uncovered.sorted())"
        )
    }

    func testImplementedInventoryEntriesResolveToSyntheticLinks() throws {
        let (sema, interner) = try makeSema()
        let currentLinks = collectRandomLinks(sema: sema, interner: interner)

        for (signature, link) in Self.implementedLinks {
            XCTAssertTrue(
                currentLinks.contains(link),
                "\(signature) should resolve to \(link); current links: \(currentLinks.sorted())"
            )
        }
    }

    func testCurrentRandomLinksAreClassified() throws {
        let (sema, interner) = try makeSema()
        let currentLinks = collectRandomLinks(sema: sema, interner: interner)
        let classified = Set(Self.implementedLinks.values).union(Self.knownNonOfficialPublishedLinks)
        let unclassified = currentLinks.subtracting(classified)
        XCTAssertTrue(
            unclassified.isEmpty,
            "Unclassified kotlin.random synthetic links: \(unclassified.sorted())"
        )
    }

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func collectRandomLinks(
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        var links: Set<String> = []

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        if let randomSymbol = sema.symbols.lookup(fqName: randomFQ) {
            XCTAssertNotNil(sema.symbols.symbol(randomSymbol), "kotlin.random.Random should be registered")
        } else {
            XCTFail("kotlin.random.Random should be registered")
        }

        let defaultFQ = ["kotlin", "random", "Random", "Default"].map { interner.intern($0) }
        if let defaultSymbol = sema.symbols.lookup(fqName: defaultFQ),
           let link = sema.symbols.externalLinkName(for: defaultSymbol)
        {
            links.insert(link)
        }

        let constructorFQ = ["kotlin", "random", "Random", "<init>"].map { interner.intern($0) }
        for symbol in sema.symbols.lookupAll(fqName: constructorFQ) {
            if let link = sema.symbols.externalLinkName(for: symbol) {
                links.insert(link)
            }
        }

        for member in [
            "nextBits",
            "nextBoolean",
            "nextBytes",
            "nextDouble",
            "nextFloat",
            "nextInt",
            "nextLong",
            "nextUBytes",
            "nextULong",
        ] {
            let memberFQ = ["kotlin", "random", "Random", member].map { interner.intern($0) }
            for symbol in sema.symbols.lookupAll(fqName: memberFQ) {
                if let link = sema.symbols.externalLinkName(for: symbol) {
                    links.insert(link)
                }
            }
        }

        return links
    }
}
