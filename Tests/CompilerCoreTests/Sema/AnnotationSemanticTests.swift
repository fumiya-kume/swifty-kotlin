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

    func testContextFunctionTypeParamsSurfaceIsRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let annotationFQName = [
            interner.intern("kotlin"),
            interner.intern("ContextFunctionTypeParams"),
        ]
        let annotationSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: annotationFQName),
            "kotlin.ContextFunctionTypeParams must be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(annotationSymbol)?.kind, .annotationClass)

        let annotations = sema.symbols.annotations(for: annotationSymbol)
        XCTAssertTrue(annotations.contains {
            $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                && $0.arguments.contains("AnnotationTarget.TYPE")
        }, "ContextFunctionTypeParams must be targeted to type usages")

        let countSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: annotationFQName + [interner.intern("count")]),
            "kotlin.ContextFunctionTypeParams.count must be registered"
        )
        XCTAssertEqual(sema.symbols.propertyType(for: countSymbol), sema.types.intType)

        let ctorSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: annotationFQName + [interner.intern("<init>")]).first(where: {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == [sema.types.intType]
            }),
            "kotlin.ContextFunctionTypeParams(count: Int) constructor must be registered"
        )
        XCTAssertEqual(sema.symbols.functionSignature(for: ctorSymbol)?.returnType, sema.types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        ))))
    }

    func testContextFunctionTypeParamsResolvesAnnotatedFunctionType() throws {
        let source = """
        interface Host {
            val action: @ContextFunctionTypeParams(2) @ExtensionFunctionType Function4<String, Int, Double, Byte, Unit>
            val block: @ContextFunctionTypeParams(count = 1) Function2<String, Byte, Unit>
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected ContextFunctionTypeParams source to compile cleanly, got: \(ctx.diagnostics.diagnostics)")

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
            return XCTFail("Expected interface declaration")
        }

        let actionPropertyType = try propertyType(named: "action", in: interfaceDecl, ast: ast, sema: sema, interner: ctx.interner)
        guard case let .functionType(actionFunctionType) = sema.types.kind(of: actionPropertyType) else {
            return XCTFail("Expected action to resolve as a function type")
        }
        XCTAssertEqual(actionFunctionType.contextReceivers, [sema.types.stringType, sema.types.intType])
        XCTAssertEqual(actionFunctionType.receiver, sema.types.doubleType)
        XCTAssertEqual(actionFunctionType.params, [sema.types.intType])
        XCTAssertEqual(actionFunctionType.returnType, sema.types.unitType)

        let blockPropertyType = try propertyType(named: "block", in: interfaceDecl, ast: ast, sema: sema, interner: ctx.interner)
        guard case let .functionType(blockFunctionType) = sema.types.kind(of: blockPropertyType) else {
            return XCTFail("Expected block to resolve as a function type, got \(sema.types.renderType(blockPropertyType))")
        }
        XCTAssertEqual(blockFunctionType.contextReceivers, [sema.types.stringType])
        XCTAssertNil(blockFunctionType.receiver)
        XCTAssertEqual(blockFunctionType.params, [sema.types.intType])
        XCTAssertEqual(blockFunctionType.returnType, sema.types.unitType)
    }

    func testContextFunctionTypeParamsRejectsDeclarationUsage() {
        let source = """
        @ContextFunctionTypeParams(1)
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one annotation-target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testContextFunctionTypeParamsRejectsTooLargeCount() {
        let source = """
        interface Host {
            val invalid: @ContextFunctionTypeParams(3) Function2<String, Int, Unit>
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-CONTEXT-FN-TYPE", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one context-function-type diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Context-function-type diagnostics should be errors")
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

    func testExposedCopyVisibilityResolvesAndTargetsClasses() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("ExposedCopyVisibility"),
            ]),
            "kotlin.ExposedCopyVisibility must be registered"
        )

        let annotations = sema.symbols.annotations(for: symbol)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.CLASS"]
            },
            "ExposedCopyVisibility should target classes, got: \(annotations)"
        )
    }

    func testDslMarkerResolvesAndTargetsAnnotationClasses() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("DslMarker"),
            ]),
            "kotlin.DslMarker must be registered"
        )
        let declaration = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(declaration.kind, .annotationClass)
        XCTAssertEqual(declaration.visibility, .public)
        XCTAssertTrue(declaration.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbol)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
            },
            "DslMarker should target annotation classes, got: \(annotations)"
        )
    }

    func testExposedCopyVisibilityRejectsFunctionUse() {
        let source = """
        @ExposedCopyVisibility
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected class-only annotation target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testParameterNameSurfaceHasNamePropertyConstructorAndTypeTarget() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("ParameterName"),
        ]
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let declaration = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(declaration.kind, .annotationClass)
        XCTAssertEqual(declaration.visibility, .public)
        XCTAssertTrue(declaration.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbol)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == ["AnnotationTarget.TYPE"]
            },
            "ParameterName should target type uses, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.BINARY"]
            },
            "ParameterName should carry binary retention, got: \(annotations)"
        )

        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName + [ctx.interner.intern("name")])
        )
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), sema.types.stringType)

        let ctorSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fqName + [ctx.interner.intern("<init>")]).first {
                sema.symbols.symbol($0)?.kind == .constructor
            }
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: ctorSymbol))
        XCTAssertEqual(signature.parameterTypes, [sema.types.stringType])
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.valueParameterIsVararg, [false])
    }

    func testParameterNameAcceptsTypeUse() {
        let source = """
        interface Host {
            val value: @ParameterName(name = "value") String
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)

        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected ParameterName on a type use to compile, got: \(ctx.diagnostics.diagnostics)")
    }

    func testParameterNameRejectsClassUse() {
        let source = """
        @ParameterName("Bad")
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected ParameterName to reject class use, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testPublishedApiSurfaceHasDeclarationTargetsAndBinaryRetention() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try XCTUnwrap(ctx.sema)
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("PublishedApi"),
            ]),
            "kotlin.PublishedApi must be registered"
        )
        let declaration = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(declaration.kind, .annotationClass)
        XCTAssertEqual(declaration.visibility, .public)
        XCTAssertTrue(declaration.flags.contains(.synthetic))

        let annotations = sema.symbols.annotations(for: symbol)
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == KnownCompilerAnnotation.target.qualifiedName
                    && $0.arguments == [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                    ]
            },
            "PublishedApi should target public ABI declaration sites, got: \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.BINARY"]
            },
            "PublishedApi should carry binary retention, got: \(annotations)"
        )
    }

    func testPublishedApiAcceptsDocumentedDeclarationTargets() {
        let source = """
        @PublishedApi
        internal class InternalHost {
            @PublishedApi
            internal val value: Int = 1

            @PublishedApi
            internal fun expose(): Int = value
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected PublishedApi declaration targets to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    func testPublishedApiRejectsFileTarget() {
        let source = """
        @file:PublishedApi

        package sample
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected PublishedApi to reject file target, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testDslMarkerAcceptsAnnotationClassAndRejectsRegularClassUse() {
        let source = """
        @DslMarker
        annotation class HtmlDsl

        @DslMarker
        class Bad
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected DslMarker to reject regular class use, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
    }

    func testDslMarkerCanMarkCustomDslAnnotation() {
        let source = """
        @DslMarker
        annotation class HtmlDsl

        @HtmlDsl
        class Tag
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected custom DslMarker annotation to compile, got: \(ctx.diagnostics.diagnostics)")
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

    func testExposedCopyVisibilitySuppressesWarningAndKeepsPublicCopy() throws {
        let source = """
        package test

        @ExposedCopyVisibility
        data class Secret private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected ExposedCopyVisibility to suppress migration warning, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertEqual(
            try symbolVisibility(["test", "Secret", "copy"], in: ctx),
            .public,
            "ExposedCopyVisibility should keep copy() public"
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

}
