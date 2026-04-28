@testable import CompilerCore
import XCTest

final class ThrowableSuppressedExceptionsSyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected Throwable surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testSuppressedExceptionsRootExtensionPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinPackage = ["kotlin"].map { interner.intern($0) }
        let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

        let throwableSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: kotlinPackage + [interner.intern("Throwable")]
        ))
        let listSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("List")]
        ))
        let throwableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedListType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(throwableType)],
            nullability: .nonNull
        )))

        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(
                fqName: kotlinPackage + [interner.intern("suppressedExceptions")]
            ).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) == throwableType
            },
            "Expected kotlin.Throwable.suppressedExceptions root extension property"
        )
        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))

        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), expectedListType)
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_throwable_suppressedExceptions")
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_throwable_suppressedExceptions")
        XCTAssertEqual(sema.symbols.functionSignature(for: getterSymbol)?.receiverType, throwableType)
        XCTAssertEqual(sema.symbols.functionSignature(for: getterSymbol)?.returnType, expectedListType)
    }

    func testSuppressedExceptionsCanBeAssignedToListOfThrowable() throws {
        let source = """
        fun sample(e: Throwable) {
            val suppressed: List<Throwable> = e.suppressedExceptions
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let sampleSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: [interner.intern("sample")]
        ))

        XCTAssertNotNil(sema.symbols.functionSignature(for: sampleSymbol))
    }
}
