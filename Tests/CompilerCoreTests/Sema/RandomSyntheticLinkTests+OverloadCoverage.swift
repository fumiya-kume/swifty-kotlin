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

    /// nextLong(range: LongRange) extension-style overload is registered on Random.
    func testNextLongLongRangeExtensionIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextLong"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let longRangeOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id),
                  sig.parameterTypes.count == 1,
                  let paramType = sig.parameterTypes.first
            else { return false }
            if case .primitive = sema.types.kind(of: paramType) { return false }
            return true
        }
        XCTAssertNotNil(longRangeOverload, "nextLong(range: LongRange) overload must be registered")
        if let longRangeOverload,
           let signature = sema.symbols.functionSignature(for: longRangeOverload)
        {
            XCTAssertEqual(sema.symbols.externalLinkName(for: longRangeOverload), "kk_random_nextLong_rangeObject")
            XCTAssertEqual(signature.returnType, sema.types.longType)
            XCTAssertTrue(signature.canThrow, "nextLong(range) must expose the empty-range throw path")
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

    /// nextBytes(array, fromIndex, toIndex) is registered and linked correctly.
    func testNextBytesArrayRangeOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextBytes"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let rangeOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 3 &&
                sig.parameterTypes.dropFirst().allSatisfy { $0 == sema.types.intType }
        }
        XCTAssertNotNil(rangeOverload, "nextBytes(array, fromIndex, toIndex) overload must be registered")
        if let rangeOverload,
           let signature = sema.symbols.functionSignature(for: rangeOverload)
        {
            XCTAssertEqual(sema.symbols.externalLinkName(for: rangeOverload), "kk_random_nextBytes_range")
            XCTAssertTrue(signature.canThrow, "nextBytes(array, fromIndex, toIndex) must expose its bounds checks")
        }
    }

    /// nextUBytes overloads are registered with UByteArray surface types.
    func testNextUBytesOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextUBytes"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        let byLink = Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate in
            sema.symbols.externalLinkName(for: candidate).map { ($0, candidate) }
        })

        func isUByteArrayType(_ type: TypeID) -> Bool {
            guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }
            return interner.resolve(symbol.name) == "UByteArray"
        }

        let arrayOverload = try XCTUnwrap(byLink["kk_random_nextUBytes"])
        let arraySignature = try XCTUnwrap(sema.symbols.functionSignature(for: arrayOverload))
        XCTAssertEqual(arraySignature.parameterTypes.count, 1)
        XCTAssertTrue(isUByteArrayType(arraySignature.parameterTypes[0]))
        XCTAssertTrue(isUByteArrayType(arraySignature.returnType))
        XCTAssertFalse(arraySignature.canThrow)

        let sizeOverload = try XCTUnwrap(byLink["kk_random_nextUBytes_size"])
        let sizeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: sizeOverload))
        XCTAssertEqual(sizeSignature.parameterTypes, [sema.types.intType])
        XCTAssertTrue(isUByteArrayType(sizeSignature.returnType))
        XCTAssertTrue(sizeSignature.canThrow)

        let rangeOverload = try XCTUnwrap(byLink["kk_random_nextUBytes_range"])
        let rangeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: rangeOverload))
        XCTAssertEqual(rangeSignature.parameterTypes.count, 3)
        XCTAssertTrue(isUByteArrayType(rangeSignature.parameterTypes[0]))
        XCTAssertEqual(Array(rangeSignature.parameterTypes.dropFirst()), [sema.types.intType, sema.types.intType])
        XCTAssertTrue(isUByteArrayType(rangeSignature.returnType))
        XCTAssertTrue(rangeSignature.canThrow)
    }

    // MARK: - nextInt(IntRange) extension

    /// nextInt(range: IntRange) extension function is registered and linked correctly.
    func testNextIntIntRangeExtensionIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let intRangeOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id),
                  sig.parameterTypes.count == 1,
                  let paramType = sig.parameterTypes.first
            else { return false }
            if case .primitive = sema.types.kind(of: paramType) { return false }
            return true
        }
        XCTAssertNotNil(intRangeOverload, "nextInt(range: IntRange) overload must be registered")
        if let intRangeOverload,
           let signature = sema.symbols.functionSignature(for: intRangeOverload)
        {
            XCTAssertEqual(sema.symbols.externalLinkName(for: intRangeOverload), "kk_random_nextInt_intRange")
            XCTAssertEqual(signature.returnType, sema.types.intType)
            XCTAssertTrue(signature.canThrow, "nextInt(range) must expose the empty-range throw path")
        }
    }

    // MARK: - range.random(random: Random)

    func testRangeRandomOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: randomFQ))
        let randomType = sema.types.make(.classType(ClassType(
            classSymbol: randomSymbol,
            args: [],
            nullability: .nonNull
        )))

        let cases: [(typeName: String, expectedLink: String)] = [
            ("CharRange", "kk_char_range_random_random"),
            ("IntRange", "kk_range_random_random"),
            ("LongRange", "kk_long_range_random_random"),
            ("UIntRange", "kk_uint_range_random_random"),
            ("ULongRange", "kk_ulong_range_random_random"),
        ]

        for (typeName, expectedLink) in cases {
            let fq = ["kotlin", "ranges", typeName, "random"].map { interner.intern($0) }
            let candidates = sema.symbols.lookupAll(fqName: fq)
            let overload = candidates.first { id in
                guard let sig = sema.symbols.functionSignature(for: id) else { return false }
                return sig.parameterTypes.count == 1 && sig.parameterTypes.first == randomType
            }
            XCTAssertNotNil(overload, "\(typeName).random(random: Random) must be registered")
            if let overload {
                XCTAssertEqual(sema.symbols.externalLinkName(for: overload), expectedLink)
            }
        }
    }
}
