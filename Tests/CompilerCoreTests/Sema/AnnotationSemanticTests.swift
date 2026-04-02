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

    func testBuilderInferenceAnnotationIsRecordedOnValueParameter() throws {
        let source = """
        fun <T> build(@BuilderInference block: MutableList<T>.() -> Unit): List<T> = TODO()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected builder inference annotation sample to type-check, got: \(ctx.diagnostics.diagnostics)")

        let sema = try XCTUnwrap(ctx.sema)
        let buildSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [ctx.interner.intern("build")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: buildSymbol))
        let parameterSymbol = signature.valueParameterSymbols[0]
        let annotations = sema.symbols.annotations(for: parameterSymbol)

        XCTAssertTrue(
            annotations.contains(where: { KnownCompilerAnnotation.builderInference.matches($0.annotationFQName) }),
            "Expected @BuilderInference to be recorded on the value parameter, got: \(annotations)"
        )
    }

    func testBuilderInferenceRejectsFunctionTargetUsage() {
        let source = """
        @BuilderInference
        fun bad() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one annotation-target diagnostic, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isError), "Annotation-target diagnostics should be errors")
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
>>>>>>> origin/master
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
    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    private func isError(_ diagnostic: Diagnostic) -> Bool {
        if case .error = diagnostic.severity {
            return true
        }
        return false
    }

    private func isWarning(_ diagnostic: Diagnostic) -> Bool {
        if case .warning = diagnostic.severity {
            return true
        }
        return false
    }
}
