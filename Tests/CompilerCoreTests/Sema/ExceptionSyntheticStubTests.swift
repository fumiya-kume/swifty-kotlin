@testable import CompilerCore
import XCTest

final class ExceptionSyntheticStubTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testNoWhenBranchMatchedExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let noWhenFQName = ["kotlin", "NoWhenBranchMatchedException"].map { interner.intern($0) }
        let noWhenSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: noWhenFQName))
        XCTAssertEqual(sema.symbols.symbol(noWhenSymbol)?.kind, .class)

        let runtimeExceptionFQName = ["kotlin", "RuntimeException"].map { interner.intern($0) }
        let runtimeExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: runtimeExceptionFQName))
        XCTAssertTrue(sema.symbols.directSupertypes(for: noWhenSymbol).contains(runtimeExceptionSymbol))

        let noWhenType = sema.types.make(.classType(ClassType(
            classSymbol: noWhenSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: noWhenSymbol), noWhenType)

        let throwableFQName = ["kotlin", "Throwable"].map { interner.intern($0) }
        let throwableSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: throwableFQName))
        let nullableThrowableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nullable
        )))
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)

        let constructorFQName = noWhenFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "kk_no_when_branch_matched_exception_new"),
            ([nullableStringType], "kk_no_when_branch_matched_exception_new_message"),
            ([nullableStringType, nullableThrowableType], "kk_no_when_branch_matched_exception_new_message_cause"),
            ([nullableThrowableType], "kk_no_when_branch_matched_exception_new_cause"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try XCTUnwrap(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            XCTAssertEqual(sema.symbols.functionSignature(for: constructor)?.returnType, noWhenType)
            XCTAssertEqual(sema.symbols.externalLinkName(for: constructor), externalLinkName)
        }
    }

    func testNoWhenBranchMatchedExceptionResolvesInSource() throws {
        _ = try makeSema(source: """
        fun noArg(): RuntimeException = NoWhenBranchMatchedException()
        fun message(message: String?): RuntimeException = NoWhenBranchMatchedException(message)
        fun messageCause(message: String?, cause: Throwable?): RuntimeException = NoWhenBranchMatchedException(message, cause)
        fun cause(cause: Throwable?): RuntimeException = NoWhenBranchMatchedException(cause)
        """)
    }

    func testCharacterCodingExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "text", "CharacterCodingException"].map { interner.intern($0) }
        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        XCTAssertEqual(sema.symbols.symbol(exceptionSymbol)?.kind, .class)

        let rootExceptionFQName = ["kotlin", "Exception"].map { interner.intern($0) }
        let rootExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: rootExceptionFQName))
        XCTAssertTrue(sema.symbols.directSupertypes(for: exceptionSymbol).contains(rootExceptionSymbol))

        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: exceptionSymbol), exceptionType)

        let nullableStringType = sema.types.makeNullable(sema.types.stringType)
        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "kk_throwable_new"),
            ([nullableStringType], "kk_throwable_new"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try XCTUnwrap(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            XCTAssertEqual(sema.symbols.functionSignature(for: constructor)?.returnType, exceptionType)
            XCTAssertEqual(sema.symbols.externalLinkName(for: constructor), externalLinkName)
        }
    }

    func testCharacterCodingExceptionResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlin.text.CharacterCodingException

        fun noArg(): Exception = CharacterCodingException()
        fun message(message: String?): Exception = CharacterCodingException(message)
        fun catchCharacterCoding(): String =
            try { throw CharacterCodingException("bad input") }
            catch (e: CharacterCodingException) { e.message ?: "caught" }
        """)
    }

    func testNoSuchFileExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "io", "NoSuchFileException"].map { interner.intern($0) }
        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        XCTAssertEqual(sema.symbols.symbol(exceptionSymbol)?.kind, .class)

        let rootExceptionFQName = ["kotlin", "Exception"].map { interner.intern($0) }
        let rootExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: rootExceptionFQName))
        XCTAssertTrue(sema.symbols.directSupertypes(for: exceptionSymbol).contains(rootExceptionSymbol))

        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: exceptionSymbol), exceptionType)

        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "kk_throwable_new"),
            ([sema.types.stringType], "kk_throwable_new"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try XCTUnwrap(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            XCTAssertEqual(sema.symbols.functionSignature(for: constructor)?.returnType, exceptionType)
            XCTAssertEqual(sema.symbols.externalLinkName(for: constructor), externalLinkName)
        }
    }

    func testNoSuchFileExceptionResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlin.io.NoSuchFileException

        fun noArg(): Exception = NoSuchFileException()
        fun file(path: String): Exception = NoSuchFileException(path)
        fun catchNoSuchFile(): String =
            try { throw NoSuchFileException("missing.txt") }
            catch (e: NoSuchFileException) { e.message ?: "caught" }
        """)
    }

    func testConcurrentModificationExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "ConcurrentModificationException"].map { interner.intern($0) }
        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        XCTAssertEqual(sema.symbols.symbol(exceptionSymbol)?.kind, .class)

        let runtimeExceptionFQName = ["kotlin", "RuntimeException"].map { interner.intern($0) }
        let runtimeExceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: runtimeExceptionFQName))
        XCTAssertTrue(sema.symbols.directSupertypes(for: exceptionSymbol).contains(runtimeExceptionSymbol))

        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: exceptionSymbol), exceptionType)

        let throwableFQName = ["kotlin", "Throwable"].map { interner.intern($0) }
        let throwableSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: throwableFQName))
        let nullableThrowableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nullable
        )))
        let nullableStringType = sema.types.makeNullable(sema.types.stringType)

        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "kk_concurrent_modification_exception_new"),
            ([nullableStringType], "kk_concurrent_modification_exception_new_message"),
            ([nullableStringType, nullableThrowableType], "kk_concurrent_modification_exception_new_message_cause"),
            ([nullableThrowableType], "kk_concurrent_modification_exception_new_cause"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try XCTUnwrap(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            XCTAssertEqual(sema.symbols.functionSignature(for: constructor)?.returnType, exceptionType)
            XCTAssertEqual(sema.symbols.externalLinkName(for: constructor), externalLinkName)
        }
    }

    func testConcurrentModificationExceptionResolvesInSource() throws {
        _ = try makeSema(source: """
        fun noArg(): RuntimeException = ConcurrentModificationException()
        fun message(message: String?): RuntimeException = ConcurrentModificationException(message)
        fun messageCause(message: String?, cause: Throwable?): RuntimeException = ConcurrentModificationException(message, cause)
        fun cause(cause: Throwable?): RuntimeException = ConcurrentModificationException(cause)
        """)
    }

    func testArrayIndexOutOfBoundsExceptionSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let exceptionFQName = ["kotlin", "ArrayIndexOutOfBoundsException"].map { interner.intern($0) }
        let exceptionSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: exceptionFQName))
        XCTAssertEqual(sema.symbols.symbol(exceptionSymbol)?.kind, .class)

        let indexOutOfBoundsFQName = ["kotlin", "IndexOutOfBoundsException"].map { interner.intern($0) }
        let indexOutOfBoundsSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: indexOutOfBoundsFQName))
        XCTAssertTrue(sema.symbols.directSupertypes(for: exceptionSymbol).contains(indexOutOfBoundsSymbol))

        let exceptionType = sema.types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: exceptionSymbol), exceptionType)

        let nullableStringType = sema.types.makeNullable(sema.types.stringType)
        let constructorFQName = exceptionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let expected: [([TypeID], String)] = [
            ([], "kk_array_index_out_of_bounds_exception_new"),
            ([nullableStringType], "kk_array_index_out_of_bounds_exception_new_message"),
        ]
        for (parameterTypes, externalLinkName) in expected {
            let constructor = try XCTUnwrap(constructors.first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameterTypes
            })
            XCTAssertEqual(sema.symbols.functionSignature(for: constructor)?.returnType, exceptionType)
            XCTAssertEqual(sema.symbols.externalLinkName(for: constructor), externalLinkName)
        }
    }

    func testArrayIndexOutOfBoundsExceptionResolvesInSource() throws {
        _ = try makeSema(source: """
        fun noArg(): IndexOutOfBoundsException = ArrayIndexOutOfBoundsException()
        fun message(message: String?): IndexOutOfBoundsException = ArrayIndexOutOfBoundsException(message)
        """)
    }
}
