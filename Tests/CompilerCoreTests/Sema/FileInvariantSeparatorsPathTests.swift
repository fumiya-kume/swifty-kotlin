@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-IO-PROP-003: File.invariantSeparatorsPath
//
// Sema-surface tests for the `kotlin.io.invariantSeparatorsPath` extension
// property on `java.io.File`.
//
// Kotlin signature:
//   public val File.invariantSeparatorsPath: String
//     get() = if (File.separatorChar != '/') path.replace(File.separatorChar, '/') else path

final class FileInvariantSeparatorsPathTests: XCTestCase {

    // MARK: - Resolves with explicit import

    func testFileInvariantSeparatorsPathWithExplicitImportResolves() throws {
        let source = """
        import java.io.File
        import kotlin.io.invariantSeparatorsPath

        fun normalized(file: File): String {
            return file.invariantSeparatorsPath
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.invariantSeparatorsPath in kotlin.io should resolve as String: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    // MARK: - Returned value typed as String

    func testFileInvariantSeparatorsPathReturnsString() throws {
        let source = """
        import java.io.File
        import kotlin.io.invariantSeparatorsPath

        fun length(file: File): Int {
            val normalized: String = file.invariantSeparatorsPath
            return normalized.length
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.invariantSeparatorsPath should type as String, allowing .length use: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    // MARK: - Inline File construction

    func testFileInvariantSeparatorsPathOnFreshlyConstructedFile() throws {
        let source = """
        import java.io.File
        import kotlin.io.invariantSeparatorsPath

        fun main() {
            val s: String = File("/tmp/foo").invariantSeparatorsPath
            println(s)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File(...).invariantSeparatorsPath should compile end-to-end through Sema: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
        }
    }

    // MARK: - External link name is registered on the synthetic symbol

    func testFileInvariantSeparatorsPathExternalLinkNameIsRegistered() throws {
        let source = """
        import java.io.File
        import kotlin.io.invariantSeparatorsPath

        fun stub(file: File): String = file.invariantSeparatorsPath
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try XCTUnwrap(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types

            let fileSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
            )
            let fileType = types.make(.classType(ClassType(
                classSymbol: fileSymbol, args: [], nullability: .nonNull
            )))

            let candidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "invariantSeparatorsPath"].map(interner.intern)
            )
            let property = try XCTUnwrap(candidates.first { symbolID in
                guard symbols.symbol(symbolID)?.kind == .property else {
                    return false
                }
                return symbols.extensionPropertyReceiverType(for: symbolID) == fileType
            })

            XCTAssertEqual(
                symbols.externalLinkName(for: property),
                "kk_file_invariantSeparatorsPath"
            )
            XCTAssertEqual(symbols.propertyType(for: property), types.stringType)
        }
    }
}
