@testable import CompilerCore
import XCTest

/// STDLIB-IO-TYPE-002: Validates that `kotlin.io.FileAlreadyExistsException`
/// is registered as a synthetic class with the expected `Exception` supertype,
/// File-based constructor overloads, and routes to the shared
/// `kk_throwable_new` runtime entry point.
final class FileAlreadyExistsExceptionSyntheticStubTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testFileAlreadyExistsExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "io", "FileAlreadyExistsException"].map { interner.intern($0) }
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

    func testFileAlreadyExistsExceptionResolvesInSource() throws {
        _ = try makeSema(source: """
        import java.io.File
        import kotlin.io.FileAlreadyExistsException

        fun build(file: File): FileAlreadyExistsException = FileAlreadyExistsException(file)

        fun buildWithOther(file: File, other: File?): FileAlreadyExistsException =
            FileAlreadyExistsException(file, other)

        fun buildWithReason(file: File, other: File?, reason: String?): FileAlreadyExistsException =
            FileAlreadyExistsException(file, other, reason)

        fun catchAsException(file: File): String =
            try { throw FileAlreadyExistsException(file) }
            catch (e: Exception) { e.message ?: "caught" }
        """)
    }
}
