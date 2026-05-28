@testable import CompilerCore
import XCTest

/// Surface tests for `kotlin.io.AccessDeniedException` (STDLIB-IO-TYPE-001).
///
/// Verifies that the synthetic Sema stub registers:
/// - `kotlin.io.AccessDeniedException` as a class
/// - its `FileSystemException` parent (and indirect `Exception` ancestor)
/// - constructor overloads `(File)`, `(File, File?)`, `(File, File?, String?)`
/// - `file`, `other`, `reason` member properties
/// - source-level resolution of the type in Kotlin code
final class IOAccessDeniedExceptionTypeTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testAccessDeniedExceptionClassSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "io", "AccessDeniedException"].map { interner.intern($0) }
        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        XCTAssertEqual(sema.symbols.symbol(exceptionSymbol)?.kind, .class)

        let fileSystemExceptionFQName = ["kotlin", "io", "FileSystemException"].map { interner.intern($0) }
        let fileSystemExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fileSystemExceptionFQName))
        XCTAssertTrue(
            sema.symbols.directSupertypes(for: exceptionSymbol).contains(fileSystemExceptionSymbol),
            "AccessDeniedException should directly inherit FileSystemException"
        )

        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: exceptionSymbol), exceptionType)
    }

    func testFileSystemExceptionInheritsFromException() throws {
        let (sema, interner) = try makeSema()

        let fileSystemExceptionFQName = ["kotlin", "io", "FileSystemException"].map { interner.intern($0) }
        let fileSystemExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fileSystemExceptionFQName))
        XCTAssertEqual(sema.symbols.symbol(fileSystemExceptionSymbol)?.kind, .class)

        let exceptionFQName = ["kotlin", "Exception"].map { interner.intern($0) }
        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        XCTAssertTrue(
            sema.symbols.directSupertypes(for: fileSystemExceptionSymbol).contains(exceptionSymbol),
            "FileSystemException should inherit from Exception in the synthetic hierarchy"
        )
    }

    func testAccessDeniedExceptionConstructorOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "io", "AccessDeniedException"].map { interner.intern($0) }
        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))

        let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
        let fileSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fileFQName))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nonNull
        )))
        let nullableFileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nullable
        )))
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)

        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        XCTAssertGreaterThanOrEqual(constructors.count, 3)

        let expected: [([TypeID], String)] = [
            ([fileType], "kk_access_denied_exception_new_file"),
            ([fileType, nullableFileType], "kk_access_denied_exception_new_file_other"),
            (
                [fileType, nullableFileType, nullableStringType],
                "kk_access_denied_exception_new_file_other_reason"
            ),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try XCTUnwrap(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            }, "Constructor with parameters \(parameterTypes) not found")
            XCTAssertEqual(
                sema.symbols.functionSignature(for: constructor)?.returnType,
                exceptionType
            )
            XCTAssertEqual(sema.symbols.externalLinkName(for: constructor), externalLinkName)
        }
    }

    func testAccessDeniedExceptionMemberPropertiesAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "io", "AccessDeniedException"].map { interner.intern($0) }
        _ = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))

        let fileFQName = ["java", "io", "File"].map { interner.intern($0) }
        let fileSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fileFQName))
        let fileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nonNull
        )))
        let nullableFileType = sema.types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nullable
        )))
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)

        let expected: [(propertyName: String, propertyType: TypeID, link: String)] = [
            ("file", fileType, "kk_access_denied_exception_file"),
            ("other", nullableFileType, "kk_access_denied_exception_other"),
            ("reason", nullableStringType, "kk_access_denied_exception_reason"),
        ]
        for (propertyName, propertyType, externalLink) in expected {
            let propFQName = exceptionFQName + [interner.intern(propertyName)]
            let propSymbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: propFQName).first {
                    sema.symbols.symbol($0)?.kind == .property
                },
                "Property \(propertyName) not registered on AccessDeniedException"
            )
            XCTAssertEqual(sema.symbols.propertyType(for: propSymbol), propertyType)
            XCTAssertEqual(sema.symbols.externalLinkName(for: propSymbol), externalLink)
        }
    }

    func testAccessDeniedExceptionResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlin.io.AccessDeniedException
        import java.io.File

        fun makeWithFile(file: File): AccessDeniedException = AccessDeniedException(file)
        fun makeWithOther(file: File, other: File?): AccessDeniedException = AccessDeniedException(file, other)
        fun makeWithReason(file: File, other: File?, reason: String?): AccessDeniedException =
            AccessDeniedException(file, other, reason)

        fun describe(e: AccessDeniedException): String {
            val f: File = e.file
            val o: File? = e.other
            val r: String? = e.reason
            return f.path + (o?.path ?: "") + (r ?: "")
        }
        """)
    }
}
