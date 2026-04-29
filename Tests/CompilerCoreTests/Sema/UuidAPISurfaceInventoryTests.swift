@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-UUID-001 / STDLIB-UUID-002: kotlin.uuid.Uuid API surface inventory
//
// This file catalogues the Uuid-related symbols that the sema layer registers as
// synthetic stubs and verifies that:
//   • the kotlin.uuid package hierarchy is present after sema
//   • Uuid class, Companion object, and all factory/instance members are wired to
//     the correct ABI external-link names
//   • implemented companion factories are tracked in one inventory
//   • known pending companion members are tracked as gaps
//   • Uuid.random() return type resolves to kotlin.uuid.Uuid
//   • Uuid.LEXICAL_ORDER resolves to Comparator<Uuid>
//   • toString vs toHexString dispatch is tracked as separate links
//   • toByteArray() and toLongs() are present with their signatures
//   • @ExperimentalUuidApi opt-in marker: now synthesised (STDLIB-EXPERIMENTAL-ABI-001)
//
// Scope: sema / symbol-table level only.  Runtime correctness is in RuntimeUuidTests
//        and the edge-case file added in PR #1221 (UUID-003).
//
// NOTE - known gaps detected during inventory:
//   • No tracked companion-member gaps remain for the implemented UUID surface.

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

    private func symbols(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        sema.symbols.lookupAll(fqName: fqPath.map { interner.intern($0) })
    }

    private func hasExperimentalUuidApiAnnotation(
        _ symbol: SymbolID,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.annotations(for: symbol).contains {
            $0.annotationFQName == "kotlin.uuid.ExperimentalUuidApi"
        }
    }

    private func runUuidSemaCollectingDiagnostics(
        _ source: String,
        frontendFlags: [String] = []
    ) -> CompilationContext {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath], frontendFlags: frontendFlags)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        do {
            try runSema(ctx)
        } catch {
            // Individual tests assert on the resulting diagnostics.
        }
        return ctx
    }

    private func optInDiagnostics(in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
    }

    private func isError(_ diagnostic: Diagnostic) -> Bool {
        if case .error = diagnostic.severity {
            return true
        }
        return false
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

    func testUuidParseOrNullAcceptsStringParameterAndReturnsNullableUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parseOrNull"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.parseOrNull must be registered")
        let parseOrNullSym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseOrNullSym) else {
            XCTFail("Uuid.parseOrNull has no signature"); return
        }
        XCTAssertEqual(sig.parameterTypes.count, 1, "Uuid.parseOrNull must take exactly 1 parameter")
        XCTAssertEqual(
            sig.parameterTypes[0], sema.types.stringType,
            "Uuid.parseOrNull parameter must be of type String (sema.types.stringType)"
        )

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try XCTUnwrap(sema.symbols.lookup(fqName: uuidFQ))
        guard case .classType(let ct) = sema.types.kind(of: sig.returnType) else {
            XCTFail("Uuid.parseOrNull return type must be a nullable Uuid class type")
            return
        }
        XCTAssertEqual(ct.classSymbol, uuidSym)
        XCTAssertEqual(ct.nullability, .nullable)
    }

    func testUuidParseHexAcceptsStringParameter() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parseHex"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.parseHex must be registered")
        let parseHexSym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseHexSym) else {
            XCTFail("Uuid.parseHex has no signature"); return
        }
        XCTAssertEqual(sig.parameterTypes.count, 1, "Uuid.parseHex must take exactly 1 parameter")
        XCTAssertEqual(
            sig.parameterTypes[0], sema.types.stringType,
            "Uuid.parseHex parameter must be of type String (sema.types.stringType)"
        )
    }

    func testUuidParseHexOrNullAcceptsStringParameterAndReturnsNullableUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parseHexOrNull"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.parseHexOrNull must be registered")
        let parseHexOrNullSym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseHexOrNullSym) else {
            XCTFail("Uuid.parseHexOrNull has no signature"); return
        }
        XCTAssertEqual(sig.parameterTypes.count, 1, "Uuid.parseHexOrNull must take exactly 1 parameter")
        XCTAssertEqual(
            sig.parameterTypes[0], sema.types.stringType,
            "Uuid.parseHexOrNull parameter must be of type String (sema.types.stringType)"
        )

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try XCTUnwrap(sema.symbols.lookup(fqName: uuidFQ))
        guard case .classType(let ct) = sema.types.kind(of: sig.returnType) else {
            XCTFail("Uuid.parseHexOrNull return type must be a nullable Uuid class type")
            return
        }
        XCTAssertEqual(ct.classSymbol, uuidSym)
        XCTAssertEqual(ct.nullability, .nullable)
    }

    func testUuidParseHexDashAcceptsStringParameter() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parseHexDash"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.parseHexDash must be registered")
        let parseHexDashSym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseHexDashSym) else {
            XCTFail("Uuid.parseHexDash has no signature"); return
        }
        XCTAssertEqual(sig.parameterTypes.count, 1, "Uuid.parseHexDash must take exactly 1 parameter")
        XCTAssertEqual(
            sig.parameterTypes[0], sema.types.stringType,
            "Uuid.parseHexDash parameter must be of type String (sema.types.stringType)"
        )
    }

    func testUuidParseHexDashOrNullAcceptsStringParameterAndReturnsNullableUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "parseHexDashOrNull"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.parseHexDashOrNull must be registered")
        let parseHexDashOrNullSym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: parseHexDashOrNullSym) else {
            XCTFail("Uuid.parseHexDashOrNull has no signature"); return
        }
        XCTAssertEqual(sig.parameterTypes.count, 1, "Uuid.parseHexDashOrNull must take exactly 1 parameter")
        XCTAssertEqual(
            sig.parameterTypes[0], sema.types.stringType,
            "Uuid.parseHexDashOrNull parameter must be of type String (sema.types.stringType)"
        )

        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try XCTUnwrap(sema.symbols.lookup(fqName: uuidFQ))
        guard case .classType(let ct) = sema.types.kind(of: sig.returnType) else {
            XCTFail("Uuid.parseHexDashOrNull return type must be a nullable Uuid class type")
            return
        }
        XCTAssertEqual(ct.classSymbol, uuidSym)
        XCTAssertEqual(ct.nullability, .nullable)
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

    func testUuidFromLongsCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_fromLongs"),
            "Uuid.fromLongs must link to kk_uuid_fromLongs; found: \(links)"
        )
    }

    func testUuidFromByteArrayCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_fromByteArray"),
            "Uuid.fromByteArray must link to kk_uuid_fromByteArray; found: \(links)"
        )
    }

    // MARK: - 3. Overload presence: parse vs parseHex

    func testUuidParseHexCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "parseHex"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_parseHex"),
            "Uuid.parseHex(hexString) must link to kk_uuid_parseHex; found: \(links)"
        )
    }

    func testUuidParseHexOrNullCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "parseHexOrNull"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_parseHexOrNull"),
            "Uuid.parseHexOrNull(hexString) must link to kk_uuid_parseHexOrNull; found: \(links)"
        )
    }

    func testUuidParseOrNullCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "parseOrNull"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_parseOrNull"),
            "Uuid.parseOrNull(uuidString) must link to kk_uuid_parseOrNull; found: \(links)"
        )
    }

    func testUuidParseHexDashCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "parseHexDash"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_parseHexDash"),
            "Uuid.parseHexDash(hexDashString) must link to kk_uuid_parseHexDash; found: \(links)"
        )
    }

    func testUuidParseHexDashOrNullCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "parseHexDashOrNull"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_parseHexDashOrNull"),
            "Uuid.parseHexDashOrNull(hexDashString) must link to kk_uuid_parseHexDashOrNull; found: \(links)"
        )
    }

    func testUuidParseFactoriesAreDistinctOverloads() throws {
        let (sema, interner) = try makeSema()
        let parseFQ = ["kotlin", "uuid", "Uuid", "Companion", "parse"].map { interner.intern($0) }
        let parseHexFQ = ["kotlin", "uuid", "Uuid", "Companion", "parseHex"].map { interner.intern($0) }
        let parseHexDashFQ = ["kotlin", "uuid", "Uuid", "Companion", "parseHexDash"].map { interner.intern($0) }
        let parseSyms = Set(sema.symbols.lookupAll(fqName: parseFQ))
        let parseHexSyms = Set(sema.symbols.lookupAll(fqName: parseHexFQ))
        let parseHexDashSyms = Set(sema.symbols.lookupAll(fqName: parseHexDashFQ))
        XCTAssertFalse(parseSyms.isEmpty, "Uuid.parse must be registered")
        XCTAssertFalse(parseHexSyms.isEmpty, "Uuid.parseHex must be registered")
        XCTAssertFalse(parseHexDashSyms.isEmpty, "Uuid.parseHexDash must be registered")
        XCTAssertTrue(
            parseSyms.isDisjoint(with: parseHexSyms),
            "parse and parseHex must not share the same SymbolID"
        )
        XCTAssertTrue(
            parseSyms.isDisjoint(with: parseHexDashSyms),
            "parse and parseHexDash must not share the same SymbolID"
        )
        XCTAssertTrue(
            parseHexSyms.isDisjoint(with: parseHexDashSyms),
            "parseHex and parseHexDash must not share the same SymbolID"
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

    // MARK: - 8. NIL constant

    func testUuidNILCompanionConstantIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "NIL"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(
            link,
            "kk_uuid_nil",
            "Uuid.NIL companion constant must link to kk_uuid_nil"
        )
    }

    func testUuidNILReturnTypeIsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "NIL"].map { interner.intern($0) }
        let nilSym = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fq).first,
            "Uuid.NIL must be registered"
        )
        let propType = try XCTUnwrap(sema.symbols.propertyType(for: nilSym))
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        let uuidSym = try XCTUnwrap(sema.symbols.lookup(fqName: uuidFQ))

        guard case .classType(let ct) = sema.types.kind(of: propType) else {
            XCTFail("Uuid.NIL property type must be a class type")
            return
        }
        XCTAssertEqual(ct.classSymbol, uuidSym)
    }

    func testUuidSizeConstantsAreRegisteredAsConstInts() throws {
        let (sema, interner) = try makeSema()
        let expectedConstants: [(name: String, value: Int64)] = [
            ("SIZE_BITS", 128),
            ("SIZE_BYTES", 16),
        ]

        for expected in expectedConstants {
            let fq = ["kotlin", "uuid", "Uuid", "Companion", expected.name].map { interner.intern($0) }
            let sym = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: fq).first(where: { sema.symbols.symbol($0)?.kind == .property }),
                "Uuid.\(expected.name) must be registered as a companion property"
            )
            let info = try XCTUnwrap(sema.symbols.symbol(sym))
            XCTAssertTrue(info.flags.contains(.static), "Uuid.\(expected.name) must be static")
            XCTAssertTrue(info.flags.contains(.constValue), "Uuid.\(expected.name) must be const")
            XCTAssertEqual(
                sema.symbols.propertyType(for: sym),
                sema.types.intType,
                "Uuid.\(expected.name) must have Int type"
            )
            XCTAssertEqual(
                sema.symbols.constValueExprKind(for: sym),
                .intLiteral(expected.value),
                "Uuid.\(expected.name) must expose the Kotlin stdlib constant value"
            )
        }
    }

    func testUuidLexicalOrderComparatorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "LEXICAL_ORDER"].map { interner.intern($0) }
        let lexicalOrderSym = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fq).first(where: { sema.symbols.symbol($0)?.kind == .property }),
            "Uuid.LEXICAL_ORDER must be registered as a companion property"
        )

        XCTAssertEqual(
            sema.symbols.externalLinkName(for: lexicalOrderSym),
            "kk_uuid_lexicalOrder",
            "Uuid.LEXICAL_ORDER must link to the UUID lexical comparator runtime"
        )

        let propType = try XCTUnwrap(sema.symbols.propertyType(for: lexicalOrderSym))
        guard case .classType(let comparatorType) = sema.types.kind(of: propType) else {
            XCTFail("Uuid.LEXICAL_ORDER type must be kotlin.Comparator<Uuid>")
            return
        }

        let comparatorSym = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "Comparator"].map { interner.intern($0) })
        )
        let uuidSym = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "uuid", "Uuid"].map { interner.intern($0) })
        )

        XCTAssertEqual(comparatorType.classSymbol, comparatorSym)
        guard let firstArg = comparatorType.args.first,
              case .invariant(let uuidType) = firstArg
        else {
            XCTFail("Uuid.LEXICAL_ORDER Comparator type must carry invariant Uuid argument")
            return
        }
        guard case .classType(let uuidClassType) = sema.types.kind(of: uuidType) else {
            XCTFail("Uuid.LEXICAL_ORDER Comparator argument must be Uuid")
            return
        }
        XCTAssertEqual(uuidClassType.classSymbol, uuidSym)
    }

    func testKnownPendingUuidCompanionMembersAreTrackedAsGaps() throws {
        let (sema, interner) = try makeSema()
        let pendingMembers: [String] = []

        XCTAssertTrue(pendingMembers.isEmpty, "No UUID companion pending gaps should remain")

        for memberName in pendingMembers {
            let fq = ["kotlin", "uuid", "Uuid", "Companion", memberName].map { interner.intern($0) }
            let syms = sema.symbols.lookupAll(fqName: fq)
            XCTAssertTrue(
                syms.isEmpty,
                "Uuid.\(memberName) is a tracked pending API and must remain absent until its TODO is implemented; found \(syms.count) symbols"
            )
        }
    }

    func testUuidLexicalOrderComparatorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "LEXICAL_ORDER"].map { interner.intern($0) }
        let lexicalOrderSym = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fq).first(where: { sema.symbols.symbol($0)?.kind == .property }),
            "Uuid.LEXICAL_ORDER must be registered as a companion property"
        )

        XCTAssertEqual(
            sema.symbols.externalLinkName(for: lexicalOrderSym),
            "kk_uuid_lexicalOrder",
            "Uuid.LEXICAL_ORDER must link to the UUID lexical comparator runtime"
        )

        let propType = try XCTUnwrap(sema.symbols.propertyType(for: lexicalOrderSym))
        guard case .classType(let comparatorType) = sema.types.kind(of: propType) else {
            XCTFail("Uuid.LEXICAL_ORDER type must be kotlin.Comparator<Uuid>")
            return
        }

        let comparatorSym = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "Comparator"].map { interner.intern($0) })
        )
        let uuidSym = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["kotlin", "uuid", "Uuid"].map { interner.intern($0) })
        )

        XCTAssertEqual(comparatorType.classSymbol, comparatorSym)
        guard let firstArg = comparatorType.args.first,
              case .invariant(let uuidType) = firstArg
        else {
            XCTFail("Uuid.LEXICAL_ORDER Comparator type must carry invariant Uuid argument")
            return
        }
        guard case .classType(let uuidClassType) = sema.types.kind(of: uuidType) else {
            XCTFail("Uuid.LEXICAL_ORDER Comparator argument must be Uuid")
            return
        }
        XCTAssertEqual(uuidClassType.classSymbol, uuidSym)
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

    func testExperimentalUuidApiAnnotationIsRequiresOptIn() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "ExperimentalUuidApi"].map { interner.intern($0) }
        let sym = try XCTUnwrap(sema.symbols.lookup(fqName: fq))
        let annotations = sema.symbols.annotations(for: sym)

        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.RequiresOptIn" &&
                    $0.arguments.contains("level=RequiresOptIn.Level.ERROR")
            },
            "ExperimentalUuidApi must carry @RequiresOptIn(ERROR), got \(annotations)"
        )
    }

    func testUuidApiSymbolsAreTaggedExperimentalUuidApi() throws {
        let (sema, interner) = try makeSema()
        let apiPaths = [
            ["kotlin", "uuid", "Uuid"],
            ["kotlin", "uuid", "Uuid", "Companion", "random"],
            ["kotlin", "uuid", "Uuid", "Companion", "NIL"],
            ["kotlin", "uuid", "Uuid", "Companion", "SIZE_BITS"],
            ["kotlin", "uuid", "Uuid", "Companion", "SIZE_BYTES"],
            ["kotlin", "uuid", "Uuid", "Companion", "LEXICAL_ORDER"],
            ["kotlin", "uuid", "Uuid", "Companion", "parse"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHex"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexDash"],
            ["kotlin", "uuid", "Uuid", "Companion", "parseHexDashOrNull"],
            ["kotlin", "uuid", "Uuid", "Companion", "nameUUIDFromBytes"],
            ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"],
            ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"],
            ["kotlin", "uuid", "Uuid", "toString"],
            ["kotlin", "uuid", "Uuid", "toHexString"],
            ["kotlin", "uuid", "Uuid", "toLongs"],
            ["kotlin", "uuid", "Uuid", "toByteArray"],
            ["kotlin", "uuid", "Uuid", "version"],
            ["kotlin", "uuid", "Uuid", "variant"],
            ["kotlin", "uuid", "Uuid", "mostSignificantBits"],
            ["kotlin", "uuid", "Uuid", "leastSignificantBits"],
        ]

        for path in apiPaths {
            let syms = symbols(fqPath: path, sema: sema, interner: interner)
            XCTAssertFalse(syms.isEmpty, "\(path.joined(separator: ".")) must be registered")
            XCTAssertTrue(
                syms.contains { hasExperimentalUuidApiAnnotation($0, sema: sema) },
                "\(path.joined(separator: ".")) must carry @ExperimentalUuidApi"
            )
        }
    }

    func testUuidUsageWithoutOptInEmitsDiagnostic() {
        let source = """
        import kotlin.uuid.Uuid

        fun uuidText(): String = Uuid.NIL.toString()
        """

        let ctx = runUuidSemaCollectingDiagnostics(source)
        let diagnostics = optInDiagnostics(in: ctx)

        XCTAssertFalse(
            diagnostics.isEmpty,
            "Expected opt-in diagnostics for Uuid usage without @OptIn, got \(ctx.diagnostics.diagnostics)"
        )
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Uuid opt-in diagnostics should be errors")
    }

    func testUuidUsageWithOptInSuppressesDiagnostic() {
        let source = """
        import kotlin.OptIn
        import kotlin.uuid.ExperimentalUuidApi
        import kotlin.uuid.Uuid

        @OptIn(ExperimentalUuidApi::class)
        fun uuidText(): String = Uuid.NIL.toString()
        """

        let ctx = runUuidSemaCollectingDiagnostics(source)
        let diagnostics = optInDiagnostics(in: ctx)

        XCTAssertTrue(
            diagnostics.isEmpty,
            "Expected @OptIn(ExperimentalUuidApi::class) to suppress Uuid opt-in diagnostics, got \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - 10. Full API surface inventory

    func testAllRegisteredUuidCompanionLinksArePresent() throws {
        let (sema, interner) = try makeSema()
        let companionFQ = ["kotlin", "uuid", "Uuid", "Companion"]
        let expectedCompanionLinks: Set<String> = [
            "kk_uuid_random",
            "kk_uuid_nil",
            "kk_uuid_lexicalOrder",
            "kk_uuid_parse",
            "kk_uuid_parseOrNull",
            "kk_uuid_parseHex",
            "kk_uuid_parseHexOrNull",
            "kk_uuid_parseHexDash",
            "kk_uuid_parseHexDashOrNull",
            "kk_uuid_nameUUIDFromBytes",
            "kk_uuid_fromLongs",
            "kk_uuid_fromByteArray",
        ]
        var foundLinks: Set<String> = []
        for memberName in ["random", "NIL", "LEXICAL_ORDER", "parse", "parseOrNull", "parseHex", "parseHexOrNull", "parseHexDash", "parseHexDashOrNull", "nameUUIDFromBytes", "fromLongs", "fromByteArray"] {
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
