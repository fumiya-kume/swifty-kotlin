/// Sema overload-resolution coverage for kotlin.random.Random
/// Task: STDLIB-RANDOM-001 (API list) + STDLIB-RANDOM-002 (sema/lowering)
///
/// Each test verifies a specific overload-selection or stub-presence property.
/// Tests marked "// GAP:" document capabilities that are not yet registered
/// in the synthetic stub table and will fail until implemented.

@testable import CompilerCore
import Foundation
import XCTest

extension RandomSyntheticLinkTests {

    // MARK: - Random factory / seed constructors

    /// Random(seed: Int) factory constructor is registered and linked correctly.
    func testRandomIntSeedConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let ctorFQ = ["kotlin", "random", "Random", "<init>"].map { interner.intern($0) }
        let ctors = sema.symbols.lookupAll(fqName: ctorFQ)
        XCTAssertFalse(ctors.isEmpty, "Random <init> constructor must be registered")

        let intSeedCtor = ctors.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 1 &&
                sig.parameterTypes.first == sema.types.intType
        }
        XCTAssertNotNil(intSeedCtor, "Random(seed: Int) constructor must exist")

        if let ctor = intSeedCtor {
            let link = sema.symbols.externalLinkName(for: ctor)
            XCTAssertEqual(link, "kk_random_create_seeded",
                           "Random(seed: Int) must link to kk_random_create_seeded")
        }
    }

    /// Random(seed: Long) factory constructor is registered and linked correctly.
    func testRandomLongSeedConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let ctorFQ = ["kotlin", "random", "Random", "<init>"].map { interner.intern($0) }
        let ctors = sema.symbols.lookupAll(fqName: ctorFQ)

        let longSeedCtor = ctors.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 1 &&
                sig.parameterTypes.first == sema.types.longType
        }
        XCTAssertNotNil(longSeedCtor, "Random(seed: Long) constructor must exist")

        if let ctor = longSeedCtor {
            let link = sema.symbols.externalLinkName(for: ctor)
            XCTAssertEqual(link, "kk_random_create_seeded",
                           "Random(seed: Long) must link to kk_random_create_seeded")
        }
    }

    // MARK: - Random.Default singleton

    /// Random.Default property is registered as the default Random singleton.
    func testRandomDefaultSingletonIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let defaultFQ = ["kotlin", "random", "Random", "Default"].map { interner.intern($0) }
        let defaultSym = sema.symbols.lookup(fqName: defaultFQ)
        XCTAssertNotNil(defaultSym, "Random.Default singleton must be registered")

        if let defaultSym {
            let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
            let randomSym = sema.symbols.lookup(fqName: randomFQ)
            XCTAssertNotNil(randomSym, "Random object must be registered")
            if let randomSym {
                let expectedType = sema.types.make(.classType(ClassType(
                    classSymbol: randomSym,
                    args: [],
                    nullability: .nonNull
                )))
                XCTAssertEqual(sema.symbols.propertyType(for: defaultSym), expectedType)
            }
            XCTAssertEqual(sema.symbols.externalLinkName(for: defaultSym), "kk_random_default")
        }
    }

    // MARK: - nextInt overload selection

    /// nextInt() zero-arg, nextInt(until), and nextInt(from, until) are all registered.
    func testNextIntAllThreeOverloadsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let arities = candidates.compactMap { id -> Int? in
            sema.symbols.functionSignature(for: id).map { $0.parameterTypes.count }
        }
        XCTAssertTrue(arities.contains(0), "nextInt() (arity 0) must be registered")
        XCTAssertTrue(arities.contains(1), "nextInt(until) (arity 1) must be registered")
        XCTAssertTrue(arities.contains(2), "nextInt(from, until) (arity 2) must be registered")
    }

    /// nextInt(until) resolves to the arity-1 overload linked to kk_random_nextInt_until.
    func testNextIntUntilOverloadLinksCorrectly() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let arity1 = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.parameterTypes.count == 1
        }
        XCTAssertNotNil(arity1, "nextInt(until) overload must exist")
        if let sym = arity1 {
            XCTAssertEqual(sema.symbols.externalLinkName(for: sym), "kk_random_nextInt_until")
        }
    }

    /// nextInt(from, until) resolves to the arity-2 overload linked to kk_random_nextInt_range.
    func testNextIntFromUntilOverloadLinksCorrectly() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let arity2 = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.parameterTypes.count == 2
        }
        XCTAssertNotNil(arity2, "nextInt(from, until) overload must exist")
        if let sym = arity2 {
            XCTAssertEqual(sema.symbols.externalLinkName(for: sym), "kk_random_nextInt_range")
        }
    }

    /// nextInt(from, until) and nextInt(until) are distinct symbols (no collision).
    func testNextIntOverloadsAreDistinct() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let links = candidates.compactMap { sema.symbols.externalLinkName(for: $0) }
        XCTAssertTrue(links.contains("kk_random_nextInt_until"),
                      "nextInt(until) link must be present")
        XCTAssertTrue(links.contains("kk_random_nextInt_range"),
                      "nextInt(from, until) link must be present")
        let untilSym = candidates.first { sema.symbols.externalLinkName(for: $0) == "kk_random_nextInt_until" }
        let rangeSym = candidates.first { sema.symbols.externalLinkName(for: $0) == "kk_random_nextInt_range" }
        XCTAssertNotEqual(untilSym, rangeSym,
                          "nextInt(until) and nextInt(from, until) must be separate symbols")
    }

    func testNextULongOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextULong"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let ulongRangeFQ = ["kotlin", "ranges", "ULongRange"].map { interner.intern($0) }
        let ulongRangeSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: ulongRangeFQ))
        let ulongRangeType = sema.types.make(.classType(ClassType(
            classSymbol: ulongRangeSymbol,
            args: [],
            nullability: .nonNull
        )))

        func candidate(parameterTypes: [TypeID]) -> SymbolID? {
            candidates.first { id in
                sema.symbols.functionSignature(for: id)?.parameterTypes == parameterTypes
            }
        }

        let zero = try XCTUnwrap(candidate(parameterTypes: []))
        XCTAssertEqual(sema.symbols.externalLinkName(for: zero), "kk_random_nextULong")

        let until = try XCTUnwrap(candidate(parameterTypes: [sema.types.ulongType]))
        XCTAssertEqual(sema.symbols.externalLinkName(for: until), "kk_random_nextULong_until")
        XCTAssertEqual(sema.symbols.functionSignature(for: until)?.returnType, sema.types.ulongType)
        XCTAssertTrue(sema.symbols.functionSignature(for: until)?.canThrow ?? false)

        let range = try XCTUnwrap(candidate(parameterTypes: [sema.types.ulongType, sema.types.ulongType]))
        XCTAssertEqual(sema.symbols.externalLinkName(for: range), "kk_random_nextULong_range")
        XCTAssertEqual(sema.symbols.functionSignature(for: range)?.returnType, sema.types.ulongType)
        XCTAssertTrue(sema.symbols.functionSignature(for: range)?.canThrow ?? false)

        let ulongRange = try XCTUnwrap(candidate(parameterTypes: [ulongRangeType]))
        XCTAssertEqual(sema.symbols.externalLinkName(for: ulongRange), "kk_random_nextULong_ulongRange")
        XCTAssertEqual(sema.symbols.functionSignature(for: ulongRange)?.returnType, sema.types.ulongType)
        XCTAssertTrue(sema.symbols.functionSignature(for: ulongRange)?.canThrow ?? false)
    }

    // MARK: - nextBytes overloads

    /// nextBytes(array: ByteArray) is registered and linked to kk_random_nextBytes.
    func testNextBytesByteArrayOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextBytes"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(candidates.isEmpty, "nextBytes stub must be registered")

        let links = candidates.compactMap { sema.symbols.externalLinkName(for: $0) }
        XCTAssertTrue(links.contains("kk_random_nextBytes"),
                      "nextBytes(array) must link to kk_random_nextBytes")
    }

    /// nextBytes(size: Int) returning a new ByteArray is registered and linked correctly.
    func testNextBytesSizeOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextBytes"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        // The registered overload takes one ByteArray parameter; the size: Int overload
        // would also have arity 1 but with Int parameter type.
        let intParamOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 1 &&
                sig.parameterTypes.first == sema.types.intType
        }
        XCTAssertNotNil(intParamOverload, "nextBytes(size: Int): ByteArray overload must be registered")
        if let intParamOverload,
           let signature = sema.symbols.functionSignature(for: intParamOverload)
        {
            XCTAssertEqual(sema.symbols.externalLinkName(for: intParamOverload), "kk_random_nextBytes_size")
            XCTAssertTrue(signature.canThrow, "nextBytes(size) must expose its negative-size throw path")
        }
    }

    // MARK: - nextBits member

    /// nextBits(bitCount: Int) is registered and linked to kk_random_nextBits.
    func testNextBitsMemberIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextBits"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let nextBits = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == [sema.types.intType] &&
                sig.returnType == sema.types.intType
        }
        XCTAssertNotNil(nextBits, "nextBits(bitCount: Int) member must be registered")
        if let nextBits,
           let signature = sema.symbols.functionSignature(for: nextBits)
        {
            XCTAssertEqual(sema.symbols.externalLinkName(for: nextBits), "kk_random_nextBits")
            XCTAssertTrue(signature.canThrow, "nextBits(bitCount) must expose its bitCount bounds checks")
        }
    }

    // MARK: - nextInt(IntRange) extension

    /// nextInt(range: IntRange) extension function is a documented gap.
    func testNextIntIntRangeExtensionGap() throws {
        let (sema, interner) = try makeSema()

        // The extension fun Random.nextInt(range: IntRange) would be in the
        // kotlin.random package as a top-level function or as an additional
        // nextInt overload with an IntRange receiver parameter.
        let fq = ["kotlin", "random", "Random", "nextInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        // IntRange would appear as a class type parameter; check by looking for
        // an arity-1 overload whose parameter type is a class (not Int primitive).
        let intRangeOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id),
                  sig.parameterTypes.count == 1,
                  let paramType = sig.parameterTypes.first
            else { return false }
            // Int primitive type has kind .primitive; IntRange would be .classType
            if case .primitive = sema.types.kind(of: paramType) { return false }
            return true
        }
        // GAP: nextInt(range: IntRange) extension not yet registered.
        XCTAssertNil(intRangeOverload,
                     "GAP(STDLIB-RANDOM-002): nextInt(range: IntRange) extension not yet registered; " +
                     "change to XCTAssertNotNil once added")
    }
}
