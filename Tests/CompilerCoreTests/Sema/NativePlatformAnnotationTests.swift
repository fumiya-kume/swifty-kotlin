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
        @file:OptIn(kotlin.experimental.ExperimentalObjCRefinement::class)
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
            "Expected HiddenFromObjC on class/function/property to type-check with ObjC refinement opt-in, got \(errors)"
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

    func testObsoleteNativeApiMarkerIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "ObsoleteNativeApi"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.ObsoleteNativeApi must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testObsoleteNativeApiCarriesRequiresOptInError() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "ObsoleteNativeApi"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let requiresOptIn = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.RequiresOptIn" },
            "ObsoleteNativeApi must carry @RequiresOptIn"
        )

        XCTAssertTrue(
            requiresOptIn.arguments.contains("level=RequiresOptIn.Level.ERROR"),
            "ObsoleteNativeApi must be an error-level opt-in marker; got \(requiresOptIn.arguments)"
        )
        XCTAssertTrue(
            requiresOptIn.arguments.contains { $0.contains("obsolete and subject to removal") },
            "ObsoleteNativeApi opt-in message should mention removal risk"
        )
    }

    func testObsoleteNativeApiCarriesNativeTargets() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "ObsoleteNativeApi"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "ObsoleteNativeApi must carry @Target metadata"
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
                "ObsoleteNativeApi @Target should include \(expectedTarget); got \(target.arguments)"
            )
        }
    }

    func testUsingObsoleteNativeApiWithoutOptInProducesErrorDiagnostic() {
        let source = """
        import kotlin.native.ObsoleteNativeApi

        @ObsoleteNativeApi
        fun obsoleteApi() {}

        fun probe() {
            obsoleteApi()
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInErrors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error
        }

        XCTAssertFalse(
            optInErrors.isEmpty,
            "Expected error-level opt-in diagnostic for ObsoleteNativeApi usage"
        )
    }

    func testOptingInToObsoleteNativeApiSuppressesDiagnostic() {
        let source = """
        @file:OptIn(kotlin.native.ObsoleteNativeApi::class)
        import kotlin.native.ObsoleteNativeApi

        @ObsoleteNativeApi
        fun obsoleteApi() {}

        fun probe() {
            obsoleteApi()
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }

        XCTAssertTrue(
            optInDiagnostics.isEmpty,
            "Expected no opt-in diagnostic when @OptIn(ObsoleteNativeApi::class) is present"
        )
    }

    func testEagerInitializationAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "EagerInitialization"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.EagerInitialization must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
    }

    func testEagerInitializationCarriesStdlibMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "native", "EagerInitialization"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)
        let target = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "EagerInitialization must carry @Target metadata"
        )
        let retention = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "EagerInitialization must carry @Retention metadata"
        )
        let deprecated = try XCTUnwrap(
            annotations.first { $0.annotationFQName == "kotlin.Deprecated" },
            "EagerInitialization must carry @Deprecated metadata"
        )

        XCTAssertEqual(Set(target.arguments), Set(["AnnotationTarget.PROPERTY"]))
        XCTAssertEqual(retention.arguments, ["AnnotationRetention.BINARY"])
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.ExperimentalStdlibApi" },
            "EagerInitialization must carry @ExperimentalStdlibApi metadata"
        )
        XCTAssertTrue(
            deprecated.arguments.contains { $0.contains("temporal migration assistance") },
            "EagerInitialization deprecation message should mention temporary migration assistance"
        )
    }

    func testEagerInitializationIsAcceptedOnPropertyWithStdlibOptIn() {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
        import kotlin.native.EagerInitialization

        @EagerInitialization
        val eagerValue: Int = 1
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        XCTAssertTrue(
            errors.isEmpty,
            "Expected EagerInitialization on a property to type-check with ExperimentalStdlibApi opt-in, got \(errors)"
        )
    }

}
