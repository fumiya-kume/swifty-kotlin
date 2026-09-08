#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct AnnotationSemanticTests {

    @Test func testAnnotationSemanticSema() throws {
        let sources: [String] = [
            // testDeprecatedLevelErrorEmitsErrorAtCallSite
            """
            package sample0
                    @Deprecated("Use replacement", level = DeprecationLevel.ERROR)
                    fun oldApi(): Int = 1

                    fun caller(): Int = oldApi()

            """,

            // testDeprecatedLevelErrorCanBeSuppressedWithDeprecationError
            """
            package sample1
                    @Deprecated("Use replacement", level = DeprecationLevel.ERROR)
                    fun oldApi(): Int = 1

                    @Suppress("DEPRECATION_ERROR")
                    fun caller(): Int = oldApi()

            """,

            // testDeprecatedStdlibApisCanBeSuppressedWithDeprecationError
            """
            package sample2
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

            """,

            // testDeprecatedDefaultEmitsWarningAtCallSite
            """
            package sample3
                    @Deprecated("Use replacement")
                    fun oldApi(): Int = 1

                    fun caller(): Int = oldApi()

            """,

            // testDeprecatedOnCompanionMemberEmitsWarning
            """
            package sample4
                    class Host {
                        companion object {
                            @Deprecated("Use create2")
                            fun create(): Int = 1
                        }
                    }

                    fun caller(): Int = Host.create()

            """,

            // testDeprecatedReplaceWithAddsMessageAndCodeAction
            """
            package sample5
                    @Deprecated("Use replacement", replaceWith = ReplaceWith("newApi()"))
                    fun oldApi(): Int = 1

                    fun newApi(): Int = 2
                    fun caller(): Int = oldApi()

            """,

            // testDeprecatedReplaceWithNamedExpressionParses
            """
            package sample6
                    @Deprecated(
                        message = "Use replacement",
                        replaceWith = ReplaceWith(expression = "newApi()")
                    )
                    fun oldApi(): Int = 1

                    fun newApi(): Int = 2
                    fun caller(): Int = oldApi()

            """,

            // testDeprecatedErrorLevelWithReplaceWithStillEmitsError
            """
            package sample7
                    @Deprecated("Use replacement", replaceWith = ReplaceWith("newApi()"), level = DeprecationLevel.ERROR)
                    fun oldApi(): Int = 1

                    fun newApi(): Int = 2
                    fun caller(): Int = oldApi()

            """,

            // testDeprecatedEmptyReplaceWithDoesNotAddSuggestion
            """
            package sample8
                    @Deprecated("Use replacement", replaceWith = ReplaceWith())
                    fun oldApi(): Int = 1

                    fun caller(): Int = oldApi()

            """,

            // testDeprecatedSinceKotlinAcceptsDocumentedTargets
            """
            package sample9
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

            """,

            // testDeprecatedSinceKotlinRejectsFileTarget
            """
            package sample10
                    @file:DeprecatedSinceKotlin


            """,

            // testSyntheticDeprecatedToCharEmitsError
            """
            package sample11
                    fun caller(): Char = 65L.toChar()

            """,

            // testSyntheticDeprecatedStringSubSequenceEmitsWarning
            """
            package sample12
                    fun caller(): String = "kotlin".subSequence(1, 4).toString()

            """,

            // testSyntheticDeprecatedCreateTempDirEmitsError
            """
            package sample13
                    import kotlin.io.createTempDir

                    fun caller() = createTempDir(prefix = "demo")

            """,

            // testSuppressUncheckedCastByKotlinNameSuppressesDiagnostic
            """
            package sample14
                    @Suppress("UNCHECKED_CAST")
                    fun suppressed(v: Any): List<String> = v as List<String>

                    fun unsuppressed(v: Any): List<String> = v as List<String>

            """,

            // testSuppressUncheckedCastByInternalCodeSuppressesDiagnostic
            """
            package sample15
                    @Suppress("KSWIFTK-SEMA-UNCHECKED-CAST")
                    fun suppressed(v: Any): List<String> = v as List<String>

                    fun unsuppressed(v: Any): List<String> = v as List<String>

            """,

            // testAnnotationTargetEnumConstantResolves
            """
            package sample16
                    fun targetSmoke(): AnnotationTarget = AnnotationTarget.CLASS

            """,

            // testOverloadResolutionByLambdaReturnTypeResolves
            """
            package sample17
                    import kotlin.OverloadResolutionByLambdaReturnType

                    fun marker(x: OverloadResolutionByLambdaReturnType?): Int = 0

            """,

            // testExperimentalTypeInferenceResolves
            """
            package sample18
                    import kotlin.experimental.ExperimentalTypeInference

                    fun marker(x: ExperimentalTypeInference?): Int = 0

            """,

            // testOptInResolves
            """
            package sample19
                    fun marker(x: OptIn?): Int = 0

            """,

            // testSubclassOptInRequiredResolves
            """
            package sample20
                    fun marker(x: SubclassOptInRequired?): Int = 0

            """,

            // testContextFunctionTypeParamsRejectsDeclarationUsage
            """
            package sample21
                    @ContextFunctionTypeParams(1)
                    class Bad

            """,

            // testContextFunctionTypeParamsRejectsTooLargeCount
            """
            package sample22
                    interface Host {
                        val invalid: @ContextFunctionTypeParams(3) Function2<String, Int, Unit>
                    }

            """,

            // testConsistentCopyVisibilityRejectsFunctionUse
            """
            package sample23
                    @ConsistentCopyVisibility
                    fun bad() {}

            """,

            // testMustUseReturnValuesAllowsClassUse
            """
            package sample24
                    @MustUseReturnValues
                    class ApiScope

            """,

            // testMustUseReturnValuesAllowsFileUse
            """
            package sample25
                    @file:MustUseReturnValues

                    fun api(): Int = 1

            """,

            // testMustUseReturnValuesRejectsFunctionUse
            """
            package sample26
                    @MustUseReturnValues
                    fun bad() {}

            """,

            // testBuilderInferenceAcceptsDocumentedTargets
            """
            package sample27
                    @BuilderInference
                    fun builderFunction(block: () -> Unit) {}

                    fun acceptsValueParameter(@BuilderInference block: () -> Unit) {}

                    @BuilderInference
                    val builderProperty: Int = 1

            """,

            // testBuilderInferenceRejectsClassTarget
            """
            package sample28
                    @BuilderInference
                    class Bad

            """,

            // testIgnorableReturnValueAllowsFunctionUse
            """
            package sample29
                    @IgnorableReturnValue
                    fun ignored(): Int = 1

            """,

            // testIgnorableReturnValueRejectsClassUse
            """
            package sample30
                    @IgnorableReturnValue
                    class Bad

            """,

            // testExposedCopyVisibilityRejectsFunctionUse
            """
            package sample31
                    @ExposedCopyVisibility
                    fun bad() {}

            """,

            // testParameterNameAcceptsTypeUse
            """
            package sample32
                    interface Host {
                        val value: @ParameterName(name = "value") String
                    }

            """,

            // testParameterNameRejectsClassUse
            """
            package sample33
                    @ParameterName("Bad")
                    class Bad

            """,

            // testPublishedApiAcceptsDocumentedDeclarationTargets
            """
            package sample34
                    @PublishedApi
                    internal class InternalHost {
                        @PublishedApi
                        internal val value: Int = 1

                        @PublishedApi
                        internal fun expose(): Int = value
                    }

            """,

            // testPublishedApiRejectsFileTarget
            """
            package sample35
                    @file:PublishedApi


            """,

            // testDslMarkerAcceptsAnnotationClassAndRejectsRegularClassUse
            """
            package sample36
                    @DslMarker
                    annotation class HtmlDsl

                    @DslMarker
                    class Bad

            """,

            // testDslMarkerCanMarkCustomDslAnnotation
            """
            package sample37
                    @DslMarker
                    annotation class HtmlDsl

                    @HtmlDsl
                    class Tag

            """,

            // testDataClassCopyVisibilityWarningCanBeSuppressedByAlias
            """
            package sample38
                    @Suppress("DATA_CLASS_COPY_VISIBILITY")
                    data class Secret private constructor(val value: Int)

            """,

            // testDeprecatedSinceKotlinRefinesSeverityAndHonorsSuppression
            """
            package sample39
                    @Deprecated("Use replacement")
                    @DeprecatedSinceKotlin(warningSince = "1.0", errorSince = "2.1")
                    fun sinceError(): Int = 1

                    @Deprecated("Use replacement")
                    @DeprecatedSinceKotlin(warningSince = "1.0", errorSince = "3.1")
                    fun sinceWarning(): Int = 2

                    @Deprecated("Use replacement")
                    @DeprecatedSinceKotlin(hiddenSince = "1.0")
                    fun sinceHidden(): Int = 3

                    @Deprecated("Use replacement", level = DeprecationLevel.HIDDEN)
                    fun hiddenByLevel(): Int = 4

                    @Suppress("DEPRECATION_ERROR")
                    fun suppressed(): Int = sinceError()

                    fun caller(): Int = sinceError() + sinceWarning() + sinceHidden() + hiddenByLevel()

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testDeprecatedLevelErrorEmitsErrorAtCallSite
            do {
                let samplePath = paths[0]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                let v0 = diagnostics.contains(where: isError)
                #expect(v0, "Expected deprecated(error) diagnostic, got: \(sampleDiags)")
            }
            // testDeprecatedLevelErrorCanBeSuppressedWithDeprecationError
            do {
                let samplePath = paths[1]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                #expect(diagnostics.isEmpty, "Expected deprecated(error) diagnostic to be suppressed, got: \(sampleDiags)")
            }
            // testDeprecatedStdlibApisCanBeSuppressedWithDeprecationError
            do {
                let samplePath = paths[2]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                #expect(diagnostics.isEmpty, "Expected stdlib deprecation diagnostics to be suppressed, got: \(sampleDiags)")
            }
            // testDeprecatedDefaultEmitsWarningAtCallSite
            do {
                let samplePath = paths[3]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                let v1 = diagnostics.contains(where: isWarning)
                #expect(v1, "Expected deprecated(warning) diagnostic, got: \(sampleDiags)")
                let v2 = diagnostics.contains(where: isError)
                #expect(!v2, "Did not expect deprecated(error) diagnostic for default level")
            }
            // testDeprecatedOnCompanionMemberEmitsWarning
            do {
                let samplePath = paths[4]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                let v3 = diagnostics.contains(where: isWarning)
                #expect(v3, "Expected deprecated warning on companion call, got: \(sampleDiags)")
            }
            // testDeprecatedReplaceWithAddsMessageAndCodeAction
            do {
                let samplePath = paths[5]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                #expect(diagnostics.count == 1, "Expected one deprecated diagnostic, got: \(sampleDiags)")
                let v4 = diagnostics.contains(where: isWarning)
                #expect(v4, "Expected deprecated warning, got: \(sampleDiags)")
                #expect(diagnostics[0].message.contains("Replace with: newApi()"), "Expected replaceWith message, got: \(diagnostics[0].message)")
                #expect(diagnostics[0].codeActions.map(\.title) == ["Replace with 'newApi()'"])
            }
            // testDeprecatedReplaceWithNamedExpressionParses
            do {
                let samplePath = paths[6]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                #expect(diagnostics.count == 1, "Expected one deprecated diagnostic, got: \(sampleDiags)")
                #expect(diagnostics[0].message.contains("Replace with: newApi()"), "Expected replaceWith message, got: \(diagnostics[0].message)")
                #expect(diagnostics[0].codeActions.map(\.title) == ["Replace with 'newApi()'"])
            }
            // testDeprecatedErrorLevelWithReplaceWithStillEmitsError
            do {
                let samplePath = paths[7]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                #expect(diagnostics.count == 1, "Expected one deprecated diagnostic, got: \(sampleDiags)")
                let v5 = diagnostics.contains(where: isError)
                #expect(v5, "Expected deprecated error, got: \(sampleDiags)")
                #expect(diagnostics[0].message.contains("Replace with: newApi()"), "Expected replaceWith message, got: \(diagnostics[0].message)")
            }
            // testDeprecatedEmptyReplaceWithDoesNotAddSuggestion
            do {
                let samplePath = paths[8]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                #expect(diagnostics.count == 1, "Expected one deprecated diagnostic, got: \(sampleDiags)")
                #expect(!(diagnostics[0].message.contains("Replace with:")), "Did not expect replaceWith message, got: \(diagnostics[0].message)")
                #expect(diagnostics[0].codeActions.isEmpty, "Did not expect code actions for empty replaceWith")
            }
            // testDeprecatedSinceKotlinAcceptsDocumentedTargets
            do {
                let samplePath = paths[9]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected DeprecatedSinceKotlin target uses to be accepted, got: \(sampleDiags)")
            }
            // testDeprecatedSinceKotlinRejectsFileTarget
            do {
                let samplePath = paths[10]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected file-target diagnostic for DeprecatedSinceKotlin, got: \(sampleDiags)")
                let v7 = diagnostics.allSatisfy(isError)
                #expect(v7, "Annotation-target diagnostics should be errors")
            }
            // testSyntheticDeprecatedToCharEmitsWarning
            do {
                let samplePath = paths[11]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                #expect(diagnostics.count == 1, "Expected one deprecated diagnostic for toChar(), got: \(sampleDiags)")
                let v8 = diagnostics.contains(where: isError)
                #expect(v8, "Expected deprecated error for toChar(), got: \(sampleDiags)")
                #expect(diagnostics[0].message.contains("toChar"), "Expected toChar() in message, got: \(diagnostics[0].message)")
            }
            // testSyntheticDeprecatedStringSubSequenceEmitsWarning
            do {
                let samplePath = paths[12]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                #expect(diagnostics.count == 1, "Expected one deprecated diagnostic for subSequence(), got: \(sampleDiags)")
                let v9 = diagnostics.contains(where: isWarning)
                #expect(v9, "Expected deprecated warning for subSequence(), got: \(sampleDiags)")
                #expect(diagnostics[0].message.contains("subSequence"), "Expected subSequence() in message, got: \(diagnostics[0].message)")
            }
            // testSyntheticDeprecatedCreateTempDirEmitsError
            do {
                let samplePath = paths[13]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                #expect(diagnostics.count == 1, "Expected one deprecated diagnostic for createTempDir(), got: \(sampleDiags)")
                let v10 = diagnostics.contains(where: isError)
                #expect(v10, "Expected deprecated error for createTempDir(), got: \(sampleDiags)")
                #expect(diagnostics[0].message.contains("createTempDir"), "Expected createTempDir() in message, got: \(diagnostics[0].message)")
            }
            // testSuppressUncheckedCastByKotlinNameSuppressesDiagnostic
            do {
                let samplePath = paths[14]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-UNCHECKED-CAST" }

                #expect(diagnostics.count == 1, "Expected exactly one unchecked-cast warning from unsuppressed function, got: \(diagnostics)")
                let v11 = diagnostics.allSatisfy(isWarning)
                #expect(v11, "Unchecked-cast diagnostics should be warnings")
            }
            // testSuppressUncheckedCastByInternalCodeSuppressesDiagnostic
            do {
                let samplePath = paths[15]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-UNCHECKED-CAST" }

                #expect(diagnostics.count == 1, "Expected exactly one unchecked-cast warning from unsuppressed function, got: \(diagnostics)")
                let v12 = diagnostics.allSatisfy(isWarning)
                #expect(v12, "Unchecked-cast diagnostics should be warnings")
            }
            // testAnnotationTargetEnumConstantResolves
            do {
                let samplePath = paths[16]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected AnnotationTarget smoke test to compile cleanly, got: \(sampleDiags)")
            }
            // testOverloadResolutionByLambdaReturnTypeResolves
            do {
                let samplePath = paths[17]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected OverloadResolutionByLambdaReturnType smoke test to compile cleanly, got: \(sampleDiags)")
            }
            // testExperimentalTypeInferenceResolves
            do {
                let samplePath = paths[18]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected ExperimentalTypeInference smoke test to compile cleanly, got: \(sampleDiags)")
            }
            // testOptInResolves
            do {
                let samplePath = paths[19]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected OptIn smoke test to compile cleanly, got: \(sampleDiags)")
            }
            // testSubclassOptInRequiredResolves
            do {
                let samplePath = paths[20]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected SubclassOptInRequired smoke test to compile cleanly, got: \(sampleDiags)")
            }
            // testContextFunctionTypeParamsRejectsDeclarationUsage
            do {
                let samplePath = paths[21]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected one annotation-target diagnostic, got: \(sampleDiags)")
                let v14 = diagnostics.allSatisfy(isError)
                #expect(v14, "Annotation-target diagnostics should be errors")
            }
            // testContextFunctionTypeParamsRejectsTooLargeCount
            do {
                let samplePath = paths[22]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-CONTEXT-FN-TYPE" }

                #expect(diagnostics.count == 1, "Expected one context-function-type diagnostic, got: \(sampleDiags)")
                let v15 = diagnostics.allSatisfy(isError)
                #expect(v15, "Context-function-type diagnostics should be errors")
            }
            // testConsistentCopyVisibilityRejectsFunctionUse
            do {
                let samplePath = paths[23]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected class-only annotation target diagnostic, got: \(sampleDiags)")
                let v17 = diagnostics.allSatisfy(isError)
                #expect(v17, "Annotation-target diagnostics should be errors")
            }
            // testMustUseReturnValuesAllowsClassUse
            do {
                let samplePath = paths[24]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected @MustUseReturnValues to be accepted on classes, got: \(sampleDiags)")
            }
            // testMustUseReturnValuesAllowsFileUse
            do {
                let samplePath = paths[25]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected @file:MustUseReturnValues to be accepted, got: \(sampleDiags)")
            }
            // testMustUseReturnValuesRejectsFunctionUse
            do {
                let samplePath = paths[26]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected file-or-class annotation target diagnostic, got: \(sampleDiags)")
                let v19 = diagnostics.allSatisfy(isError)
                #expect(v19, "Annotation-target diagnostics should be errors")
            }
            // testBuilderInferenceAcceptsDocumentedTargets
            do {
                let samplePath = paths[27]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected BuilderInference target uses to be accepted, got: \(sampleDiags)")
            }
            // testBuilderInferenceRejectsClassTarget
            do {
                let samplePath = paths[28]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected class-target diagnostic for BuilderInference, got: \(sampleDiags)")
                let v23 = diagnostics.allSatisfy(isError)
                #expect(v23, "Annotation-target diagnostics should be errors")
            }
            // testIgnorableReturnValueAllowsFunctionUse
            do {
                let samplePath = paths[29]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected @IgnorableReturnValue to be accepted on functions, got: \(sampleDiags)")
            }
            // testIgnorableReturnValueRejectsClassUse
            do {
                let samplePath = paths[30]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected function-only annotation target diagnostic, got: \(sampleDiags)")
                let v25 = diagnostics.allSatisfy(isError)
                #expect(v25, "Annotation-target diagnostics should be errors")
            }
            // testExposedCopyVisibilityRejectsFunctionUse
            do {
                let samplePath = paths[31]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected class-only annotation target diagnostic, got: \(sampleDiags)")
                let v28 = diagnostics.allSatisfy(isError)
                #expect(v28, "Annotation-target diagnostics should be errors")
            }
            // testParameterNameAcceptsTypeUse
            do {
                let samplePath = paths[32]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)


                #expect(sampleDiags.isEmpty, "Expected ParameterName on a type use to compile, got: \(sampleDiags)")
            }
            // testParameterNameRejectsClassUse
            do {
                let samplePath = paths[33]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected ParameterName to reject class use, got: \(sampleDiags)")
                let v31 = diagnostics.allSatisfy(isError)
                #expect(v31, "Annotation-target diagnostics should be errors")
            }
            // testPublishedApiAcceptsDocumentedDeclarationTargets
            do {
                let samplePath = paths[34]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.isEmpty, "Expected PublishedApi declaration targets to be accepted, got: \(sampleDiags)")
            }
            // testPublishedApiRejectsFileTarget
            do {
                let samplePath = paths[35]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected PublishedApi to reject file target, got: \(sampleDiags)")
                let v34 = diagnostics.allSatisfy(isError)
                #expect(v34, "Annotation-target diagnostics should be errors")
            }
            // testDslMarkerAcceptsAnnotationClassAndRejectsRegularClassUse
            do {
                let samplePath = paths[36]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }

                #expect(diagnostics.count == 1, "Expected DslMarker to reject regular class use, got: \(sampleDiags)")
                let v35 = diagnostics.allSatisfy(isError)
                #expect(v35, "Annotation-target diagnostics should be errors")
            }
            // testDslMarkerCanMarkCustomDslAnnotation
            do {
                let samplePath = paths[37]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                #expect(sampleDiags.isEmpty, "Expected custom DslMarker annotation to compile, got: \(sampleDiags)")
            }
            // testDataClassCopyVisibilityWarningCanBeSuppressedByAlias
            do {
                let samplePath = paths[38]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DATA-COPY-VISIBILITY" }

                #expect(diagnostics.isEmpty, "Expected DATA_CLASS_COPY_VISIBILITY suppression alias to suppress diagnostic, got: \(sampleDiags)")
            }
            // testDeprecatedSinceKotlinRefinesSeverityAndHonorsSuppression
            do {
                let samplePath = paths[39]
                let sampleDiags = diagnosticsForPath(samplePath, in: ctx)

                let diagnostics = sampleDiags.filter { $0.code == "KSWIFTK-SEMA-DEPRECATED" }

                #expect(diagnostics.count == 2, "Expected only unsuppressed error/warning diagnostics, got: \(sampleDiags)")
                #expect(diagnostics.contains(where: isError), "Expected errorSince to promote the diagnostic, got: \(diagnostics)")
                #expect(diagnostics.contains(where: isWarning), "Expected warningSince to retain a warning, got: \(diagnostics)")
                #expect(diagnostics.contains(where: { $0.message.contains("sinceError") }))
                #expect(diagnostics.contains(where: { $0.message.contains("sinceWarning") }))
                #expect(!diagnostics.contains(where: { $0.message.contains("sinceHidden") }))
            }

        }
    }


    @Test func testAnnotationSemanticSurfaceRegistrations() throws {
        let sources: [String] = [
            // testDeprecatedSinceKotlinSurfaceHasVersionPropertiesAndDefaults
            """
            package sample0
            fun noop() {}
            """,
            // testSubclassOptInRequiredMarkerClassPropertyIsRegistered
            """
            package sample1
            fun noop() {}
            """,
            // testContextFunctionTypeParamsSurfaceIsRegistered
            """
            package sample2
            fun noop() {}
            """,
            // testConsistentCopyVisibilityResolvesAndTargetsClasses
            """
            package sample3
            fun noop() {}
            """,
            // testMustUseReturnValuesResolvesAndTargetsFileAndClass
            """
            package sample4
            fun marker(x: MustUseReturnValues?): Int = 0
            """,
            // testBuilderInferenceAnnotationSurfaceIsRegisteredAndTargeted
            """
            package sample5
            fun noop() {}
            """,
            // testIgnorableReturnValueResolvesAndTargetsFunctions
            """
            package sample6
            fun marker(x: IgnorableReturnValue?): Int = 0
            """,
            // testExposedCopyVisibilityResolvesAndTargetsClasses
            """
            package sample7
            fun noop() {}
            """,
            // testDslMarkerResolvesAndTargetsAnnotationClasses
            """
            package sample8
            fun noop() {}
            """,
            // testParameterNameSurfaceHasNamePropertyConstructorAndTypeTarget
            """
            package sample9
            fun noop() {}
            """,
            // testPublishedApiSurfaceHasDeclarationTargetsAndBinaryRetention
            """
            package sample10
            fun noop() {}
            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)

            // testDeprecatedSinceKotlinSurfaceHasVersionPropertiesAndDefaults
            do {
            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("DeprecatedSinceKotlin"),
            ]
            let symbolID = try #require(sema.symbols.lookup(fqName: fqName))
            let symbol = try #require(sema.symbols.symbol(symbolID))

            #expect(symbol.kind == .annotationClass)
            #expect(symbol.visibility == .public)

            let annotations = sema.symbols.annotations(for: symbolID)
            let v6 = annotations.contains {
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
            }
            #expect(
                v6,
                "DeprecatedSinceKotlin should carry its declaration target list, got: \(annotations)"
            )

            let propertyNames = ["warningSince", "errorSince", "hiddenSince"]
            for propertyName in propertyNames {
                let propertySymbol = try #require(
                    sema.symbols.lookup(fqName: fqName + [ctx.interner.intern(propertyName)])
                )
                #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.stringType)
            }

            let initName = ctx.interner.intern("<init>")
            let ctorSymbol = try #require(
                sema.symbols.lookupAll(fqName: fqName + [initName]).first {
                    sema.symbols.symbol($0)?.kind == .constructor
                }
            )
            let signature = try #require(sema.symbols.functionSignature(for: ctorSymbol))
            #expect(signature.parameterTypes == Array(repeating: sema.types.stringType, count: 3))
            #expect(signature.valueParameterHasDefaultValues == [true, true, true])
            #expect(signature.valueParameterIsVararg == [false, false, false])

            }
            // testSubclassOptInRequiredMarkerClassPropertyIsRegistered
            do {
            let valueSymbol = try #require(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("SubclassOptInRequired"),
                    ctx.interner.intern("markerClass"),
                ]),
                "kotlin.SubclassOptInRequired.markerClass must be registered"
            )
            #expect(sema.symbols.propertyType(for: valueSymbol) != nil, "markerClass must have a property type")

            }
            // testContextFunctionTypeParamsSurfaceIsRegistered
            do {
            let annotationFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("ContextFunctionTypeParams"),
            ]
            let annotationSymbol = try #require(
                sema.symbols.lookup(fqName: annotationFQName),
                "kotlin.ContextFunctionTypeParams must be registered"
            )
            #expect(sema.symbols.symbol(annotationSymbol)?.kind == .annotationClass)

            let annotations = sema.symbols.annotations(for: annotationSymbol)
            let v13 = annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments.contains("AnnotationTarget.TYPE")
            }
            #expect(v13, "ContextFunctionTypeParams must be targeted to type usages")

            let countSymbol = try #require(
                sema.symbols.lookup(fqName: annotationFQName + [ctx.interner.intern("count")]),
                "kotlin.ContextFunctionTypeParams.count must be registered"
            )
            #expect(sema.symbols.propertyType(for: countSymbol) == sema.types.intType)

            let ctorSymbol = try #require(
                sema.symbols.lookupAll(fqName: annotationFQName + [ctx.interner.intern("<init>")]).first(where: {
                    sema.symbols.functionSignature(for: $0)?.parameterTypes == [sema.types.intType]
                }),
                "kotlin.ContextFunctionTypeParams(count: Int) constructor must be registered"
            )
            #expect(sema.symbols.functionSignature(for: ctorSymbol)?.returnType == sema.types.make(.classType(ClassType(
                classSymbol: annotationSymbol,
                args: [],
                nullability: .nonNull
            ))))

            }
            // testConsistentCopyVisibilityResolvesAndTargetsClasses
            do {
            let symbol = try #require(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("ConsistentCopyVisibility"),
                ]),
                "kotlin.ConsistentCopyVisibility must be registered"
            )
            let annotations = sema.symbols.annotations(for: symbol)
            let v16 = annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.CLASS"]
            }
            #expect(
                v16,
                "ConsistentCopyVisibility should target classes, got: \(annotations)"
            )

            }
            // testMustUseReturnValuesResolvesAndTargetsFileAndClass
            do {
            let symbol = try #require(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("MustUseReturnValues"),
                ]),
                "kotlin.MustUseReturnValues must be registered"
            )
            let symbolInfo = try #require(sema.symbols.symbol(symbol))
            #expect(symbolInfo.kind == .annotationClass, "MustUseReturnValues must be an annotation class")

            let annotations = sema.symbols.annotations(for: symbol)
            let v18 = annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && Set($0.arguments) == Set(["AnnotationTarget.FILE", "AnnotationTarget.CLASS"])
            }
            #expect(
                v18,
                "MustUseReturnValues should target files and classes, got: \(annotations)"
            )

            }
            // testBuilderInferenceAnnotationSurfaceIsSyntheticAndTargeted
            do {
            let symbolID = try #require(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("BuilderInference"),
                ]),
                "kotlin.BuilderInference must be registered"
            )
            let symbol = try #require(sema.symbols.symbol(symbolID))

            #expect(symbol.kind == .annotationClass)
            #expect(symbol.visibility == .public)
            #expect(!symbol.flags.contains(.synthetic))

            let annotations = sema.symbols.annotations(for: symbolID)
            let v20 = annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == [
                        "AnnotationTarget.VALUE_PARAMETER",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                    ]
            }
            #expect(
                v20,
                "BuilderInference should target value parameters, functions, and properties, got: \(annotations)"
            )
            let v21 = annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.BINARY"]
            }
            #expect(
                v21,
                "BuilderInference should carry binary retention, got: \(annotations)"
            )
            let v22 = annotations.contains {
                KnownCompilerAnnotation.experimentalTypeInference.matches($0.annotationFQName)
            }
            #expect(
                v22,
                "BuilderInference should be annotated with ExperimentalTypeInference, got: \(annotations)"
            )

            }
            // testIgnorableReturnValueResolvesAndTargetsFunctions
            do {
            let symbol = try #require(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("IgnorableReturnValue"),
                ]),
                "kotlin.IgnorableReturnValue must be registered"
            )
            let symbolInfo = try #require(sema.symbols.symbol(symbol))
            #expect(symbolInfo.kind == .annotationClass, "IgnorableReturnValue must be an annotation class")

            let annotations = sema.symbols.annotations(for: symbol)
            let v24 = annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.FUNCTION"]
            }
            #expect(
                v24,
                "IgnorableReturnValue should target functions, got: \(annotations)"
            )

            }
            // testExposedCopyVisibilityResolvesAndTargetsClasses
            do {
            let symbol = try #require(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("ExposedCopyVisibility"),
                ]),
                "kotlin.ExposedCopyVisibility must be registered"
            )

            let annotations = sema.symbols.annotations(for: symbol)
            let v26 = annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.CLASS"]
            }
            #expect(
                v26,
                "ExposedCopyVisibility should target classes, got: \(annotations)"
            )

            }
            // testDslMarkerResolvesAndTargetsAnnotationClasses
            do {
            let symbol = try #require(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("DslMarker"),
                ]),
                "kotlin.DslMarker must be registered"
            )
            let declaration = try #require(sema.symbols.symbol(symbol))

            #expect(declaration.kind == .annotationClass)
            #expect(declaration.visibility == .public)
            #expect(!declaration.flags.contains(.synthetic))

            let annotations = sema.symbols.annotations(for: symbol)
            let v27 = annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
            }
            #expect(
                v27,
                "DslMarker should target annotation classes, got: \(annotations)"
            )

            }
            // testParameterNameSurfaceHasNamePropertyConstructorAndTypeTarget
            do {
            let fqName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("ParameterName"),
            ]
            let symbol = try #require(sema.symbols.lookup(fqName: fqName))
            let declaration = try #require(sema.symbols.symbol(symbol))

            #expect(declaration.kind == .annotationClass)
            #expect(declaration.visibility == .public)

            let annotations = sema.symbols.annotations(for: symbol)
            let v29 = annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.TYPE"]
            }
            #expect(
                v29,
                "ParameterName should target type uses, got: \(annotations)"
            )
            let v30 = annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.BINARY"]
            }
            #expect(
                v30,
                "ParameterName should carry binary retention, got: \(annotations)"
            )

            let propertySymbol = try #require(
                sema.symbols.lookup(fqName: fqName + [ctx.interner.intern("name")])
            )
            #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.stringType)

            let ctorSymbol = try #require(
                sema.symbols.lookupAll(fqName: fqName + [ctx.interner.intern("<init>")]).first {
                    sema.symbols.symbol($0)?.kind == .constructor
                }
            )
            let signature = try #require(sema.symbols.functionSignature(for: ctorSymbol))
            #expect(signature.parameterTypes == [sema.types.stringType])
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [false])

            }
            // testPublishedApiSurfaceHasDeclarationTargetsAndBinaryRetention
            do {
            let symbol = try #require(
                sema.symbols.lookup(fqName: [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("PublishedApi"),
                ]),
                "kotlin.PublishedApi must be registered"
            )
            let declaration = try #require(sema.symbols.symbol(symbol))

            #expect(declaration.kind == .annotationClass)
            #expect(declaration.visibility == .public)

            let annotations = sema.symbols.annotations(for: symbol)
            let v32 = annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                    ]
            }
            #expect(
                v32,
                "PublishedApi should target public ABI declaration sites, got: \(annotations)"
            )
            let v33 = annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.BINARY"]
            }
            #expect(
                v33,
                "PublishedApi should carry binary retention, got: \(annotations)"
            )

            }
        }
    }

    @Test func testIntToCharNotDeprecated() throws {
        let source = """
        package test

        fun caller(): Char = 65.toChar()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let deprecatedDiagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DEPRECATED", in: ctx)

        #expect(
            deprecatedDiagnostics.isEmpty,
            "Int.toChar() should not be deprecated in Kotlin 2.3.10, got: \(deprecatedDiagnostics)"
        )
    }



    @Test func testContextFunctionTypeParamsResolvesAnnotatedFunctionType() throws {
        let source = """
        interface Host {
            val action: @ContextFunctionTypeParams(2) @ExtensionFunctionType Function4<String, Int, Double, Byte, Unit>
            val block: @ContextFunctionTypeParams(count = 1) Function2<String, Byte, Unit>
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected ContextFunctionTypeParams source to compile cleanly, got: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let file = try #require(ast.files.first)
        let interfaceDeclID = try #require(
            file.topLevelDecls.first(where: {
                if case .interfaceDecl = ast.arena.decl($0) {
                    return true
                }
                return false
            })
        )
        guard case let .interfaceDecl(interfaceDecl) = ast.arena.decl(interfaceDeclID) else {
            Issue.record("Expected interface declaration")
            return
        }

        let actionPropertyType = try propertyType(named: "action", in: interfaceDecl, ast: ast, sema: sema, interner: ctx.interner)
        guard case let .functionType(actionFunctionType) = sema.types.kind(of: actionPropertyType) else {
            Issue.record("Expected action to resolve as a function type")
            return
        }
        #expect(actionFunctionType.contextReceivers == [sema.types.stringType, sema.types.intType])
        #expect(actionFunctionType.receiver == sema.types.doubleType)
        #expect(actionFunctionType.params == [sema.types.byteType])
        #expect(actionFunctionType.returnType == sema.types.unitType)

        let blockPropertyType = try propertyType(named: "block", in: interfaceDecl, ast: ast, sema: sema, interner: ctx.interner)
        guard case let .functionType(blockFunctionType) = sema.types.kind(of: blockPropertyType) else {
            Issue.record("Expected block to resolve as a function type, got \(sema.types.renderType(blockPropertyType))")
            return
        }
        #expect(blockFunctionType.contextReceivers == [sema.types.stringType])
        #expect(blockFunctionType.receiver == nil)
        #expect(blockFunctionType.params == [sema.types.byteType])
        #expect(blockFunctionType.returnType == sema.types.unitType)
    }


    @Test func testPrivateDataClassCopyVisibilityMigrationWarnsAndKeepsPublicCopy() throws {
        let source = """
        package test

        data class Secret private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        #expect(diagnostics.count == 1, "Expected one data class copy visibility warning, got: \(ctx.diagnostics.diagnostics)")
        let v36 = diagnostics.allSatisfy(isWarning)
        #expect(v36, "Data class copy visibility diagnostic should be a warning")
        #expect(diagnostics[0].message.contains("private"), "Expected primary constructor visibility in message, got: \(diagnostics[0].message)")
        #expect(
            try symbolVisibility(["test", "Secret", "copy"], in: ctx) == .public,
            "Unannotated migration mode should keep copy() public"
        )
    }


    @Test func testConsistentCopyVisibilityMakesCopyUseConstructorVisibility() throws {
        let source = """
        package test

        @ConsistentCopyVisibility
        data class Secret private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        #expect(diagnostics.isEmpty, "Expected ConsistentCopyVisibility to opt in to constructor visibility, got: \(ctx.diagnostics.diagnostics)")
        #expect(
            try symbolVisibility(["test", "Secret", "copy"], in: ctx) == .private,
            "Annotated data class copy() should use the private primary constructor visibility"
        )
    }


    @Test func testExposedCopyVisibilitySuppressesWarningAndKeepsPublicCopy() throws {
        let source = """
        package test

        @ExposedCopyVisibility
        data class Secret private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        #expect(diagnostics.isEmpty, "Expected ExposedCopyVisibility to suppress migration warning, got: \(ctx.diagnostics.diagnostics)")
        #expect(
            try symbolVisibility(["test", "Secret", "copy"], in: ctx) == .public,
            "ExposedCopyVisibility should keep copy() public"
        )
    }

}
#endif
