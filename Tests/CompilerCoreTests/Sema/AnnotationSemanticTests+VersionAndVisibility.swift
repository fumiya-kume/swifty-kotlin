@testable import CompilerCore
import Foundation
import XCTest

/// `SinceKotlin` / data-class copy-visibility / DSL-marker / and other
/// version- and visibility-related annotation tests, split out from
/// `AnnotationSemanticTests` to keep each test source under ~1500 lines.
extension AnnotationSemanticTests {
    func testSinceKotlinSurfaceHasVersionPropertyConstructorAndTargets() throws {
        let source = """
        class Host
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let sinceKotlinFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("SinceKotlin"),
        ]
        let symbolID = try XCTUnwrap(
            sema.symbols.lookup(fqName: sinceKotlinFQName),
            "kotlin.SinceKotlin must be registered"
        )
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))

        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertEqual(symbol.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbolID)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.FIELD",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY_GETTER",
                        "AnnotationTarget.PROPERTY_SETTER",
                        "AnnotationTarget.TYPEALIAS",
                    ]
            },
            "SinceKotlin should carry declaration target metadata, got: \(annotations)"
        )

        let versionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: sinceKotlinFQName + [ctx.interner.intern("version")]),
            "SinceKotlin.version property must be registered"
        )
        XCTAssertEqual(sema.symbols.propertyType(for: versionSymbol), sema.types.stringType)

        let constructors = sema.symbols.lookupAll(fqName: sinceKotlinFQName + [ctx.interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(
            constructors.lazy.compactMap { sema.symbols.functionSignature(for: $0) }.first { signature in
                signature.parameterTypes == [sema.types.stringType]
            },
            "SinceKotlin(version: String) constructor must be registered"
        )
        XCTAssertEqual(constructorSignature.valueParameterSymbols.count, 1)
        let parameter = try XCTUnwrap(sema.symbols.symbol(constructorSignature.valueParameterSymbols[0]))
        XCTAssertEqual(ctx.interner.resolve(parameter.name), "version")
    }

    func testSinceKotlinAcceptsDocumentedDeclarationTargets() {
        let source = """
        @SinceKotlin("1.0")
        class Stable {
            @SinceKotlin(version = "1.1")
            val value: Int = 1

            @SinceKotlin("1.2")
            fun expose(): Int = value
        }

        @SinceKotlin("1.3")
        typealias StableAlias = Stable
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected SinceKotlin declaration targets to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    func testSinceKotlinRejectsFileTarget() {
        let source = """
        @file:SinceKotlin("1.0")

        package sample
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected SinceKotlin to reject file target, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testDslMarkerSurfaceHasDocumentedMetadata() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let dslMarkerFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("DslMarker"),
        ]
        let symbolID = try XCTUnwrap(
            sema.symbols.lookup(fqName: dslMarkerFQName),
            "kotlin.DslMarker must be registered"
        )
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))

        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertEqual(symbol.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbolID)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
            },
            "DslMarker should target annotation classes, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.BINARY"]
            },
            "DslMarker should carry binary retention, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" },
            "DslMarker should carry MustBeDocumented, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                KnownCompilerAnnotation.sinceKotlin.matches($0.annotationFQName)
                    && $0.arguments == ["1.1"]
            },
            "DslMarker should carry SinceKotlin(1.1), got: \(annotations)"
        )
    }

    func testDslMarkerAcceptsAnnotationClassTarget() {
        let source = """
        @DslMarker
        annotation class HtmlDsl
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected DslMarker to be accepted on annotation classes, got: \(ctx.diagnostics.diagnostics)")
    }

    func testDslMarkerRejectsRegularClassTarget() {
        let source = """
        @DslMarker
        class BadMarker
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected annotation-class-only target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testIntroducedAtSurfaceHasVersionPropertyConstructorAndValueParameterTarget() throws {
        let source = """
        class Host
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let introducedAtFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("IntroducedAt"),
        ]
        let symbolID = try XCTUnwrap(
            sema.symbols.lookup(fqName: introducedAtFQName),
            "kotlin.IntroducedAt must be registered"
        )
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))

        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertEqual(symbol.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbolID)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.VALUE_PARAMETER"]
            },
            "IntroducedAt should target value parameters, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" },
            "IntroducedAt should be documented in the public API, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                KnownCompilerAnnotation.experimentalVersionOverloading.matches($0.annotationFQName)
            },
            "IntroducedAt should require ExperimentalVersionOverloading opt-in, got: \(annotations)"
        )

        let versionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: introducedAtFQName + [ctx.interner.intern("version")]),
            "IntroducedAt.version property must be registered"
        )
        XCTAssertEqual(sema.symbols.propertyType(for: versionSymbol), sema.types.stringType)

        let constructors = sema.symbols.lookupAll(fqName: introducedAtFQName + [ctx.interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(
            constructors.lazy.compactMap { sema.symbols.functionSignature(for: $0) }.first { signature in
                signature.parameterTypes == [sema.types.stringType]
            },
            "IntroducedAt(version: String) constructor must be registered"
        )
        XCTAssertEqual(constructorSignature.valueParameterSymbols.count, 1)
        let parameter = try XCTUnwrap(sema.symbols.symbol(constructorSignature.valueParameterSymbols[0]))
        XCTAssertEqual(ctx.interner.resolve(parameter.name), "version")
    }

    func testIntroducedAtAllowsValueParameterUse() {
        let source = """
        fun sample(@IntroducedAt("1.1") value: Int = 0): Int = value
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected IntroducedAt value-parameter target to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    func testIntroducedAtRejectsClassTarget() {
        let source = """
        @IntroducedAt("1.1")
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected IntroducedAt to reject class target, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testOptionalExpectationSurfaceIsSyntheticTargetedAndExperimental() throws {
        let source = """
        class Host
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let optionalExpectationFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("OptionalExpectation"),
        ]
        let symbolID = try XCTUnwrap(
            sema.symbols.lookup(fqName: optionalExpectationFQName),
            "kotlin.OptionalExpectation must be registered"
        )
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))

        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertEqual(symbol.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbolID)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
            },
            "OptionalExpectation should target annotation classes, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.ExperimentalMultiplatform" },
            "OptionalExpectation should require ExperimentalMultiplatform opt-in, got: \(annotations)"
        )
    }

    func testOptionalExpectationAcceptsAnnotationClassTarget() {
        let source = """
        @OptionalExpectation
        annotation class PlatformMarker
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected OptionalExpectation annotation-class target to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    func testOptionalExpectationRejectsFunctionTarget() {
        let source = """
        @OptIn(ExperimentalMultiplatform::class)
        @OptionalExpectation
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected OptionalExpectation to reject function target, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testRootThrowsSurfaceHasVarargKClassPropertyConstructorAndTargets() throws {
        let source = """
        class Host
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let throwsFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("Throws"),
        ]
        let symbolID = try XCTUnwrap(
            sema.symbols.lookup(fqName: throwsFQName),
            "kotlin.Throws must be registered"
        )
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))

        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertEqual(symbol.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbolID)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == [
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY_GETTER",
                        "AnnotationTarget.PROPERTY_SETTER",
                        "AnnotationTarget.CONSTRUCTOR",
                    ]
            },
            "Throws should carry function/getter/setter/constructor target metadata, got: \(annotations)"
        )

        let exceptionClassesSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: throwsFQName + [ctx.interner.intern("exceptionClasses")]),
            "Throws.exceptionClasses property must be registered"
        )
        let exceptionClassesType = try XCTUnwrap(sema.symbols.propertyType(for: exceptionClassesSymbol))
        try assertArrayOfOutThrowableKClass(exceptionClassesType, in: sema, interner: ctx.interner)

        let constructors = sema.symbols.lookupAll(fqName: throwsFQName + [ctx.interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(
            constructors.lazy.compactMap { sema.symbols.functionSignature(for: $0) }.first { signature in
                signature.valueParameterIsVararg == [true]
                    && signature.valueParameterSymbols.count == 1
            },
            "Throws(vararg exceptionClasses: KClass<out Throwable>) constructor must be registered"
        )
        try assertThrowableKClass(constructorSignature.parameterTypes[0], in: sema, interner: ctx.interner)
        let parameter = try XCTUnwrap(sema.symbols.symbol(constructorSignature.valueParameterSymbols[0]))
        XCTAssertEqual(ctx.interner.resolve(parameter.name), "exceptionClasses")
    }

    func testRootThrowsAcceptsDocumentedDeclarationTargets() {
        let source = """
        class Host @Throws(Throwable::class) constructor() {
            @get:Throws(Throwable::class)
            val readonly: Int = 1

            @set:Throws(Throwable::class)
            var value: Int = 0

            @Throws(Throwable::class)
            fun expose(): Int = value
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected Throws declaration targets to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    func testRootThrowsRejectsClassTarget() {
        let source = """
        @Throws(Throwable::class)
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected Throws to reject class target, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testTargetAnnotationIsRejectedOnRegularClass() {
        let source = """
        @Target(AnnotationTarget.CLASS)
        class BadTarget
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one annotation-target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testTargetAnnotationAllowsAnnotationClassButRejectsFunctionUsage() {
        let source = """
        @Target(AnnotationTarget.CLASS)
        annotation class ClassOnly

        @ClassOnly
        class Good

        @ClassOnly
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected exactly one annotation-target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testMustBeDocumentedAnnotationIsSyntheticAndTargetedToAnnotationClasses() throws {
        let source = """
        annotation class ExperimentalApi
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let mustBeDocumentedFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("annotation"),
            ctx.interner.intern("MustBeDocumented"),
        ]
        let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: mustBeDocumentedFQName))
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))

        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertEqual(symbol.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol.id)
        XCTAssertTrue(
            annotations.contains(
                where: {
                    $0.annotationFQName == "kotlin.annotation.Target"
                        && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
                }
            ),
            "Expected MustBeDocumented to carry @Target(AnnotationTarget.ANNOTATION_CLASS), got: \(annotations)"
        )
    }

    func testAnnotationClassInheritsKotlinAnnotation() throws {
        let source = """
        annotation class MyAnnotation
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let kotlinAnnotationSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern("Annotation")])
        )
        let myAnnotationSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [ctx.interner.intern("MyAnnotation")])
        )

        XCTAssertEqual(sema.symbols.symbol(myAnnotationSymbol)?.kind, .annotationClass)
        XCTAssertTrue(
            sema.symbols.directSupertypes(for: myAnnotationSymbol).contains(kotlinAnnotationSymbol),
            "Annotation classes should implicitly inherit kotlin.Annotation"
        )
    }

    func testExperimentalContractsAnnotationIsSyntheticAnnotationClass() throws {
        let source = """
        annotation class ExperimentalApi
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("contracts"),
            ctx.interner.intern("ExperimentalContracts"),
        ]
        let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))

        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertEqual(symbol.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol.id)
        XCTAssertTrue(
            annotations.contains(
                where: {
                    $0.annotationFQName == "kotlin.annotation.Target"
                        && $0.arguments == [
                            "AnnotationTarget.CLASS",
                            "AnnotationTarget.FUNCTION",
                            "AnnotationTarget.PROPERTY",
                            "AnnotationTarget.TYPEALIAS",
                        ]
                }
            ),
            "Expected ExperimentalContracts to carry @Target for class/function/property/typealias, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains(
                where: {
                    $0.annotationFQName == "kotlin.annotation.Retention"
                        && $0.arguments == ["AnnotationRetention.BINARY"]
                }
            ),
            "Expected ExperimentalContracts to carry @Retention(AnnotationRetention.BINARY), got: \(annotations)"
        )
    }

    func testExperimentalExtendedContractsAnnotationIsSyntheticOptInMarker() throws {
        let source = """
        fun noop() {}
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("contracts"),
            ctx.interner.intern("ExperimentalExtendedContracts"),
        ]
        let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))

        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))
        XCTAssertEqual(symbol.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: symbol.id)
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.RequiresOptIn" },
            "Expected ExperimentalExtendedContracts to carry @RequiresOptIn, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains(
                where: {
                    $0.annotationFQName == "kotlin.annotation.Target"
                        && $0.arguments == [
                            "AnnotationTarget.CLASS",
                            "AnnotationTarget.FUNCTION",
                            "AnnotationTarget.PROPERTY",
                            "AnnotationTarget.TYPEALIAS",
                        ]
                }
            ),
            "Expected ExperimentalExtendedContracts to carry @Target for class/function/property/typealias, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains(
                where: {
                    $0.annotationFQName == "kotlin.annotation.Retention"
                        && $0.arguments == ["AnnotationRetention.BINARY"]
                }
            ),
            "Expected ExperimentalExtendedContracts to carry @Retention(AnnotationRetention.BINARY), got: \(annotations)"
        )
    }

    func testExperimentalExtendedContractsRequiresOptIn() {
        let source = """
        import kotlin.contracts.ExperimentalExtendedContracts

        @ExperimentalExtendedContracts
        fun extendedApi(): Int = 1

        fun caller(): Int = extendedApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one ExperimentalExtendedContracts opt-in diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "ExperimentalExtendedContracts opt-in diagnostics should be errors")
    }

    func testOverloadResolutionByLambdaReturnTypeRejectsClassTarget() {
        let source = """
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.OptIn
        import kotlin.experimental.ExperimentalTypeInference

        @Target(AnnotationTarget.CLASS)
        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 2, "Expected target diagnostics for both @Target and @OverloadResolutionByLambdaReturnType misuse, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testExperimentalTypeInferenceAcceptsFunctionTarget() {
        let source = """
        import kotlin.experimental.ExperimentalTypeInference

        @ExperimentalTypeInference
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "ExperimentalTypeInference should be accepted on functions, got: \(ctx.diagnostics.diagnostics)")
    }

    func testOverloadResolutionByLambdaReturnTypeRequiresOptIn() {
        let source = """
        import kotlin.OverloadResolutionByLambdaReturnType

        @OverloadResolutionByLambdaReturnType
        fun foo(block: () -> Int): Int = block()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPTIN", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one opt-in diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Opt-in diagnostics should be errors")
    }

    func testOverloadResolutionByLambdaReturnTypeAcceptsOptIn() {
        let source = """
        import kotlin.OptIn
        import kotlin.OverloadResolutionByLambdaReturnType
        import kotlin.experimental.ExperimentalTypeInference

        @OptIn(ExperimentalTypeInference::class)
        @OverloadResolutionByLambdaReturnType
        fun foo(block: () -> Int): Int = block()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPTIN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected opt-in diagnostic to be suppressed by @OptIn, got: \(ctx.diagnostics.diagnostics)")
    }

    func testFieldTargetAllowsBackedFieldAndRejectsMissingBackingField() {
        let source = """
        @Target(value = [AnnotationTarget.FIELD])
        annotation class FieldOnly

        class Storage {
            @field:FieldOnly val stored: String = ""
        }

        class Missing {
            @field:FieldOnly val missing: String
                get() = "x"
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected exactly one annotation-target diagnostic for the missing backing field, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testFieldTargetRejectsExtensionProperty() {
        let source = """
        @Target(value = [AnnotationTarget.FIELD])
        annotation class FieldOnly

        @field:FieldOnly
        val String.ext: Int
            get() = length
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one annotation-target diagnostic for the extension property, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testAnnotationTargetSuppressionAliasSuppressesDiagnostic() {
        let source = """
        @Suppress("ANNOTATION_TARGET")
        @Target(AnnotationTarget.CLASS)
        class BadTarget
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected ANNOTATION_TARGET suppression alias to suppress annotation-target diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }


    func testWasExperimentalAnnotationIsCollectedOnDeclaration() throws {
        let source = """
        annotation class ExperimentalApi

        @WasExperimental(markerClass = ExperimentalApi::class)
        fun stabilizedApi(): Int = 42
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let symbolID = try XCTUnwrap(sema.symbols.lookupAll(fqName: [ctx.interner.intern("stabilizedApi")]).first)
        let annotations = sema.symbols.annotations(for: symbolID)
        let annotation = try XCTUnwrap(annotations.first(where: {
            KnownCompilerAnnotation.wasExperimental.matches($0.annotationFQName)
        }))

        XCTAssertEqual(annotation.arguments, ["markerClass=ExperimentalApi::class"])
    }

    func testExtensionFunctionTypeResolvesInterfacePropertyAndTypeAlias() throws {
        let source = """
        interface Host {
            val receiverAction: @ExtensionFunctionType Function1<String, Unit>
        }

        typealias Action = @ExtensionFunctionType Function2<String, Int, Unit>
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected extension function type source to compile cleanly, got: \(ctx.diagnostics.diagnostics)")

        let ast = try XCTUnwrap(ctx.ast)
        let sema = try XCTUnwrap(ctx.sema)
        let file = try XCTUnwrap(ast.files.first)

        let interfaceDeclID = try XCTUnwrap(
            file.topLevelDecls.first(where: {
                if case .interfaceDecl = ast.arena.decl($0) {
                    return true
                }
                return false
            })
        )
        guard case let .interfaceDecl(interfaceDecl) = ast.arena.decl(interfaceDeclID) else {
            XCTFail("Expected interface declaration")
            return
        }
        let propertyDeclID = try XCTUnwrap(interfaceDecl.memberProperties.first)
        let propertySymbol = try XCTUnwrap(sema.bindings.declSymbol(for: propertyDeclID))
        let propertyType = try XCTUnwrap(sema.symbols.propertyType(for: propertySymbol))

        if case let .functionType(functionType) = sema.types.kind(of: propertyType) {
            XCTAssertEqual(functionType.receiver, sema.types.stringType)
            XCTAssertTrue(functionType.params.isEmpty)
            XCTAssertEqual(functionType.returnType, sema.types.unitType)
            XCTAssertFalse(functionType.isSuspend)
        } else {
            XCTFail("Expected interface property type to resolve as functionType")
        }

        let actionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [ctx.interner.intern("Action")]))
        let actionUnderlyingType = try XCTUnwrap(sema.symbols.typeAliasUnderlyingType(for: actionSymbol))

        if case let .functionType(functionType) = sema.types.kind(of: actionUnderlyingType) {
            XCTAssertEqual(functionType.receiver, sema.types.stringType)
            XCTAssertEqual(functionType.params, [sema.types.intType])
            XCTAssertEqual(functionType.returnType, sema.types.unitType)
            XCTAssertFalse(functionType.isSuspend)
        } else {
            XCTFail("Expected typealias underlying type to resolve as functionType")
        }
    }

    func testExtensionFunctionTypeRejectsFunction0() {
        let source = """
        interface Host {
            val invalid: @ExtensionFunctionType Function0<Unit>
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-EXTFN-TYPE", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one extension-function-type diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Extension-function-type diagnostics should be errors")
    }

    func testExtensionFunctionTypeRejectsNonFunctionNominalType() {
        let source = """
        interface Host {
            val invalid: @ExtensionFunctionType List<String>
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-EXTFN-TYPE", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one extension-function-type diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Extension-function-type diagnostics should be errors")
    }

    func testTypeAnnotationTargetValidationRejectsClassOnlyAnnotationOnTypeUsage() {
        let source = """
        @Target(AnnotationTarget.CLASS)
        annotation class ClassOnly

        interface Host {
            val invalid: @ClassOnly String
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one annotation-target diagnostic for type usage, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testTypeAnnotationRejectsUseSiteTarget() {
        let source = """
        interface Host {
            val invalid: @field:ExtensionFunctionType Function1<String, Unit>
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-PARSE-TYPE-ANNOTATION", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one parse diagnostic for type annotation use-site target, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Type-annotation parse diagnostics should be errors")
    }

    func testCompilerMetadataAutoAttachedToNominalDeclarations() throws {
        let source = """
        class Plain
        interface Face
        object Singleton
        enum class Color { RED }
        annotation class Marker
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected metadata attachment smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        XCTAssertNotNil(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Metadata")]))

        for name in ["Plain", "Face", "Singleton", "Color", "Marker"] {
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern(name)]))
            let annotations = sema.symbols.annotations(for: symbol)
            XCTAssertTrue(
                annotations.contains(where: { $0.annotationFQName == KnownCompilerAnnotation.metadata.qualifiedName }),
                "Expected \(name) to receive compiler metadata annotation, got: \(annotations)"
            )
        }
    }

    func testOptInAllowsExperimentalStdlibApiUsage() {
        let source = """
        @OptIn(ExperimentalStdlibApi::class)
        fun hex(): String = 255.toHexString()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected opt-in annotated function to use HexFormat API without diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    func testExperimentalStdlibApiWithoutOptInEmitsDiagnostic() {
        let source = """
        fun hex(): String = 255.toHexString()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one opt-in diagnostic for toHexString(), got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Opt-in diagnostics should be errors")
    }

    func testExperimentalStdlibApiDefaultPropertyWithoutOptInEmitsDiagnostic() {
        let source = """
        fun hex(): String = 42.toHexString(HexFormat.Default)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertEqual(diagnostics.count, 2, "Expected opt-in diagnostics for HexFormat.Default and toHexString(), got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Opt-in diagnostics should be errors")
    }

    func testCompilerOptInFlagAllowsExperimentalStdlibApiUsage() {
        let source = """
        fun hex(): String = 255.toHexString()
        """

        let ctx = runSemaCollectingDiagnostics(
            source,
            frontendFlags: ["opt-in=kotlin.ExperimentalStdlibApi"]
        )
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected compiler -opt-in flag to suppress stdlib opt-in diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    func testExperimentalVersionOverloadingAnnotationRequiresOptIn() {
        let source = """
        import kotlin.ExperimentalVersionOverloading

        @ExperimentalVersionOverloading
        annotation class Versioned

        @Versioned
        fun api() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one ExperimentalVersionOverloading opt-in diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "ExperimentalVersionOverloading opt-in diagnostics should be errors")
    }

    func testExperimentalVersionOverloadingAnnotationAcceptsOptIn() {
        let source = """
        import kotlin.ExperimentalVersionOverloading

        @ExperimentalVersionOverloading
        annotation class Versioned

        @OptIn(ExperimentalVersionOverloading::class)
        @Versioned
        fun api() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected @OptIn to suppress ExperimentalVersionOverloading diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    func testExperimentalVersionOverloadingAnnotationAcceptsCompilerOptInFlag() {
        let source = """
        import kotlin.ExperimentalVersionOverloading

        @ExperimentalVersionOverloading
        annotation class Versioned

        @Versioned
        fun api() {}
        """

        let ctx = runSemaCollectingDiagnostics(
            source,
            frontendFlags: ["opt-in=kotlin.ExperimentalVersionOverloading"]
        )
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected compiler -opt-in flag to suppress ExperimentalVersionOverloading diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    func testExperimentalContextParametersMarkerRequiresOptIn() {
        let source = """
        import kotlin.ExperimentalContextParameters

        @ExperimentalContextParameters
        fun contextApi(): Int = 1

        fun caller(): Int = contextApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one ExperimentalContextParameters opt-in diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "ExperimentalContextParameters opt-in diagnostics should be errors")
        XCTAssertTrue(
            diagnostics.first?.message.contains("context parameters") == true,
            "Expected diagnostic to include the ExperimentalContextParameters message, got: \(diagnostics)"
        )
    }

    func testExperimentalContextParametersMarkerAcceptsOptIn() {
        let source = """
        import kotlin.ExperimentalContextParameters

        @ExperimentalContextParameters
        fun contextApi(): Int = 1

        @OptIn(ExperimentalContextParameters::class)
        fun caller(): Int = contextApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected @OptIn to suppress ExperimentalContextParameters diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    func testExperimentalContextParametersMarkerAcceptsCompilerOptInFlag() {
        let source = """
        import kotlin.ExperimentalContextParameters

        @ExperimentalContextParameters
        fun contextApi(): Int = 1

        fun caller(): Int = contextApi()
        """

        let ctx = runSemaCollectingDiagnostics(
            source,
            frontendFlags: ["opt-in=kotlin.ExperimentalContextParameters"]
        )
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected compiler -opt-in flag to suppress ExperimentalContextParameters diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    func testSubclassOptInRequiredRejectsSubclassWithoutOptIn() {
        let source = """
        @RequiresOptIn
        annotation class ExperimentalBase

        @SubclassOptInRequired(ExperimentalBase::class)
        open class Base

        class Child : Base()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one subclass opt-in diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.contains(where: isError), "Subclass opt-in diagnostic should follow ERROR marker severity")
    }

    func testSubclassOptInRequiredAllowsSubclassWithOptIn() {
        let source = """
        @RequiresOptIn
        annotation class ExperimentalBase

        @SubclassOptInRequired(ExperimentalBase::class)
        open class Base

        @OptIn(ExperimentalBase::class)
        class Child : Base()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected @OptIn to satisfy subclass opt-in requirement, got: \(ctx.diagnostics.diagnostics)")
    }

    func testSubclassOptInRequiredPropagatesThroughSupertypeChain() {
        let source = """
        @RequiresOptIn
        annotation class ExperimentalBase

        @SubclassOptInRequired(ExperimentalBase::class)
        open class Base

        @OptIn(ExperimentalBase::class)
        open class Middle : Base()

        class Child : Middle()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected inherited subclass opt-in requirement to reach Child, got: \(ctx.diagnostics.diagnostics)")
    }

    func testSubclassOptInRequiredRejectsNonOptInMarkerClass() {
        let source = """
        annotation class PlainMarker

        @SubclassOptInRequired(PlainMarker::class)
        open class Base

        class Child : Base()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-SUBCLASS-OPT-IN", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected misuse diagnostic for non opt-in marker, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.first?.message.contains("markerClass") == true)
    }

    func testFileLevelOptInAllowsExperimentalStdlibApiUsage() {
        let source = """
        @file:OptIn(ExperimentalStdlibApi::class)

        fun hex(): Int = "ff".hexToInt()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected file-level opt-in to suppress HexFormat diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    func testExperimentalAssociatedObjectsMarkerRequiresOptIn() {
        let source = """
        import kotlin.reflect.ExperimentalAssociatedObjects

        @ExperimentalAssociatedObjects
        fun associatedObjectsApi(): Int = 1

        fun caller(): Int = associatedObjectsApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.contains(where: isError), "Expected ExperimentalAssociatedObjects opt-in error, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(
            diagnostics.first?.message.contains("ExperimentalAssociatedObjects") == true,
            "Expected diagnostic to mention ExperimentalAssociatedObjects, got: \(diagnostics)"
        )
    }

    func testExperimentalAssociatedObjectsMarkerAllowsExplicitOptIn() {
        let source = """
        import kotlin.reflect.ExperimentalAssociatedObjects

        @ExperimentalAssociatedObjects
        fun associatedObjectsApi(): Int = 1

        @OptIn(ExperimentalAssociatedObjects::class)
        fun caller(): Int = associatedObjectsApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected @OptIn to suppress ExperimentalAssociatedObjects diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    func testOptInSuppressionAliasSuppressesDiagnostic() {
        let source = """
        @Suppress("OPT_IN_USAGE")
        fun hex(): String = 255.toHexString()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected OPT_IN_USAGE suppression alias to suppress opt-in diagnostics, got: \(ctx.diagnostics.diagnostics)")
    }

    func propertyType(
        named name: String,
        in interfaceDecl: InterfaceDecl,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> TypeID {
        let expectedName = interner.intern(name)
        let propertyDeclID = try XCTUnwrap(interfaceDecl.memberProperties.first(where: { declID in
            guard case let .propertyDecl(propertyDecl) = ast.arena.decl(declID) else {
                return false
            }
            return propertyDecl.name == expectedName
        }))
        let propertySymbol = try XCTUnwrap(sema.bindings.declSymbol(for: propertyDeclID))
        return try XCTUnwrap(sema.symbols.propertyType(for: propertySymbol))
    }

    func runSemaCollectingDiagnostics(
        _ source: String,
        frontendFlags: [String] = []
    ) -> CompilationContext {
        let ctx = makeAnnotationSemanticContext(source, frontendFlags: frontendFlags)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }

    private func makeAnnotationSemanticContext(
        _ source: String,
        frontendFlags: [String]
    ) -> CompilationContext {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath], frontendFlags: frontendFlags)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        return ctx
    }

    func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    func isError(_ diagnostic: Diagnostic) -> Bool {
        if case .error = diagnostic.severity {
            return true
        }
        return false
    }

    func isWarning(_ diagnostic: Diagnostic) -> Bool {
        if case .warning = diagnostic.severity {
            return true
        }
        return false
    }

    func symbolVisibility(_ path: [String], in ctx: CompilationContext) throws -> Visibility {
        let sema = try XCTUnwrap(ctx.sema)
        let fqName = path.map(ctx.interner.intern)
        let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))
        return symbol.visibility
    }

    private func assertArrayOfOutThrowableKClass(
        _ type: TypeID,
        in sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard case let .classType(arrayType) = sema.types.kind(of: type) else {
            return XCTFail("Expected Array<out KClass<Throwable>>, got \(sema.types.renderType(type))", file: file, line: line)
        }
        let arraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Array")]),
            file: file,
            line: line
        )
        XCTAssertEqual(arrayType.classSymbol, arraySymbol, file: file, line: line)
        XCTAssertEqual(arrayType.args.count, 1, file: file, line: line)
        guard case let .out(elementType) = arrayType.args[0] else {
            return XCTFail("Expected covariant Array element, got \(arrayType.args[0])", file: file, line: line)
        }
        try assertThrowableKClass(elementType, in: sema, interner: interner, file: file, line: line)
    }

    private func assertThrowableKClass(
        _ type: TypeID,
        in sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard case let .kClassType(kClassType) = sema.types.kind(of: type) else {
            return XCTFail("Expected KClass<Throwable>, got \(sema.types.renderType(type))", file: file, line: line)
        }
        guard case let .classType(argumentType) = sema.types.kind(of: kClassType.argument) else {
            return XCTFail("Expected KClass argument to be Throwable, got \(sema.types.renderType(kClassType.argument))", file: file, line: line)
        }
        let throwableSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Throwable")]),
            file: file,
            line: line
        )
        XCTAssertEqual(argumentType.classSymbol, throwableSymbol, file: file, line: line)
    }
}
