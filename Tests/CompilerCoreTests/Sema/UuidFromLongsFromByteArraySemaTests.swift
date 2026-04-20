@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-UUID-ABI-001/002: Uuid.fromLongs and Uuid.fromByteArray sema stubs
//
// Verifies that fromLongs(msb, lsb) and fromByteArray(byteArray) companion factory
// methods are registered with the correct ABI external-link names.

final class UuidFromLongsFromByteArraySemaTests: XCTestCase {

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

    // MARK: - fromLongs

    func testUuidFromLongsCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_fromLongs"),
            "Uuid.fromLongs() must link to kk_uuid_fromLongs; found: \(links)"
        )
    }

    func testUuidFromLongsAcceptsTwoLongParameters() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.fromLongs must be registered")
        let sym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("Uuid.fromLongs has no signature"); return
        }
        XCTAssertEqual(sig.parameterTypes.count, 2, "Uuid.fromLongs must take 2 Long parameters")
        XCTAssertEqual(sig.parameterTypes[0], sema.types.longType, "first param must be Long")
        XCTAssertEqual(sig.parameterTypes[1], sema.types.longType, "second param must be Long")
    }

    func testUuidFromLongsReturnTypeIsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromLongs"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.fromLongs must be registered")
        let sym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("Uuid.fromLongs has no signature"); return
        }
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            XCTFail("kotlin.uuid.Uuid class symbol missing"); return
        }
        let returnTypeKind = sema.types.kind(of: sig.returnType)
        if case .classType(let ct) = returnTypeKind {
            XCTAssertEqual(ct.classSymbol, uuidSym, "Uuid.fromLongs return type must be kotlin.uuid.Uuid")
        } else {
            XCTFail("Uuid.fromLongs return type is not a class type; got \(returnTypeKind)")
        }
    }

    // MARK: - fromByteArray

    func testUuidFromByteArrayCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_uuid_fromByteArray"),
            "Uuid.fromByteArray() must link to kk_uuid_fromByteArray; found: \(links)"
        )
    }

    func testUuidFromByteArrayAcceptsOneParameter() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.fromByteArray must be registered")
        let sym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("Uuid.fromByteArray has no signature"); return
        }
        XCTAssertEqual(sig.parameterTypes.count, 1, "Uuid.fromByteArray must take 1 parameter")
        let byteArrayFQ = ["kotlin", "ByteArray"].map { interner.intern($0) }
        guard let byteArraySym = sema.symbols.lookup(fqName: byteArrayFQ) else {
            XCTFail("kotlin.ByteArray class symbol missing"); return
        }
        let expectedByteArrayType = sema.types.make(.classType(ClassType(
            classSymbol: byteArraySym,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(
            sig.parameterTypes[0],
            expectedByteArrayType,
            "Uuid.fromByteArray parameter must be of type ByteArray"
        )
    }

    func testUuidFromByteArrayReturnTypeIsUuid() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "uuid", "Uuid", "Companion", "fromByteArray"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Uuid.fromByteArray must be registered")
        let sym = try XCTUnwrap(syms.first)
        guard let sig = sema.symbols.functionSignature(for: sym) else {
            XCTFail("Uuid.fromByteArray has no signature"); return
        }
        let uuidFQ = ["kotlin", "uuid", "Uuid"].map { interner.intern($0) }
        guard let uuidSym = sema.symbols.lookup(fqName: uuidFQ) else {
            XCTFail("kotlin.uuid.Uuid class symbol missing"); return
        }
        let returnTypeKind = sema.types.kind(of: sig.returnType)
        if case .classType(let ct) = returnTypeKind {
            XCTAssertEqual(ct.classSymbol, uuidSym, "Uuid.fromByteArray return type must be kotlin.uuid.Uuid")
        } else {
            XCTFail("Uuid.fromByteArray return type is not a class type; got \(returnTypeKind)")
        }
    }

    // MARK: - Full companion link surface

    func testAllNewCompanionLinksArePresent() throws {
        let (sema, interner) = try makeSema()
        let companionFQ = ["kotlin", "uuid", "Uuid", "Companion"]
        let requiredLinks: Set<String> = [
            "kk_uuid_fromLongs",
            "kk_uuid_fromByteArray",
        ]
        var foundLinks: Set<String> = []
        for memberName in ["fromLongs", "fromByteArray"] {
            let path = companionFQ + [memberName]
            let interned = path.map { interner.intern($0) }
            let links = Set(
                sema.symbols.lookupAll(fqName: interned)
                    .compactMap { sema.symbols.externalLinkName(for: $0) }
            )
            foundLinks.formUnion(links)
        }
        XCTAssertTrue(
            requiredLinks.isSubset(of: foundLinks),
            "fromLongs and fromByteArray companion methods must be registered; found: \(foundLinks)"
        )
    }
}
