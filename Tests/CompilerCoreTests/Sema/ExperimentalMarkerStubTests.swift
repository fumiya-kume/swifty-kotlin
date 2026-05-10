@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-EXPERIMENTAL-ABI-001: Synthetic experimental opt-in marker stubs
//
// Verifies that the Kotlin stdlib experimental annotation classes discovered
// missing in PR #1231 are now synthesised correctly:
//
//   • ExperimentalUnsignedTypes  — kotlin          — severity ERROR
//   • ExperimentalVersionOverloading — kotlin       — severity ERROR
//   • ExperimentalContextParameters — kotlin        — severity ERROR
//   • ExperimentalUuidApi        — kotlin.uuid      — severity ERROR
//   • ExperimentalEncodingApi    — kotlin.io.encoding — severity ERROR
//   • ExperimentalWasmInterop    — kotlin.wasm      — severity WARNING
//   • ExperimentalMultiplatform  — kotlin           — severity ERROR
//   • ExperimentalSubclassOptIn  — kotlin           — severity WARNING
//   • ExperimentalAssociatedObjects — kotlin.reflect — severity ERROR
//
// Each test group checks:
//   1. The annotation class symbol is present in the symbol table.
//   2. Its kind is .annotationClass.
//   3. It carries @RequiresOptIn.
//   4. The @RequiresOptIn argument encodes the correct severity level.

final class ExperimentalMarkerStubTests: XCTestCase {
    private struct ExperimentalPackageMarker: Hashable {
        let name: String
        let todo: String?
    }

    private static let implementedExperimentalPackageMarkers: Set<ExperimentalPackageMarker> = [
        ExperimentalPackageMarker(name: "ExperimentalNativeApi", todo: nil),
        ExperimentalPackageMarker(name: "ExperimentalObjCEnum", todo: nil),
        ExperimentalPackageMarker(name: "ExperimentalObjCName", todo: nil),
        ExperimentalPackageMarker(name: "ExperimentalObjCRefinement", todo: nil),
        ExperimentalPackageMarker(name: "ExperimentalTypeInference", todo: nil),
        ExperimentalPackageMarker(name: "ExpectRefinement", todo: nil),
    ]

    private static let knownGapExperimentalPackageMarkers: Set<ExperimentalPackageMarker> = []

    private static let optInExperimentalPackageMarkerNames: [String] = [
        "ExperimentalNativeApi",
        "ExperimentalObjCEnum",
        "ExperimentalObjCName",
        "ExperimentalObjCRefinement",
    ]

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

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are inspected per-test.
        }
        return ctx
    }

    private func runSemaCollectingDiagnostics(_ sources: [String]) -> CompilationContext {
        let ctx = makeContextFromSources(sources)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are inspected per-test.
        }
        return ctx
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
        file: StaticString = #filePath,
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
        file: StaticString = #filePath,
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

    // MARK: - ExperimentalContextParameters (kotlin, ERROR)

    func testExperimentalContextParametersIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "ExperimentalContextParameters"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.ExperimentalContextParameters must be registered in the symbol table")
    }

    func testExperimentalContextParametersIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "ExperimentalContextParameters"], sema: sema, interner: interner)
    }

    func testExperimentalContextParametersHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "ExperimentalContextParameters"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalContextParametersRequiresOptInMessageMentionsContextParameters() throws {
        let (sema, interner) = try makeSema()
        let sym = try XCTUnwrap(
            lookupSymbol(fqPath: ["kotlin", "ExperimentalContextParameters"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: sym)
        let requiresOptIn = try XCTUnwrap(annotations.first { $0.annotationFQName == "kotlin.RequiresOptIn" })
        XCTAssertTrue(
            requiresOptIn.arguments.contains { $0.contains("context parameters") },
            "Expected ExperimentalContextParameters @RequiresOptIn message to mention context parameters, got: \(requiresOptIn.arguments)"
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

    // MARK: - ExperimentalWasmInterop (kotlin.wasm, WARNING)

    func testExperimentalWasmInteropIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "wasm", "ExperimentalWasmInterop"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.wasm.ExperimentalWasmInterop must be registered in the symbol table")
    }

    func testExperimentalWasmInteropIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "wasm", "ExperimentalWasmInterop"], sema: sema, interner: interner)
    }

    func testExperimentalWasmInteropHasRequiresOptInWithWarningSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "wasm", "ExperimentalWasmInterop"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - ExperimentalPathApi (kotlin.io.path, ERROR)

    func testExperimentalPathApiIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(
            fqPath: ["kotlin", "io", "path", "ExperimentalPathApi"],
            sema: sema,
            interner: interner
        )
        XCTAssertNotNil(sym, "kotlin.io.path.ExperimentalPathApi must be registered in the symbol table")
    }

    func testExperimentalPathApiIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(
            fqPath: ["kotlin", "io", "path", "ExperimentalPathApi"],
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalPathApiHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "io", "path", "ExperimentalPathApi"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalPathApiHasOfficialTargets() throws {
        let (sema, interner) = try makeSema()
        let sym = try XCTUnwrap(
            lookupSymbol(fqPath: ["kotlin", "io", "path", "ExperimentalPathApi"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: sym)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.ANNOTATION_CLASS",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.FIELD",
                        "AnnotationTarget.LOCAL_VARIABLE",
                        "AnnotationTarget.VALUE_PARAMETER",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY_GETTER",
                        "AnnotationTarget.PROPERTY_SETTER",
                        "AnnotationTarget.TYPEALIAS",
                    ]
            },
            "ExperimentalPathApi must carry the official @Target list, got \(annotations)"
        )
    }

    // MARK: - ExperimentalAssociatedObjects (kotlin.reflect, ERROR)

    func testExperimentalAssociatedObjectsIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(
            fqPath: ["kotlin", "reflect", "ExperimentalAssociatedObjects"],
            sema: sema,
            interner: interner
        )
        XCTAssertNotNil(sym, "kotlin.reflect.ExperimentalAssociatedObjects must be registered in the symbol table")
    }

    func testExperimentalAssociatedObjectsIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(
            fqPath: ["kotlin", "reflect", "ExperimentalAssociatedObjects"],
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalAssociatedObjectsHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "reflect", "ExperimentalAssociatedObjects"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalAssociatedObjectsHasBinaryRetention() throws {
        let (sema, interner) = try makeSema()
        let sym = try XCTUnwrap(
            lookupSymbol(fqPath: ["kotlin", "reflect", "ExperimentalAssociatedObjects"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: sym)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments.contains("AnnotationRetention.BINARY")
            },
            "Expected ExperimentalAssociatedObjects to carry @Retention(BINARY), got: \(annotations)"
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
        XCTAssertEqual(severity(fqPath: ["kotlin", "ExperimentalContextParameters"]), "ERROR")
        XCTAssertEqual(severity(fqPath: ["kotlin", "uuid", "ExperimentalUuidApi"]), "ERROR")
        XCTAssertEqual(severity(fqPath: ["kotlin", "io", "encoding", "ExperimentalEncodingApi"]), "ERROR")
        XCTAssertEqual(severity(fqPath: ["kotlin", "reflect", "ExperimentalAssociatedObjects"]), "ERROR")
        XCTAssertEqual(severity(fqPath: ["kotlin", "ExperimentalMultiplatform"]), "ERROR")
        XCTAssertEqual(severity(fqPath: ["kotlin", "ExperimentalSubclassOptIn"]), "WARNING")
    }

    // MARK: - kotlin.experimental marker inventory

    func testKotlinExperimentalMarkerInventoryHasExpectedShape() {
        let targetMarkers = Self.implementedExperimentalPackageMarkers.union(Self.knownGapExperimentalPackageMarkers)
        let targetNames = Set(targetMarkers.map(\.name))

        XCTAssertEqual(targetMarkers.count, targetNames.count)
        XCTAssertEqual(targetMarkers.count, 6)
        XCTAssertEqual(Self.implementedExperimentalPackageMarkers.count, 6)
        XCTAssertEqual(Self.knownGapExperimentalPackageMarkers.count, 0)
    }

    func testImplementedKotlinExperimentalMarkersAreRegistered() throws {
        let (sema, interner) = try makeSema()

        for marker in Self.implementedExperimentalPackageMarkers {
            let symbol = try XCTUnwrap(
                lookupSymbol(fqPath: ["kotlin", "experimental", marker.name], sema: sema, interner: interner),
                "kotlin.experimental.\(marker.name) should be registered"
            )
            XCTAssertEqual(
                sema.symbols.symbol(symbol)?.kind,
                .annotationClass,
                "kotlin.experimental.\(marker.name) should be an annotation class"
            )
        }
    }

    func testKnownGapKotlinExperimentalMarkersRemainAbsentUntilTheirTodoIsImplemented() throws {
        let (sema, interner) = try makeSema()

        for marker in Self.knownGapExperimentalPackageMarkers {
            let symbol = lookupSymbol(fqPath: ["kotlin", "experimental", marker.name], sema: sema, interner: interner)
            XCTAssertNil(
                symbol,
                "kotlin.experimental.\(marker.name) is tracked by \(marker.todo ?? "unknown TODO") and should update this inventory when implemented"
            )
        }
    }

    func testKnownGapKotlinExperimentalMarkerTodosAreScoped() {
        let todos = Set(Self.knownGapExperimentalPackageMarkers.compactMap(\.todo))
        XCTAssertEqual(todos, Set<String>())
    }

    func testExpectRefinementCarriesClassTargetAndExperimentalMultiplatformMetadata() throws {
        let (sema, interner) = try makeSema()
        let symbol = try XCTUnwrap(
            lookupSymbol(fqPath: ["kotlin", "experimental", "ExpectRefinement"], sema: sema, interner: interner),
            "kotlin.experimental.ExpectRefinement should be registered"
        )
        let annotations = sema.symbols.annotations(for: symbol)

        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == ["AnnotationTarget.CLASS"]
            },
            "ExpectRefinement should carry @Target(AnnotationTarget.CLASS), got \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.ExperimentalMultiplatform" },
            "ExpectRefinement should carry @ExperimentalMultiplatform, got \(annotations)"
        )
    }

    func testExpectRefinementMetadataIsExposedOnExpectDeclaration() throws {
        let sources = [
            """
            @file:OptIn(kotlin.ExperimentalMultiplatform::class)

            package sample.exp

            import kotlin.experimental.ExpectRefinement

            @ExpectRefinement
            expect class Refined
            """,
            """
            package sample.exp

            actual class Refined
            """,
        ]

        let ctx = runSemaCollectingDiagnostics(sources)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "Expected expect/actual refined class to compile cleanly, got \(ctx.diagnostics.diagnostics)")

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = ["sample", "exp", "Refined"].map { ctx.interner.intern($0) }
        let refinedSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                sema.symbols.symbol(symbolID)?.flags.contains(.expectDeclaration) == true
            },
            "Expected expect Refined symbol to be registered"
        )
        let annotations = sema.symbols.annotations(for: refinedSymbol)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.experimental.ExpectRefinement"
                    || $0.annotationFQName == "ExpectRefinement"
            },
            "Expected @ExpectRefinement metadata on expect declaration, got \(annotations)"
        )
    }

    func testExpectRefinementUseRequiresExperimentalMultiplatformOptIn() {
        let sources = [
            """
            package sample.exp

            import kotlin.experimental.ExpectRefinement

            @ExpectRefinement
            expect class NeedsOptIn

            fun echo(value: NeedsOptIn): NeedsOptIn = value
            """,
            """
            package sample.exp

            actual class NeedsOptIn
            """,
        ]

        let ctx = runSemaCollectingDiagnostics(sources)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        XCTAssertTrue(
            diagnostics.contains {
                $0.severity == .error && $0.message.contains("kotlin.ExperimentalMultiplatform")
            },
            "Expected ExpectRefinement usage to require ExperimentalMultiplatform opt-in, got \(ctx.diagnostics.diagnostics)"
        )
    }

    func testExpectRefinementAcceptsExperimentalMultiplatformOptIn() {
        let sources = [
            """
            @file:OptIn(kotlin.ExperimentalMultiplatform::class)

            package sample.exp

            import kotlin.experimental.ExpectRefinement

            @ExpectRefinement
            expect class RefinedWithOptIn

            fun echo(value: RefinedWithOptIn): RefinedWithOptIn = value
            """,
            """
            package sample.exp

            actual class RefinedWithOptIn
            """,
        ]

        let ctx = runSemaCollectingDiagnostics(sources)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        XCTAssertTrue(
            diagnostics.isEmpty,
            "Expected @OptIn(kotlin.ExperimentalMultiplatform::class) to suppress ExpectRefinement diagnostics, got \(ctx.diagnostics.diagnostics)"
        )
    }

    func testExpectRefinementRejectsFunctionTarget() {
        let source = """
        @file:OptIn(kotlin.ExperimentalMultiplatform::class)

        import kotlin.experimental.ExpectRefinement

        @ExpectRefinement
        fun invalidRefinementTarget() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
        XCTAssertEqual(
            diagnostics.count,
            1,
            "Expected ExpectRefinement to reject function target, got \(ctx.diagnostics.diagnostics)"
        )
        XCTAssertTrue(
            diagnostics.allSatisfy { $0.severity == .error },
            "ExpectRefinement target diagnostics should be errors"
        )
    }

    func testKotlinExperimentalOptInMarkersCarryRequiresOptInError() throws {
        let (sema, interner) = try makeSema()

        for marker in Self.optInExperimentalPackageMarkerNames {
            let symbol = try XCTUnwrap(
                lookupSymbol(fqPath: ["kotlin", "experimental", marker], sema: sema, interner: interner),
                "kotlin.experimental.\(marker) should be registered"
            )
            let annotations = sema.symbols.annotations(for: symbol)
            XCTAssertTrue(
                annotations.contains {
                    $0.annotationFQName == "kotlin.RequiresOptIn"
                        && $0.arguments.contains("level=RequiresOptIn.Level.ERROR")
                },
                "kotlin.experimental.\(marker) should carry @RequiresOptIn(ERROR), got \(annotations)"
            )
        }
    }

    func testKotlinExperimentalOptInMarkersEmitDiagnosticsOnUse() {
        for marker in Self.optInExperimentalPackageMarkerNames {
            let source = """
            import kotlin.experimental.\(marker)

            @\(marker)
            @Target(AnnotationTarget.FUNCTION)
            annotation class Uses\(marker)

            @Uses\(marker)
            fun experimental\(marker)(): Int = 1

            fun use\(marker)(): Int = experimental\(marker)()
            """

            let ctx = runSemaCollectingDiagnostics(source)
            let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
            XCTAssertTrue(
                diagnostics.contains { $0.severity == .error },
                "Expected \(marker) use to emit an opt-in error, got \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    func testKotlinExperimentalOptInMarkersAcceptExplicitOptIn() {
        for marker in Self.optInExperimentalPackageMarkerNames {
            let source = """
            @file:OptIn(kotlin.experimental.\(marker)::class)
            import kotlin.experimental.\(marker)

            @\(marker)
            @Target(AnnotationTarget.FUNCTION)
            annotation class Uses\(marker)

            @Uses\(marker)
            fun experimental\(marker)(): Int = 1

            fun use\(marker)(): Int = experimental\(marker)()
            """

            let ctx = runSemaCollectingDiagnostics(source)
            let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
            XCTAssertTrue(
                diagnostics.isEmpty,
                "Expected @OptIn(\(marker)::class) to suppress opt-in diagnostics, got \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    // MARK: - ExperimentalJsCollectionsApi (kotlin.js, WARNING)

    func testExperimentalJsCollectionsApiIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsCollectionsApi"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.js.ExperimentalJsCollectionsApi must be registered in the symbol table")
    }

    func testExperimentalJsCollectionsApiIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "js", "ExperimentalJsCollectionsApi"], sema: sema, interner: interner)
    }

    func testExperimentalJsCollectionsApiHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalJsCollectionsApi"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalJsCollectionsApiHasOfficialTargets() throws {
        let (sema, interner) = try makeSema()
        let symbol = try XCTUnwrap(
            lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsCollectionsApi"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: symbol)
        let target = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "ExperimentalJsCollectionsApi should carry explicit @Target metadata"
        )
        XCTAssertEqual(
            Set(target.arguments),
            Set([
                "AnnotationTarget.CLASS",
                "AnnotationTarget.FUNCTION",
            ])
        )
    }

    // MARK: - ExperimentalJsExport (kotlin.js, WARNING)

    func testExperimentalJsExportIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsExport"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.js.ExperimentalJsExport must be registered in the symbol table")
    }

    func testExperimentalJsExportIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "js", "ExperimentalJsExport"], sema: sema, interner: interner)
    }

    func testExperimentalJsExportHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalJsExport"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalJsExportDoesNotCarryExplicitTargetMetadata() throws {
        let (sema, interner) = try makeSema()
        let symbol = try XCTUnwrap(
            lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsExport"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: symbol)

        XCTAssertFalse(
            annotations.contains { $0.annotationFQName == "kotlin.annotation.Target" },
            "ExperimentalJsExport should not carry explicit @Target metadata, got \(annotations)"
        )
    }

    // MARK: - ExperimentalJsFileName (kotlin.js, WARNING)

    func testExperimentalJsFileNameIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsFileName"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.js.ExperimentalJsFileName must be registered in the symbol table")
    }

    func testExperimentalJsFileNameIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "js", "ExperimentalJsFileName"], sema: sema, interner: interner)
    }

    func testExperimentalJsFileNameHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalJsFileName"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalJsFileNameDoesNotCarryExplicitTargetMetadata() throws {
        let (sema, interner) = try makeSema()
        let symbol = try XCTUnwrap(
            lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsFileName"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: symbol)

        XCTAssertFalse(
            annotations.contains { $0.annotationFQName == "kotlin.annotation.Target" },
            "ExperimentalJsFileName should not carry explicit @Target metadata, got \(annotations)"
        )
    }

    // MARK: - ExperimentalJsReflectionCreateInstance (kotlin.js, WARNING)

    func testExperimentalJsReflectionCreateInstanceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(
            fqPath: ["kotlin", "js", "ExperimentalJsReflectionCreateInstance"],
            sema: sema,
            interner: interner
        )
        XCTAssertNotNil(sym, "kotlin.js.ExperimentalJsReflectionCreateInstance must be registered in the symbol table")
    }

    func testExperimentalJsReflectionCreateInstanceIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(
            fqPath: ["kotlin", "js", "ExperimentalJsReflectionCreateInstance"],
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalJsReflectionCreateInstanceHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalJsReflectionCreateInstance"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalJsReflectionCreateInstanceHasOfficialTargets() throws {
        let (sema, interner) = try makeSema()
        let symbol = try XCTUnwrap(
            lookupSymbol(
                fqPath: ["kotlin", "js", "ExperimentalJsReflectionCreateInstance"],
                sema: sema,
                interner: interner
            )
        )
        let annotations = sema.symbols.annotations(for: symbol)
        let target = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "ExperimentalJsReflectionCreateInstance should carry explicit @Target metadata"
        )
        XCTAssertEqual(
            Set(target.arguments),
            Set([
                "AnnotationTarget.CLASS",
                "AnnotationTarget.ANNOTATION_CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FIELD",
                "AnnotationTarget.LOCAL_VARIABLE",
                "AnnotationTarget.VALUE_PARAMETER",
                "AnnotationTarget.CONSTRUCTOR",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY_GETTER",
                "AnnotationTarget.PROPERTY_SETTER",
                "AnnotationTarget.TYPEALIAS",
            ])
        )
    }

    // MARK: - ExperimentalJsStatic (kotlin.js, WARNING)

    func testExperimentalJsStaticIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsStatic"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.js.ExperimentalJsStatic must be registered in the symbol table")
    }

    func testExperimentalJsStaticIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "js", "ExperimentalJsStatic"], sema: sema, interner: interner)
    }

    func testExperimentalJsStaticHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalJsStatic"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalJsStaticDoesNotCarryExplicitTargetMetadata() throws {
        let (sema, interner) = try makeSema()
        let symbol = try XCTUnwrap(
            lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsStatic"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: symbol)

        XCTAssertFalse(
            annotations.contains { $0.annotationFQName == "kotlin.annotation.Target" },
            "ExperimentalJsStatic should not carry explicit @Target metadata, got \(annotations)"
        )
    }

    // MARK: - ExperimentalWasmJsInterop (kotlin.js, WARNING)

    func testExperimentalWasmJsInteropIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalWasmJsInterop"], sema: sema, interner: interner)
        XCTAssertNotNil(sym, "kotlin.js.ExperimentalWasmJsInterop must be registered in the symbol table")
    }

    func testExperimentalWasmJsInteropIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "js", "ExperimentalWasmJsInterop"], sema: sema, interner: interner)
    }

    func testExperimentalWasmJsInteropHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalWasmJsInterop"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    func testExperimentalWasmJsInteropHasOfficialTargets() throws {
        let (sema, interner) = try makeSema()
        let symbol = try XCTUnwrap(
            lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalWasmJsInterop"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: symbol)
        let target = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "ExperimentalWasmJsInterop should carry explicit @Target metadata"
        )
        XCTAssertEqual(
            Set(target.arguments),
            Set([
                "AnnotationTarget.CLASS",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.TYPEALIAS",
            ])
        )
    }
}
