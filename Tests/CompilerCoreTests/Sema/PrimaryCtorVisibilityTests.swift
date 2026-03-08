@testable import CompilerCore
import Foundation
import XCTest

final class PrimaryCtorVisibilityTests: XCTestCase {
    func testPrimaryConstructorUsesExplicitVisibilityModifiers() throws {
        let source = """
        package test

        class Hidden private constructor()
        sealed class SealedHidden private constructor()
        class Outer {
            class Nested private constructor()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "CtorVis")
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertEqual(
                constructorVisibility(["test", "Hidden"], symbols: sema.symbols, interner: ctx.interner),
                .private
            )
            XCTAssertEqual(
                constructorVisibility(["test", "SealedHidden"], symbols: sema.symbols, interner: ctx.interner),
                .private
            )
            XCTAssertEqual(
                constructorVisibility(["test", "Outer", "Nested"], symbols: sema.symbols, interner: ctx.interner),
                .private
            )
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    func testInvalidExplicitTypeArgumentsOnStringFormatReportResolutionError() throws {
        let source = """
        fun main() {
            val text = "%s".format<String>("age")
            println(text)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FormatFallback")
            try runSema(ctx)

            assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        }
    }

    private func constructorVisibility(
        _ typePath: [String],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> Visibility? {
        let fqName = typePath.map(interner.intern) + [interner.intern("<init>")]
        guard let symbolID = symbols.lookup(fqName: fqName),
              let symbol = symbols.symbol(symbolID)
        else {
            return nil
        }
        return symbol.visibility
    }
}
