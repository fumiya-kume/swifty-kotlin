@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-IO-TYPE-003: Validates that the `kotlin.io.FileSystemException`
/// synthetic class is registered with the expected constructor surface,
/// supertype chain, and read-only `file` / `other` / `reason` properties.
final class FileSystemExceptionClassTests: XCTestCase {
    func testFileSystemExceptionConstructorAndPropertiesResolveInSource() throws {
        let source = """
        import java.io.File
        import kotlin.io.FileSystemException

        fun raiseSingle(file: File): Nothing {
            throw FileSystemException(file)
        }

        fun raiseWithOther(file: File, other: File?): Nothing {
            throw FileSystemException(file, other)
        }

        fun raiseFull(file: File, other: File?, reason: String?): Nothing {
            throw FileSystemException(file, other, reason)
        }

        fun extractFile(ex: FileSystemException): File {
            return ex.file
        }

        fun extractOther(ex: FileSystemException): File? {
            return ex.other
        }

        fun extractReason(ex: FileSystemException): String? {
            return ex.reason
        }

        fun catchUpcast(file: File) {
            try {
                throw FileSystemException(file)
            } catch (e: Exception) {
                // Sub-typing through Exception must hold.
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            diagnostics.isEmpty,
            "kotlin.io.FileSystemException should be wired through Sema: \(diagnostics.map { "\($0.code): \($0.message)" })"
        )
    }

    func testFileSystemExceptionSymbolTableSurface() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner
            let symbols = sema.symbols
            let types = sema.types

            let fileSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
            )
            let fileType = types.make(.classType(ClassType(
                classSymbol: fileSymbol, args: [], nullability: .nonNull
            )))
            let nullableFileType = types.makeNullable(fileType)
            let nullableStringType = types.makeNullable(types.stringType)

            let fseFQName = ["kotlin", "io", "FileSystemException"].map(interner.intern)
            let fseSymbol = try XCTUnwrap(symbols.lookup(fqName: fseFQName))

            // Class is registered under the kotlin.io package.
            let kotlinIOPkg = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "io"].map(interner.intern))
            )
            XCTAssertEqual(symbols.parentSymbol(for: fseSymbol), kotlinIOPkg)

            // Supertype chain: FileSystemException : Exception.
            let exceptionSymbol = try XCTUnwrap(
                symbols.lookup(fqName: ["kotlin", "Exception"].map(interner.intern))
            )
            XCTAssertEqual(symbols.directSupertypes(for: fseSymbol), [exceptionSymbol])

            // Three constructor overloads exist, all bound to kk_throwable_new.
            let ctorFQName = fseFQName + [interner.intern("<init>")]
            let constructors = symbols.lookupAll(fqName: ctorFQName).filter { symbolID in
                symbols.symbol(symbolID)?.kind == .constructor
            }
            let constructorSignatures = constructors.compactMap { symbols.functionSignature(for: $0)?.parameterTypes }
            XCTAssertTrue(constructorSignatures.contains([fileType]))
            XCTAssertTrue(constructorSignatures.contains([fileType, nullableFileType]))
            XCTAssertTrue(constructorSignatures.contains([fileType, nullableFileType, nullableStringType]))
            for ctor in constructors {
                XCTAssertEqual(symbols.externalLinkName(for: ctor), "kk_throwable_new")
            }

            // Read-only properties have the expected types and runtime links.
            for (name, expectedType, expectedLink) in [
                ("file", fileType, "kk_filesystem_exception_file"),
                ("other", nullableFileType, "kk_filesystem_exception_other"),
                ("reason", nullableStringType, "kk_filesystem_exception_reason"),
            ] {
                let propertySymbol = try XCTUnwrap(
                    symbols.lookup(fqName: fseFQName + [interner.intern(name)]),
                    "Expected kotlin.io.FileSystemException.\(name) property"
                )
                XCTAssertEqual(symbols.propertyType(for: propertySymbol), expectedType)
                XCTAssertEqual(symbols.externalLinkName(for: propertySymbol), expectedLink)
            }
        }
    }
}
