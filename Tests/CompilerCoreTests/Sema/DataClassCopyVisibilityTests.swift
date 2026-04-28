@testable import CompilerCore
import Foundation
import XCTest

final class DataClassCopyVisibilityTests: XCTestCase {
    func testPrivatePrimaryConstructorDataClassEmitsCopyVisibilityWarning() {
        let source = """
        data class Token private constructor(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        XCTAssertEqual(diagnostics.count, 1, "Expected one copy-visibility migration warning, got: \(ctx.diagnostics.diagnostics)")
        XCTAssertTrue(diagnostics.allSatisfy(isWarning), "Copy-visibility migration diagnostics should be warnings")
    }

    func testConsistentCopyVisibilitySuppressesWarningAndNarrowsCopyVisibility() throws {
        let source = """
        @ConsistentCopyVisibility
        data class Token private constructor(val value: Int)
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)
        XCTAssertTrue(diagnostics.isEmpty, "Expected @ConsistentCopyVisibility to suppress declaration warning, got: \(ctx.diagnostics.diagnostics)")

        let sema = try XCTUnwrap(ctx.sema)
        let copySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("Token"),
                ctx.interner.intern("copy"),
            ]).first
        )
        let copy = try XCTUnwrap(sema.symbols.symbol(copySymbol))

        XCTAssertEqual(copy.visibility, .private)
    }

    func testExposedCopyVisibilitySuppressesWarningButKeepsCopyPublic() throws {
        let source = """
        @ExposedCopyVisibility
        data class Token private constructor(val value: Int)
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)
        XCTAssertTrue(diagnostics.isEmpty, "Expected @ExposedCopyVisibility to suppress declaration warning, got: \(ctx.diagnostics.diagnostics)")

        let sema = try XCTUnwrap(ctx.sema)
        let copySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("Token"),
                ctx.interner.intern("copy"),
            ]).first
        )
        let copy = try XCTUnwrap(sema.symbols.symbol(copySymbol))

        XCTAssertEqual(copy.visibility, .public)
    }

    func testUnannotatedCopyVisibilityStaysPublicDuringMigration() throws {
        let source = """
        data class Token private constructor(val value: Int)
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let copySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("Token"),
                ctx.interner.intern("copy"),
            ]).first
        )
        let copy = try XCTUnwrap(sema.symbols.symbol(copySymbol))

        XCTAssertEqual(copy.visibility, .public)
    }

    func testPublicConstructorDataClassDoesNotEmitCopyVisibilityWarning() {
        let source = """
        data class Token(val value: Int)
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-DATA-COPY-VISIBILITY", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected no copy-visibility diagnostic for public primary constructor, got: \(ctx.diagnostics.diagnostics)")
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
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

    private func isWarning(_ diagnostic: Diagnostic) -> Bool {
        if case .warning = diagnostic.severity {
            return true
        }
        return false
    }
}
