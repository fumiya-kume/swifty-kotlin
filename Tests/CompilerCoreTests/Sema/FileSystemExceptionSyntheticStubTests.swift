@testable import CompilerCore
import XCTest

/// STDLIB-IO-TYPE-003: Validates that `kotlin.io.FileSystemException`
/// is registered as a synthetic class with the expected `Exception` supertype,
/// File-based constructor overloads, and routes to the shared
/// `kk_throwable_new` runtime entry point.
///
/// Also verifies that `FileAlreadyExistsException` now inherits from
/// `FileSystemException` rather than directly from `Exception`.
final class FileSystemExceptionSyntheticStubTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileSystemExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "io", "FileSystemException"].map { interner.intern($0) }
        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        XCTAssertEqual(sema.symbols.symbol(exceptionSymbol)?.kind, .class)

        // Inherits from kotlin.Exception so try/catch chains observe the parent type.
        let rootExceptionFQName = ["kotlin", "Exception"].map { interner.intern($0) }
        let rootExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: rootExceptionFQName))
        XCTAssertTrue(sema.symbols.directSupertypes(for: exceptionSymbol).contains(rootExceptionSymbol))

        // The synthetic class type round-trips through propertyType for downstream lookups.
        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: exceptionSymbol), exceptionType)

        // Sanity-check the parent package wiring.
        let kotlinIOPkg = ["kotlin", "io"].map { interner.intern($0) }
        let kotlinIOPkgSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinIOPkg))
        XCTAssertEqual(sema.symbols.parentSymbol(for: exceptionSymbol), kotlinIOPkgSymbol)

        // All three constructor overloads land on java.io.File parameters and reuse
        // the shared throwable runtime entry point.
        let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
        let fileSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fileFQName))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableFileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nullable
        )))
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)

        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [[TypeID]] = [
            [fileType],
            [fileType, nullableFileType],
            [fileType, nullableFileType, nullableStringType],
        ]
        for parameterTypes in expected {
            let constructor = try XCTUnwrap(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            XCTAssertEqual(sema.symbols.functionSignature(for: constructor)?.returnType, exceptionType)
            XCTAssertEqual(sema.symbols.externalLinkName(for: constructor), "kk_throwable_new")
        }
    }

    func testFileAlreadyExistsExceptionInheritsFromFileSystemException() throws {
        let (sema, interner) = try makeSema()

        let fileSystemFQName = ["kotlin", "io", "FileSystemException"].map { interner.intern($0) }
        let fileSystemSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fileSystemFQName))

        let fileAlreadyExistsFQName = ["kotlin", "io", "FileAlreadyExistsException"].map { interner.intern($0) }
        let fileAlreadyExistsSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fileAlreadyExistsFQName))

        // FileAlreadyExistsException must now inherit from FileSystemException.
        XCTAssertTrue(
            sema.symbols.directSupertypes(for: fileAlreadyExistsSymbol).contains(fileSystemSymbol),
            "FileAlreadyExistsException should inherit directly from FileSystemException"
        )
    }

    func testFileSystemExceptionResolvesInSource() throws {
        _ = try makeSema(source: """
        import java.io.File
        import kotlin.io.FileSystemException

        fun build(file: File): FileSystemException = FileSystemException(file)

        fun buildWithOther(file: File, other: File?): FileSystemException =
            FileSystemException(file, other)

        fun buildWithReason(file: File, other: File?, reason: String?): FileSystemException =
            FileSystemException(file, other, reason)

        fun catchAsException(file: File): String =
            try { throw FileSystemException(file) }
            catch (e: Exception) { e.message ?: "caught" }
        """)
    }

    func testFileAlreadyExistsExceptionCaughtAsFileSystemException() throws {
        _ = try makeSema(source: """
        import java.io.File
        import kotlin.io.FileAlreadyExistsException
        import kotlin.io.FileSystemException

        fun catchAsFileSystemException(file: File): String =
            try { throw FileAlreadyExistsException(file) }
            catch (e: FileSystemException) { e.message ?: "caught" }
        """)
    }
}
