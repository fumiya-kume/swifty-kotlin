@testable import CompilerCore
import XCTest

final class IOFileAlreadyExistsExceptionTypeTests: XCTestCase {
    func testFileAlreadyExistsExceptionClassSurfaceIsRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let exceptionFQName = ["kotlin", "io", "FileAlreadyExistsException"].map { interner.intern($0) }
        let fileSystemExceptionFQName = ["kotlin", "io", "FileSystemException"].map { interner.intern($0) }

        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        let fileSystemExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fileSystemExceptionFQName))

        XCTAssertEqual(sema.symbols.symbol(exceptionSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.directSupertypes(for: exceptionSymbol).contains(fileSystemExceptionSymbol))
    }

    func testFileAlreadyExistsExceptionConstructorsAndPropertiesResolve() throws {
        let ctx = makeContextFromSource("""
        import java.io.File
        import kotlin.io.FileAlreadyExistsException

        fun one(file: File): FileAlreadyExistsException = FileAlreadyExistsException(file)
        fun two(file: File, other: File?): FileAlreadyExistsException =
            FileAlreadyExistsException(file, other)
        fun three(file: File, other: File?, reason: String?): FileAlreadyExistsException =
            FileAlreadyExistsException(file, other, reason)

        fun describe(ex: FileAlreadyExistsException): String? {
            val sameFile: File = ex.file
            val maybeOther: File? = ex.other
            return ex.reason
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected FileAlreadyExistsException surface to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
