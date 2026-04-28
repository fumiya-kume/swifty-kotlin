@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-EXPERIMENTAL-ABI-001: Synthetic experimental opt-in marker stubs
//
// Verifies that the Kotlin stdlib experimental annotation classes discovered
// missing in PR #1231 are now synthesised correctly:
//
//   • ExperimentalUnsignedTypes  — kotlin          — severity ERROR
//   • ExperimentalVersionOverloading — kotlin      — severity ERROR
//   • ExperimentalUuidApi        — kotlin.uuid      — severity ERROR
//   • ExperimentalEncodingApi    — kotlin.io.encoding — severity ERROR
//   • ExperimentalMultiplatform  — kotlin           — severity ERROR
//   • ExperimentalSubclassOptIn  — kotlin           — severity WARNING
//
// Each test group checks:
//   1. The annotation class symbol is present in the symbol table.
//   2. Its kind is .annotationClass.
//   3. It carries @RequiresOptIn.
//   4. The @RequiresOptIn argument encodes the correct severity level.

final class ExperimentalMarkerStubTests: XCTestCase {

    // MARK: - Shared fixture

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

    // MARK: - Helpers

    private func lookupSymbol(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let interned = fqPath.map { interner.intern($0) }
        return sema.symbols.lookup(fqName: interned)
    }

    private func assertIsAnnotationClass(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let sym = lookupSymbol(fqPath: fqPath, sema: sema, interner: interner),
              let info = sema.symbols.symbol(sym)
        else {
            XCTFail("\(fqPath.joined(separator: ".")) not found in symbol table", file: file, line: line)
            return
        }
        XCTAssertEqual(info.kind, .annotationClass, "\(fqPath.last ?? "") must have kind=annotationClass", file: file, line: line)
    }

    private func assertHasRequiresOptIn(
        fqPath: [String],
        expectedSeverity: String,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let sym = lookupSymbol(fqPath: fqPath, sema: sema, interner: interner) else {
            XCTFail("\(fqPath.joined(separator: ".")) not found in symbol table", file: file, line: line)
            return
        }
        let annotations = sema.symbols.annotations(for: sym)
        guard let requiresOptIn = annotations.first(where: { $0.annotationFQName == "kotlin.RequiresOptIn" }) else {
            XCTFail("\(fqPath.last ?? "") must carry @RequiresOptIn annotation", file: file, line: line)
            return
        }
        let hasSeverity = requiresOptIn.arguments.contains { $0.contains(expectedSeverity) }
        XCTAssertTrue(
            hasSeverity,
            "\(fqPath.last ?? "") @RequiresOptIn must declare severity=\(expectedSeverity); got \(requiresOptIn.arguments)",
            file: file,
            line: line
        )
    }

    // MARK: - ExperimentalUnsignedTypes (kotlin, ERROR)

    func testExperimentalUnsignedTypesIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "ExperimentalUnsignedTypes"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.ExperimentalUnsignedTypes must be registered in the symbol table")
    }

    func testExperimentalUnsignedTypesIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "ExperimentalUnsignedTypes"], sema: sema, interner: interner)
    }

    func testExperimentalUnsignedTypesHasRequiresOptIn() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "ExperimentalUnsignedTypes"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - ExperimentalVersionOverloading (kotlin, ERROR)

    func testExperimentalVersionOverloadingIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "ExperimentalVersionOverloading"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.ExperimentalVersionOverloading must be registered in the symbol table")
    }

    func testExperimentalVersionOverloadingIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "ExperimentalVersionOverloading"], sema: sema, interner: interner)
    }

    func testExperimentalVersionOverloadingHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "ExperimentalVersionOverloading"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - ExperimentalUuidApi (kotlin.uuid, ERROR)


    func testExperimentalUuidApiIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "uuid", "ExperimentalUuidApi"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.uuid.ExperimentalUuidApi must be registered in the symbol table")
    }

    func testExperimentalUuidApiIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "uuid", "ExperimentalUuidApi"], sema: sema, interner: interner)
    }

    func testExperimentalUuidApiHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "uuid", "ExperimentalUuidApi"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - ExperimentalEncodingApi (kotlin.io.encoding, ERROR)

    func testExperimentalEncodingApiIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(
            fqPath: ["kotlin", "io", "encoding", "ExperimentalEncodingApi"],
            sema: sema,
            interner: interner
        )
        XCTAssertNotNil(sym, "kotlin.io.encoding.ExperimentalEncodingApi must be registered in the symbol table")
    }

    func testExperimentalEncodingApiIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(
            fqPath: ["kotlin", "io", "encoding", "ExperimentalEncodingApi"],
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalEncodingApiHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "io", "encoding", "ExperimentalEncodingApi"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    func testKotlinIoEncodingPackageIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "io", "encoding"].map { interner.intern($0) }
        XCTAssertNotNil(
            sema.symbols.lookup(fqName: fq),
            "kotlin.io.encoding package must be present in the symbol table after sema"
        )
    }

    // MARK: - ExperimentalMultiplatform (kotlin, ERROR)

    func testExperimentalMultiplatformIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "ExperimentalMultiplatform"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.ExperimentalMultiplatform must be registered in the symbol table")
    }

    func testExperimentalMultiplatformIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "ExperimentalMultiplatform"], sema: sema, interner: interner)
    }

    func testExperimentalMultiplatformHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "ExperimentalMultiplatform"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - ExperimentalSubclassOptIn (kotlin, WARNING)

    func testExperimentalSubclassOptInIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "ExperimentalSubclassOptIn"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.ExperimentalSubclassOptIn must be registered in the symbol table")
    }

    func testExperimentalSubclassOptInIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "ExperimentalSubclassOptIn"], sema: sema, interner: interner)
    }

    func testExperimentalSubclassOptInHasRequiresOptInWithWarningSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "ExperimentalSubclassOptIn"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - Severity cross-check: ERROR vs WARNING are distinct

    func testErrorAndWarningSeveritiesAreDistinctAcrossMarkers() throws {
        let (sema, interner) = try makeSema()

        func severity(fqPath: [String]) -> String? {
            guard let sym = lookupSymbol(fqPath: fqPath, sema: sema, interner: interner) else {
                return nil
            }
            let annotations = sema.symbols.annotations(for: sym)
            guard let req = annotations.first(where: { $0.annotationFQName == "kotlin.RequiresOptIn" }) else {
                return nil
            }
            if req.arguments.contains(where: { $0.contains("ERROR") }) { return "ERROR" }
            if req.arguments.contains(where: { $0.contains("WARNING") }) { return "WARNING" }
            return nil
        }

        XCTAssertEqual(severity(fqPath: ["kotlin", "ExperimentalUnsignedTypes"]), "ERROR")
        XCTAssertEqual(severity(fqPath: ["kotlin", "ExperimentalVersionOverloading"]), "ERROR")
        XCTAssertEqual(severity(fqPath: ["kotlin", "uuid", "ExperimentalUuidApi"]), "ERROR")
        XCTAssertEqual(severity(fqPath: ["kotlin", "io", "encoding", "ExperimentalEncodingApi"]), "ERROR")
        XCTAssertEqual(severity(fqPath: ["kotlin", "ExperimentalMultiplatform"]), "ERROR")
        XCTAssertEqual(severity(fqPath: ["kotlin", "ExperimentalSubclassOptIn"]), "WARNING")
    }
}
