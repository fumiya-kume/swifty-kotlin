@testable import CompilerCore
import XCTest

final class IONoSuchFileExceptionTypeTests: XCTestCase {
    func testNoSuchFileExceptionClassSurfaceIsRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let exceptionFQName = ["kotlin", "io", "NoSuchFileException"].map { interner.intern($0) }
        let fileSystemExceptionFQName = ["kotlin", "io", "FileSystemException"].map { interner.intern($0) }

        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        let fileSystemExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fileSystemExceptionFQName))

        XCTAssertEqual(sema.symbols.symbol(exceptionSymbol)?.kind, .class)
        XCTAssertTrue(sema.symbols.directSupertypes(for: exceptionSymbol).contains(fileSystemExceptionSymbol))
    }

    func testNoSuchFileExceptionConstructorsAndPropertiesResolve() throws {
        let ctx = makeContextFromSource("""
        import java.io.File
        import kotlin.io.NoSuchFileException

        fun one(file: File): NoSuchFileException = NoSuchFileException(file)
        fun two(file: File, other: File?): NoSuchFileException =
            NoSuchFileException(file, other)
        fun three(file: File, other: File?, reason: String?): NoSuchFileException =
            NoSuchFileException(file, other, reason)

        fun describe(ex: NoSuchFileException): String? {
            val sameFile: File = ex.file
            val maybeOther: File? = ex.other
            return ex.reason
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected NoSuchFileException surface to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
