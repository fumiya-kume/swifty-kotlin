@testable import CompilerCore
import Foundation
import XCTest

final class AnnotationSemanticTests: XCTestCase {
    func testDeprecatedLevelErrorEmitsErrorAtCallSite() {
        let source = """
        @Deprecated("Use replacement", level = DeprecationLevel.ERROR)
        fun oldApi(): Int = 1

        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertTrue(diagnostics.contains(where: isError), "Expected deprecated(error) diagnostic, got: \(ctx.diagnostics.diagnostics)")
    }

    func testDeprecatedLevelErrorCanBeSuppressedWithDeprecationError() {
        let source = """
        @Deprecated("Use replacement", level = DeprecationLevel.ERROR)
        fun oldApi(): Int = 1

        @Suppress("DEPRECATION_ERROR")
        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected deprecated(error) diagnostic to be suppressed, got: \(ctx.diagnostics.diagnostics)")
    }

    func testDeprecatedStdlibApisCanBeSuppressedWithDeprecationError() {
        let source = """
        import kotlin.io.createTempDir
        import kotlin.io.createTempFile

        @Suppress("DEPRECATION_ERROR", "KSWIFTK-SEMA-DEPRECATED")
        fun caller() {
            val legacyChar = 65.toChar()
            println(legacyChar)
            val legacySlice = "kotlin".subSequence(1, 4)
            println(legacySlice)
            val tempDir = createTempDir(prefix = "kswiftk-", suffix = "-dir")
            val tempFile = createTempFile(prefix = "kswiftk-", suffix = ".tmp", directory = tempDir)
            println(tempFile)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected stdlib deprecation diagnostics to be suppressed, got: \(ctx.diagnostics.diagnostics)")
    }

    func testDeprecatedDefaultEmitsWarningAtCallSite() {
        let source = """
        @Deprecated("Use replacement")
        fun oldApi(): Int = 1

        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertTrue(diagnostics.contains(where: isWarning), "Expected deprecated(warning) diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertFalse(diagnostics.contains(where: isError), "Did not expect deprecated(error) diagnostic for default level")
    }

    func testDeprecatedOnCompanionMemberEmitsWarning() {
        let source = """
        class Host {
            companion object {
                @Deprecated("Use create2")
                fun create(): Int = 1
            }
        }

        fun caller(): Int = Host.create()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertTrue(diagnostics.contains(where: isWarning), "Expected deprecated warning on companion call, got: \(ctx.diagnostics.diagnostics)")
    }

    func testDeprecatedReplaceWithAddsMessageAndCodeAction() {
        let source = """
        @Deprecated("Use replacement", replaceWith = ReplaceWith("newApi()"))
        fun oldApi(): Int = 1

        fun newApi(): Int = 2
        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one deprecated diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.contains(where: isWarning), "Expected deprecated warning, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics[0].message.contains("Replace with: newApi()"), "Expected replaceWith message, got: \(diagnostics[0].message)")
        XCTAssertEqual(diagnostics[0].codeActions.map(\.title), ["Replace with 'newApi()'"])
    }

    func testDeprecatedReplaceWithNamedExpressionParses() {
        let source = """
        @Deprecated(
            message = "Use replacement",
            replaceWith = ReplaceWith(expression = "newApi()")
        )
        fun oldApi(): Int = 1

        fun newApi(): Int = 2
        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one deprecated diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics[0].message.contains("Replace with: newApi()"), "Expected replaceWith message, got: \(diagnostics[0].message)")
        XCTAssertEqual(diagnostics[0].codeActions.map(\.title), ["Replace with 'newApi()'"])
    }

    func testDeprecatedErrorLevelWithReplaceWithStillEmitsError() {
        let source = """
        @Deprecated("Use replacement", replaceWith = ReplaceWith("newApi()"), level = DeprecationLevel.ERROR)
        fun oldApi(): Int = 1

        fun newApi(): Int = 2
        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one deprecated diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.contains(where: isError), "Expected deprecated error, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics[0].message.contains("Replace with: newApi()"), "Expected replaceWith message, got: \(diagnostics[0].message)")
    }

    func testDeprecatedEmptyReplaceWithDoesNotAddSuggestion() {
        let source = """
        @Deprecated("Use replacement", replaceWith = ReplaceWith())
        fun oldApi(): Int = 1

        fun caller(): Int = oldApi()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one deprecated diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertFalse(diagnostics[0].message.contains("Replace with:"), "Did not expect replaceWith message, got: \(diagnostics[0].message)")
        XCTAssertTrue(diagnostics[0].codeActions.isEmpty, "Did not expect code actions for empty replaceWith")
    }

    func testDeprecatedSinceKotlinSurfaceHasVersionPropertiesAndDefaults() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("DeprecatedSinceKotlin"),
        ]
        let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))

        XCTAssertEqual(symbol.kind, .annotationClass)
        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbolID)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.ANNOTATION_CLASS",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.PROPERTY_SETTER",
                        "AnnotationTarget.PROPERTY_GETTER",
                        "AnnotationTarget.TYPEALIAS",
                    ]
            },
            "DeprecatedSinceKotlin should carry its declaration target list, got: \(annotations)"
        )

        let propertyNames = ["warningSince", "errorSince", "hiddenSince"]
        for propertyName in propertyNames {
            let propertySymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: fqName + [ctx.interner.intern(propertyName)])
            )
            XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), sema.types.stringType)
        }

        let initName = ctx.interner.intern("<init>")
        let ctorSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fqName + [initName]).first {
                sema.symbols.symbol($0)?.kind == .constructor
            }
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: ctorSymbol))
        XCTAssertEqual(signature.parameterTypes, Array(repeating: sema.types.stringType, count: 3))
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [true, true, true])
        XCTAssertEqual(signature.valueParameterIsVararg, [false, false, false])
    }

    func testDeprecatedSinceKotlinAcceptsDocumentedTargets() {
        let source = """
        @DeprecatedSinceKotlin(warningSince = "1.0", errorSince = "1.1", hiddenSince = "1.2")
        class OldClass {
            @DeprecatedSinceKotlin
            constructor()
        }

        @DeprecatedSinceKotlin
        fun oldFun() {}

        @DeprecatedSinceKotlin
        val oldProperty: Int = 1

        @DeprecatedSinceKotlin
        annotation class OldAnnotation
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected DeprecatedSinceKotlin target uses to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    func testDeprecatedSinceKotlinRejectsFileTarget() {
        let source = """
        @file:DeprecatedSinceKotlin

        package sample
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected file-target diagnostic for DeprecatedSinceKotlin, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testSyntheticDeprecatedToCharEmitsWarning() {
        let source = """
        fun caller(): Char = 65.toChar()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one deprecated diagnostic for toChar(), got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.contains(where: isWarning), "Expected deprecated warning for toChar(), got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics[0].message.contains("toChar"), "Expected toChar() in message, got: \(diagnostics[0].message)")
    }

    func testSyntheticDeprecatedStringSubSequenceEmitsWarning() {
        let source = """
        fun caller(): String = "kotlin".subSequence(1, 4).toString()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one deprecated diagnostic for subSequence(), got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.contains(where: isWarning), "Expected deprecated warning for subSequence(), got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics[0].message.contains("subSequence"), "Expected subSequence() in message, got: \(diagnostics[0].message)")
    }

    func testSyntheticDeprecatedCreateTempDirEmitsError() {
        let source = """
        import kotlin.io.createTempDir

        fun caller() = createTempDir(prefix = "demo")
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one deprecated diagnostic for createTempDir(), got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.contains(where: isError), "Expected deprecated error for createTempDir(), got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics[0].message.contains("createTempDir"), "Expected createTempDir() in message, got: \(diagnostics[0].message)")
    }

    func testSuppressUncheckedCastByKotlinNameSuppressesDiagnostic() {
        let source = """
        @Suppress("UNCHECKED_CAST")
        fun suppressed(v: Any): List<String> = v as List<String>

        fun unsuppressed(v: Any): List<String> = v as List<String>
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-UNCHECKED-CAST", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected exactly one unchecked-cast warning from unsuppressed function, got: \(diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isWarning), "Unchecked-cast diagnostics should be warnings")
    }

    func testSuppressUncheckedCastByInternalCodeSuppressesDiagnostic() {
        let source = """
        @Suppress("KSWIFTK-SEMA-UNCHECKED-CAST")
        fun suppressed(v: Any): List<String> = v as List<String>

        fun unsuppressed(v: Any): List<String> = v as List<String>
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-UNCHECKED-CAST", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected exactly one unchecked-cast warning from unsuppressed function, got: \(diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isWarning), "Unchecked-cast diagnostics should be warnings")
    }

    func testAnnotationTargetEnumConstantResolves() {
        let source = """
        fun targetSmoke(): AnnotationTarget = AnnotationTarget.CLASS
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected AnnotationTarget smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    func testOverloadResolutionByLambdaReturnTypeResolves() {
        let source = """
        import kotlin.OverloadResolutionByLambdaReturnType

        fun marker(x: OverloadResolutionByLambdaReturnType?): Int = 0
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected OverloadResolutionByLambdaReturnType smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    func testExperimentalTypeInferenceResolves() {
        let source = """
        import kotlin.experimental.ExperimentalTypeInference

        fun marker(x: ExperimentalTypeInference?): Int = 0
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected ExperimentalTypeInference smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    func testOptInResolves() {
        let source = """
        fun marker(x: OptIn?): Int = 0
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected OptIn smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    func testSubclassOptInRequiredResolves() {
        let source = """
        fun marker(x: SubclassOptInRequired?): Int = 0
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected SubclassOptInRequired smoke test to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    func testSubclassOptInRequiredMarkerClassPropertyIsRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let valueSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("SubclassOptInRequired"),
                ctx.interner.intern("markerClass"),
            ]),
            "kotlin.SubclassOptInRequired.markerClass must be registered"
        )
        XCTAssertNotNil(sema.symbols.propertyType(for: valueSymbol), "markerClass must have a property type")
    }

    func testConsistentCopyVisibilityResolvesAndTargetsClasses() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("ConsistentCopyVisibility"),
            ]),
            "kotlin.ConsistentCopyVisibility must be registered"
        )
        let annotations = sema.symbols.annotations(for: symbol)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.CLASS"]
            },
            "ConsistentCopyVisibility should target classes, got: \(annotations)"
        )
    }

    func testConsistentCopyVisibilityRejectsFunctionUse() {
        let source = """
        @ConsistentCopyVisibility
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected class-only annotation target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testMustUseReturnValuesResolvesAndTargetsFileAndClass() throws {
        let source = """
        fun marker(x: MustUseReturnValues?): Int = 0
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("MustUseReturnValues"),
            ]),
            "kotlin.MustUseReturnValues must be registered"
        )
        let symbolInfo = try XCTUnwrap(sema.symbols.symbol(symbol))
        XCTAssertEqual(symbolInfo.kind, .annotationClass, "MustUseReturnValues must be an annotation class")

        let annotations = sema.symbols.annotations(for: symbol)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && Set($0.arguments) == Set(["AnnotationTarget.FILE", "AnnotationTarget.CLASS"])
            },
            "MustUseReturnValues should target files and classes, got: \(annotations)"
        )
    }

    func testMustUseReturnValuesAllowsClassUse() {
        let source = """
        @MustUseReturnValues
        class ApiScope
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected @MustUseReturnValues to be accepted on classes, got: \(ctx.diagnostics.diagnostics)")
    }

    func testMustUseReturnValuesAllowsFileUse() {
        let source = """
        @file:MustUseReturnValues

        fun api(): Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected @file:MustUseReturnValues to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    func testMustUseReturnValuesRejectsFunctionUse() {
        let source = """
        @MustUseReturnValues
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected file-or-class annotation target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testBuilderInferenceAnnotationSurfaceIsSyntheticAndTargeted() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let symbolID = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("BuilderInference"),
            ]),
            "kotlin.BuilderInference must be registered"
        )
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))

        XCTAssertEqual(symbol.kind, .annotationClass)
        XCTAssertEqual(symbol.visibility, .public)
        XCTAssertTrue(symbol.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbolID)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == [
                        "AnnotationTarget.VALUE_PARAMETER",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                    ]
            },
            "BuilderInference should target value parameters, functions, and properties, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.BINARY"]
            },
            "BuilderInference should carry binary retention, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                KnownCompilerAnnotation.experimentalTypeInference.matches($0.annotationFQName)
            },
            "BuilderInference should be annotated with ExperimentalTypeInference, got: \(annotations)"
        )
    }

    func testBuilderInferenceAcceptsDocumentedTargets() {
        let source = """
        @BuilderInference
        fun builderFunction(block: () -> Unit) {}

        fun acceptsValueParameter(@BuilderInference block: () -> Unit) {}

        @BuilderInference
        val builderProperty: Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected BuilderInference target uses to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    func testBuilderInferenceRejectsClassTarget() {
        let source = """
        @BuilderInference
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected class-target diagnostic for BuilderInference, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testIgnorableReturnValueResolvesAndTargetsFunctions() throws {
        let source = """
        fun marker(x: IgnorableReturnValue?): Int = 0
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("IgnorableReturnValue"),
            ]),
            "kotlin.IgnorableReturnValue must be registered"
        )
        let symbolInfo = try XCTUnwrap(sema.symbols.symbol(symbol))
        XCTAssertEqual(symbolInfo.kind, .annotationClass, "IgnorableReturnValue must be an annotation class")

        let annotations = sema.symbols.annotations(for: symbol)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.FUNCTION"]
            },
            "IgnorableReturnValue should target functions, got: \(annotations)"
        )
    }

    func testIgnorableReturnValueAllowsFunctionUse() {
        let source = """
        @IgnorableReturnValue
        fun ignored(): Int = 1
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected @IgnorableReturnValue to be accepted on functions, got: \(ctx.diagnostics.diagnostics)")
    }

    func testIgnorableReturnValueRejectsClassUse() {
        let source = """
        @IgnorableReturnValue
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected function-only annotation target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testPrivateDataClassCopyVisibilityMigrationWarnsAndKeepsPublicCopy() throws {
        let source = """
        package test

        data class Secret private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one data class copy visibility warning, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isWarning), "Data class copy visibility diagnostic should be a warning")
        XCTAssertTrue(diagnostics[0].message.contains("private"), "Expected primary constructor visibility in message, got: \(diagnostics[0].message)")
        XCTAssertEqual(
            try symbolVisibility(["test", "Secret", "copy"], in: ctx),
            .public,
            "Unannotated migration mode should keep copy() public"
        )
    }

    func testConsistentCopyVisibilityMakesCopyUseConstructorVisibility() throws {
        let source = """
        package test

        @ConsistentCopyVisibility
        data class Secret private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected ConsistentCopyVisibility to opt in to constructor visibility, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertEqual(
            try symbolVisibility(["test", "Secret", "copy"], in: ctx),
            .private,
            "Annotated data class copy() should use the private primary constructor visibility"
        )
    }

    func testDataClassCopyVisibilityWarningCanBeSuppressedByAlias() {
        let source = """
        @Suppress("DATA_CLASS_COPY_VISIBILITY")
        data class Secret private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected DATA_CLASS_COPY_VISIBILITY suppression alias to suppress diagnostic, got: \(ctx.diagnostics.diagnostics)")
    }

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

    private func symbolVisibility(_ path: [String], in ctx: CompilationContext) throws -> Visibility {
        let sema = try XCTUnwrap(ctx.sema)
        let fqName = path.map(ctx.interner.intern)
        let symbolID = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let symbol = try XCTUnwrap(sema.symbols.symbol(symbolID))
        return symbol.visibility
    }
}
