@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-FN-015: Validates that `File.copyTo(target, overwrite, bufferSize)`
/// resolves through Sema for the `java.io.File` receiver and produces a `File`.
///
/// The runtime link name exercised here is `kk_file_copyTo`.
///
/// Kotlin signature:
///
///     public fun File.copyTo(
///         target: File,
///         overwrite: Boolean = false,
///         bufferSize: Int = DEFAULT_BUFFER_SIZE
///     ): File
///
/// Declared in the `kotlin.io` package.
final class FileCopyToFunctionTests: XCTestCase {

    // MARK: - Single-argument overload (defaults for overwrite and bufferSize)

    func testFileCopyToWithJustTargetResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.File
        import kotlin.io.copyTo

        fun copy(source: File, dest: File): File = source.copyTo(dest)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected File.copyTo(target) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Two-argument overload (overwrite supplied)

    func testFileCopyToWithOverwriteFlagResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.File
        import kotlin.io.copyTo

        fun copy(source: File, dest: File): File = source.copyTo(dest, true)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected File.copyTo(target, overwrite) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Three-argument overload (all parameters supplied)

    func testFileCopyToWithAllArgumentsResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.File
        import kotlin.io.copyTo

        fun copy(source: File, dest: File): File = source.copyTo(dest, false, 8 * 1024)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected File.copyTo(target, overwrite, bufferSize) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Named arguments via default values

    func testFileCopyToWithNamedBufferSizeResolves() throws {
        let ctx = makeContextFromSource("""
        import java.io.File
        import kotlin.io.copyTo

        fun copy(source: File, dest: File): File =
            source.copyTo(target = dest, bufferSize = 4096)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected File.copyTo with named bufferSize to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Sema surface inspection

    func testFileCopyToExtensionFunctionSurfaceIsRegistered() throws {
        let source = """
        import java.io.File
        import kotlin.io.copyTo

        fun copy(source: File, dest: File): File = source.copyTo(dest, true, 4096)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "File.copyTo extension function in kotlin.io should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

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

            let copyToCandidates = symbols.lookupAll(
                fqName: ["kotlin", "io", "copyTo"].map(interner.intern)
            )
            let copyTo = try XCTUnwrap(copyToCandidates.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == fileType
                    && signature.parameterTypes == [fileType, types.booleanType, types.intType]
                    && signature.returnType == fileType
            })

            XCTAssertEqual(
                symbols.externalLinkName(for: copyTo),
                "kk_file_copyTo"
            )

            let signature = try XCTUnwrap(symbols.functionSignature(for: copyTo))
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, true, true])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, false, false])
        }
    }
}
