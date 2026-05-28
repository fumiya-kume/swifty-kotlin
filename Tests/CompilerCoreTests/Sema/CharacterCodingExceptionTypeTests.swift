@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-TYPE-002: Validates that `kotlin.text.CharacterCodingException`
/// is registered as a synthetic class in the `kotlin.text` package with
/// `Exception` as a direct supertype and exposes the two stdlib constructors
/// (`()` and `(message: String?)`). See
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticExceptionStubs.swift`
/// for the registration site and the constructors are routed to the runtime
/// link `kk_throwable_new`.
final class CharacterCodingExceptionTypeTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    // MARK: - Symbol surface

    func testCharacterCodingExceptionIsRegisteredAsClassInKotlinTextPackage() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "text", "CharacterCodingException"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.text.CharacterCodingException to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .class)
    }

    func testCharacterCodingExceptionHasExceptionDirectSupertype() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "text", "CharacterCodingException"].map { interner.intern($0) }
        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))

        let rootExceptionFQName = ["kotlin", "Exception"].map { interner.intern($0) }
        let rootExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: rootExceptionFQName))

        XCTAssertTrue(
            sema.symbols.directSupertypes(for: exceptionSymbol).contains(rootExceptionSymbol),
            "CharacterCodingException should directly inherit from kotlin.Exception"
        )
    }

    func testCharacterCodingExceptionIsAssignableToExceptionAndThrowable() throws {
        let (sema, interner) = try makeSema()

        let characterCodingFQName = ["kotlin", "text", "CharacterCodingException"].map { interner.intern($0) }
        let characterCodingSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: characterCodingFQName))
        let characterCodingType = sema.types.make(.classType(ClassType(
            classSymbol: characterCodingSymbol,
            args: [],
            nullability: .nonNull
        )))

        let exceptionFQName = ["kotlin", "Exception"].map { interner.intern($0) }
        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))

        let throwableFQName = ["kotlin", "Throwable"].map { interner.intern($0) }
        let throwableSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: throwableFQName))
        let throwableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))

        XCTAssertTrue(
            sema.types.isSubtype(characterCodingType, exceptionType),
            "CharacterCodingException should be a subtype of kotlin.Exception"
        )
        XCTAssertTrue(
            sema.types.isSubtype(characterCodingType, throwableType),
            "CharacterCodingException should be a (transitive) subtype of kotlin.Throwable"
        )
    }

    // MARK: - Constructors

    func testCharacterCodingExceptionExposesNoArgAndMessageConstructors() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "text", "CharacterCodingException"].map { interner.intern($0) }
        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))

        let nullableStringType = sema.types.makeNullable(sema.types.stringType)
        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }

        XCTAssertEqual(
            constructors.count,
            2,
            "CharacterCodingException should expose exactly the no-arg and single-message constructors"
        )

        let expected: [([TypeID], String)] = [
            ([], "kk_throwable_new"),
            ([nullableStringType], "kk_throwable_new"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try XCTUnwrap(
                constructors.first {
                    sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
                },
                "Missing CharacterCodingException constructor with parameters \(parameterTypes)"
            )
            XCTAssertEqual(
                sema.symbols.functionSignature(for: constructor)?.returnType,
                exceptionType,
                "Constructor should return CharacterCodingException"
            )
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: constructor),
                externalLinkName,
                "Constructor with parameters \(parameterTypes) should bind to \(externalLinkName)"
            )
        }
    }

    // MARK: - Source resolution

    func testCharacterCodingExceptionTypeChecksThroughImport() throws {
        let ctx = makeContextFromSource("""
        import kotlin.text.CharacterCodingException

        fun throwImported(): Nothing = throw CharacterCodingException()
        fun throwImportedWithMessage(): Nothing = throw CharacterCodingException("bad input")

        fun catchAsCharacterCoding(): String =
            try { throw CharacterCodingException("decode failed") }
            catch (e: CharacterCodingException) { e.message ?: "none" }

        fun catchAsException(): String =
            try { throw CharacterCodingException("encode failed") }
            catch (e: Exception) { e.message ?: "none" }

        fun catchAsThrowable(): String =
            try { throw CharacterCodingException("io failed") }
            catch (t: Throwable) { t.message ?: "none" }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected CharacterCodingException to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testCharacterCodingExceptionAcceptsNullMessageArgument() throws {
        let ctx = makeContextFromSource("""
        import kotlin.text.CharacterCodingException

        fun nullable(message: String?): Exception = CharacterCodingException(message)
        fun explicitNull(): Exception = CharacterCodingException(null)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected CharacterCodingException(message: String?) to accept nullable arguments, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
