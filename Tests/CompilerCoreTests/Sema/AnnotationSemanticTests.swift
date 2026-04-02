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

        XCTAssertEqual(annotation.arguments, ["markerClass=ExperimentalApiclass"])
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
