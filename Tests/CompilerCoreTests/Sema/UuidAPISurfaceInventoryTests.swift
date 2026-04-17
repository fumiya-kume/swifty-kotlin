@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-UUID-001 / STDLIB-UUID-002: kotlin.uuid.Uuid API surface inventory
//
// This file catalogues every Uuid-related symbol that the sema layer registers as a
// synthetic stub and verifies that:
//   • the kotlin.uuid package hierarchy is present after sema
//   • Uuid class, Companion object, and all factory/instance members are wired to
//     the correct ABI external-link names
//   • overload resolution between Uuid.parse and Uuid.parseHex (gap: see below)
//   • Uuid.random() return type resolves to kotlin.uuid.Uuid
//   • toString vs toHexString dispatch is tracked as separate links
//   • toByteArray() and toLongs() are present with their signatures
//   • NIL constant (gap: see below)
//   • @ExperimentalUuidApi opt-in marker: now synthesised (STDLIB-EXPERIMENTAL-ABI-001)
//
// Scope: sema / symbol-table level only.  Runtime correctness is in RuntimeUuidTests
//        and the edge-case file added in PR #1221 (UUID-003).
//
// NOTE — known gaps detected during inventory (UUID-002):
//   • Uuid.parseHex(hex: String) overload is not yet registered by the sema layer.
//     `allExternalLinks` for kotlin.uuid.Uuid.Companion.parseHex returns an empty set.
//   • Uuid.NIL companion constant is not yet registered.
//   • @ExperimentalUuidApi: resolved in STDLIB-EXPERIMENTAL-ABI-001 (PR #1282).

final class UuidAPISurfaceInventoryTests: XCTestCase {

    // MARK: - Shared sema fixture

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

    // MARK: - Lookup helpers

    /// Single external-link name for a fully-qualified symbol path.
    private func externalLink(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let interned = fqPath.map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: interned) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    /// All external-link names registered under a fully-qualified symbol path.
    private func allExternalLinks(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        let interned = fqPath.map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: interned)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    // MARK: - 1. Package hierarchy and class registration

    func testKotlinUuidPackageIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid"].map { interner.intern($0) }
        XCTAssertNotNil(
            sema.symbols.lookup(fqName: fq),
            "kotlin.uuid package must be present in symbol table after sema"
        )
    }

    func testUuidClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let sym = sema.symbols.lookup(fqName: fq)
        XCTAssertNotNil(sym, "kotlin.uuid.Uuid class must be present in symbol table after sema")
    }

    func testUuidClassKindIsClass() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq),
              let info = sema.symbols.symbol(sym) else {
            XCTFail("kotlin.uuid.Uuid not found"); return
        }
        XCTAssertEqual(info.kind, .class, "kotlin.uuid.Uuid must be registered with kind=class")
    }

    func testUuidCompanionObjectIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion"].map { interner.intern($0) }
        XCTAssertNotNil(
            sema.symbols.lookup(fqName: fq),
            "kotlin.uuid.Uuid.Companion object must be registered in symbol table"
        )
    }

    // MARK: - 2. Companion factory methods

    func testUuidRandomCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "random"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_random"),
            "Uuid.random() must link to kk_uuid_random; found: \(links)"
        )
    }

    func testUuidRandomReturnTypeIsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "random"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.random() must be in symbol table")
        let randomSym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: randomSym) else {
            XCTFail("Uuid.random() has no function signature"); return
        }
        // The return type must not be Any/void — it must resolve to Uuid's class type.
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            XCTFail("kotlin.uuid.Uuid class symbol missing"); return
        }
        let returnTypeKind = sema.types.kind(of: sig.returnType)
        if case .classType(let ct) = returnTypeKind {
            XCTAssertEqual(
                ct.classSymbol, uuidSym,
                "Uuid.random() return type must be kotlin.uuid.Uuid"
            )
        } else {
            XCTFail("Uuid.random() return type is not a class type; got \(returnTypeKind)")
        }
    }

    func testUuidParseCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "parse"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_parse"),
            "Uuid.parse(uuidString) must link to kk_uuid_parse; found: \(links)"
        )
    }

    func testUuidParseAcceptsStringParameter() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parse"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.parse must be registered")
        let parseSym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseSym) else {
            XCTFail("Uuid.parse has no signature"); return
        }
        XCTAssertEqual(sig.parameterTypes.count, 1, "Uuid.parse must take exactly 1 parameter")
        // String is a primitive type in the compiler's TypeSystem (stringType).
        // Verify the parameter resolves to the compiler's string type.
        XCTAssertEqual(
            sig.parameterTypes[0], sema.types.stringType,
            "Uuid.parse parameter must be of type String (sema.types.stringType)"
        )
    }

    func testUuidNameUUIDFromBytesCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "nameUUIDFromBytes"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_nameUUIDFromBytes"),
            "Uuid.nameUUIDFromBytes must link to kk_uuid_nameUUIDFromBytes; found: \(links)"
        )
    }

    // MARK: - 3. Overload presence: parse vs parseHex
    //
    // STDLIB-UUID-002 gap: parseHex is not yet registered.
    // This test documents the gap — it asserts the *current* state (empty set) and
    // provides a TODO marker so the gap is visible in CI output.

    func testUuidParseHexCompanionMethodIsNotYetRegistered_Gap() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "parseHex"],
            sema: sema,
            interner: interner
        )
        // TODO(STDLIB-UUID-002): When parseHex is implemented, change XCTAssertTrue to
        //   links.contains("kk_uuid_parseHex")
        XCTAssertTrue(
            links.isEmpty,
            "Uuid.parseHex overload is not yet registered (expected gap); found: \(links)"
        )
    }

    func testUuidParseAndParseAreDistinctOverloads() throws {
        // parse(uuidString) exists; parseHex is absent — they must never share the same symbol.
        let (sema, interner) = try makeSema()
        let parseFQ = ["kotlin", "uuid", "Uuid", "Companion", "parse"].map { interner.intern($0) }
        let parseHexFQ = ["kotlin", "uuid", "Uuid", "Companion", "parseHex"].map { interner.intern($0) }
        let parseSyms = Set(sema.symbols.lookupAll(fqName: parseFQ))
        let parseHexSyms = Set(sema.symbols.lookupAll(fqName: parseHexFQ))
        XCTAssertTrue(
            parseSyms.isDisjoint(with: parseHexSyms),
            "parse and parseHex must not share the same SymbolID"
        )
    }

    // MARK: - 4. Instance methods: toString vs toHexString dispatch

    func testUuidToStringInstanceMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "uuid", "Uuid", "toString"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_uuid_toString",
            "Uuid.toString() must link to kk_uuid_toString"
        )
    }

    func testUuidToHexStringInstanceMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "uuid", "Uuid", "toHexString"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_uuid_toHexString",
            "Uuid.toHexString() must link to kk_uuid_toHexString"
        )
    }

    func testUuidToStringAndToHexStringHaveDistinctLinks() throws {
        let (sema, interner) = try makeSema()
        let toStringLink = externalLink(
            fqPath: ["kotlin", "uuid", "Uuid", "toString"],
            sema: sema,
            interner: interner
        )
        let toHexStringLink = externalLink(
            fqPath: ["kotlin", "uuid", "Uuid", "toHexString"],
            sema: sema,
            interner: interner
        )
        XCTAssertNotEqual(
            toStringLink, toHexStringLink,
            "toString and toHexString must dispatch to different external-link names"
        )
    }

    // MARK: - 5. Instance methods: toByteArray and toLongs

    func testUuidToByteArrayInstanceMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "uuid", "Uuid", "toByteArray"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_uuid_toByteArray",
            "Uuid.toByteArray() must link to kk_uuid_toByteArray"
        )
    }

    func testUuidToByteArrayHasNoParameters() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "toByteArray"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.toByteArray must be registered")
        let sym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("Uuid.toByteArray has no signature"); return
        }
        XCTAssertTrue(sig.parameterTypes.isEmpty, "Uuid.toByteArray() must take no parameters")
    }

    func testUuidToLongsInstanceMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "uuid", "Uuid", "toLongs"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_uuid_toLongs",
            "Uuid.toLongs() must link to kk_uuid_toLongs"
        )
    }

    func testUuidToLongsHasNoParameters() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "toLongs"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.toLongs must be registered")
        let sym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("Uuid.toLongs has no signature"); return
        }
        XCTAssertTrue(sig.parameterTypes.isEmpty, "Uuid.toLongs() must take no parameters")
    }

    // MARK: - 6. Instance properties: mostSignificantBits, leastSignificantBits

    func testUuidMostSignificantBitsPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "uuid", "Uuid", "mostSignificantBits"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_uuid_mostSignificantBits",
            "Uuid.mostSignificantBits property must link to kk_uuid_mostSignificantBits"
        )
    }

    func testUuidLeastSignificantBitsPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "uuid", "Uuid", "leastSignificantBits"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_uuid_leastSignificantBits",
            "Uuid.leastSignificantBits property must link to kk_uuid_leastSignificantBits"
        )
    }

    // MARK: - 7. Instance methods: version and variant

    func testUuidVersionInstanceMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "uuid", "Uuid", "version"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_uuid_version",
            "Uuid.version() must link to kk_uuid_version"
        )
    }

    func testUuidVariantInstanceMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "uuid", "Uuid", "variant"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link, "kk_uuid_variant",
            "Uuid.variant() must link to kk_uuid_variant"
        )
    }

    // MARK: - 8. NIL constant — gap documentation
    //
    // STDLIB-UUID-002 gap: Uuid.NIL companion constant is not yet registered.
    // The test asserts the current state so CI catches any unintended change.

    func testUuidNILCompanionConstantIsNotYetRegistered_Gap() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "NIL"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        // TODO(STDLIB-UUID-002): When NIL is implemented, assert syms is non-empty.
        XCTAssertTrue(
            syms.isEmpty,
            "Uuid.NIL constant is not yet registered (expected gap); found \(syms.count) symbols"
        )
    }

    // MARK: - 9. @ExperimentalUuidApi opt-in annotation — now synthesised (STDLIB-EXPERIMENTAL-ABI-001)
    //
    // STDLIB-UUID-002 gap: resolved. @ExperimentalUuidApi annotation marker is now synthesised.

    func testExperimentalUuidApiAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "ExperimentalUuidApi"].map { interner.intern($0) }
        let sym = sema.symbols.lookup(fqName: fq)
        XCTAssertNotNil(
            sym,
            "kotlin.uuid.ExperimentalUuidApi must be registered (STDLIB-EXPERIMENTAL-ABI-001)"
        )
    }

    // MARK: - 10. Full API surface inventory

    func testAllRegisteredUuidCompanionLinksArePresent() throws {
        let (sema, interner) = try makeSema()
        let companionFQ = ["kotlin", "uuid", "Uuid", "Companion"]
        let expectedCompanionLinks: Set<String> = [
            "kk_uuid_random",
            "kk_uuid_parse",
            "kk_uuid_nameUUIDFromBytes",
        ]
        var foundLinks: Set<String> = []
        for memberName in ["random", "parse", "nameUUIDFromBytes"] {
            let path = companionFQ + [memberName]
            let links = allExternalLinks(fqPath: path, sema: sema, interner: interner)
            foundLinks.formUnion(links)
        }
        XCTAssertTrue(
            expectedCompanionLinks.isSubset(of: foundLinks),
            "All companion methods must be registered; found: \(foundLinks)"
        )
    }

    func testAllRegisteredUuidInstanceMethodLinksArePresent() throws {
        let (sema, interner) = try makeSema()
        let classFQ = ["kotlin", "uuid", "Uuid"]
        let expectedInstanceLinks: Set<String> = [
            "kk_uuid_toString",
            "kk_uuid_toHexString",
            "kk_uuid_toLongs",
            "kk_uuid_toByteArray",
            "kk_uuid_version",
            "kk_uuid_variant",
        ]
        var foundLinks: Set<String> = []
        for member in ["toString", "toHexString", "toLongs", "toByteArray", "version", "variant"] {
            let path = classFQ + [member]
            let links = allExternalLinks(fqPath: path, sema: sema, interner: interner)
            foundLinks.formUnion(links)
        }
        XCTAssertTrue(
            expectedInstanceLinks.isSubset(of: foundLinks),
            "All instance methods must be registered; found: \(foundLinks)"
        )
    }

    func testAllRegisteredUuidPropertyLinksArePresent() throws {
        let (sema, interner) = try makeSema()
        let classFQ = ["kotlin", "uuid", "Uuid"]
        let expectedPropertyLinks: Set<String> = [
            "kk_uuid_mostSignificantBits",
            "kk_uuid_leastSignificantBits",
        ]
        var foundLinks: Set<String> = []
        for prop in ["mostSignificantBits", "leastSignificantBits"] {
            let path = classFQ + [prop]
            let links = allExternalLinks(fqPath: path, sema: sema, interner: interner)
            foundLinks.formUnion(links)
        }
        XCTAssertTrue(
            expectedPropertyLinks.isSubset(of: foundLinks),
            "All instance properties must be registered; found: \(foundLinks)"
        )
    }
}
