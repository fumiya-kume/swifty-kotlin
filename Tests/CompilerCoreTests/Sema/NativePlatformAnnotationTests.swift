@testable import CompilerCore
import Foundation
import XCTest

final class NativePlatformAnnotationTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    func testFreezingIsDeprecatedMarkerIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "FreezingIsDeprecated"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.FreezingIsDeprecated must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testFreezingIsDeprecatedCarriesRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "FreezingIsDeprecated"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let requiresOptIn = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.RequiresOptIn" },
            "FreezingIsDeprecated must carry @RequiresOptIn"
        )

        XCTAssertTrue(
            requiresOptIn.arguments.contains("level=RequiresOptIn.Level.WARNING"),
            "FreezingIsDeprecated must be a warning-level opt-in marker; got \(requiresOptIn.arguments)"
        )
        XCTAssertTrue(
            requiresOptIn.arguments.contains { $0.contains("Freezing API is deprecated since 1.7.20") },
            "FreezingIsDeprecated opt-in message should mention the freezing API deprecation"
        )
    }

    func testFreezingIsDeprecatedCarriesNativeTargets() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "FreezingIsDeprecated"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "FreezingIsDeprecated must carry @Target metadata"
        )
        let expectedTargets = [
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

        for expectedTarget in expectedTargets {
            XCTAssertTrue(
                target.arguments.contains(expectedTarget),
                "FreezingIsDeprecated @Target should include \(expectedTarget); got \(target.arguments)"
            )
        }
    }

    func testUsingFreezingDeprecatedApiProducesWarningDiagnostic() {
        let source = """
        import kotlin.native.FreezingIsDeprecated

        @FreezingIsDeprecated
        fun frozenApi() {}

        fun probe() {
            frozenApi()
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInWarnings = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning
        }

        XCTAssertFalse(
            optInWarnings.isEmpty,
            "Expected warning-level opt-in diagnostic for FreezingIsDeprecated API usage"
        )
    }

    func testOptingInToFreezingIsDeprecatedSuppressesDiagnostic() {
        let source = """
        @file:OptIn(kotlin.native.FreezingIsDeprecated::class)
        import kotlin.native.FreezingIsDeprecated

        @FreezingIsDeprecated
        fun frozenApi() {}

        fun probe() {
            frozenApi()
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }

        XCTAssertTrue(
            optInDiagnostics.isEmpty,
            "Expected no opt-in diagnostic when @OptIn(FreezingIsDeprecated::class) is present"
        )
    }

    func testHiddenFromObjCAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "HiddenFromObjC"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.HiddenFromObjC must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testHiddenFromObjCCarriesObjCRefinementMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "HiddenFromObjC"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)

        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.native.HidesFromObjC" },
            "HiddenFromObjC must carry @HidesFromObjC metadata"
        )
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.experimental.ExperimentalObjCRefinement" },
            "HiddenFromObjC must carry @ExperimentalObjCRefinement metadata"
        )
    }

    func testHiddenFromObjCCarriesClassFunctionPropertyTargets() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "HiddenFromObjC"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "HiddenFromObjC must carry @Target metadata"
        )

        XCTAssertEqual(
            Set(target.arguments),
            Set([
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.CLASS",
            ])
        )
    }

    func testHiddenFromObjCIsAcceptedOnClassFunctionAndProperty() {
        let source = """
        import kotlin.native.HiddenFromObjC

        @HiddenFromObjC
        class HiddenType {
            @HiddenFromObjC
            val hiddenProperty: Int = 1

            @HiddenFromObjC
            fun hiddenFunction(): Int = hiddenProperty
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(
            errors.isEmpty,
            "Expected HiddenFromObjC on class/function/property to type-check, got \(errors)"
        )
    }

    func testNoInlineAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "NoInline"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.NoInline must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testNoInlineCarriesExperimentalNativeApiMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "NoInline"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)

        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi" },
            "NoInline must carry @ExperimentalNativeApi metadata"
        )
    }

    func testNoInlineCarriesFunctionPropertyTargets() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "NoInline"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "NoInline must carry @Target metadata"
        )

        XCTAssertEqual(
            Set(target.arguments),
            Set([
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY",
            ])
        )
    }

    func testNoInlineIsAcceptedOnFunctionAndProperty() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.NoInline

        @NoInline
        val nativeValue: Int = 1

        @NoInline
        fun nativeFunction(): Int = nativeValue
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(
            errors.isEmpty,
            "Expected NoInline on function/property to type-check with ExperimentalNativeApi opt-in, got \(errors)"
        )
    }

}
