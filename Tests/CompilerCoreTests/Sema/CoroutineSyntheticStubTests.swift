@testable import CompilerCore
import Foundation
import XCTest

final class CoroutineSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testEmptyCoroutineContextIsRegisteredAsSyntheticObject() throws {
        let (sema, interner) = try makeSema()

        let coroutineContextFQName = ["kotlin", "coroutines", "CoroutineContext"].map { interner.intern($0) }
        let coroutineContextSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: coroutineContextFQName),
            "Expected kotlin.coroutines.CoroutineContext to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(coroutineContextSymbol)?.kind, .interface)

        let emptyCoroutineContextFQName = ["kotlin", "coroutines", "EmptyCoroutineContext"].map { interner.intern($0) }
        let emptyCoroutineContextSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: emptyCoroutineContextFQName),
            "Expected kotlin.coroutines.EmptyCoroutineContext to be registered"
        )
        let emptyCoroutineContextInfo = try XCTUnwrap(sema.symbols.symbol(emptyCoroutineContextSymbol))
        XCTAssertEqual(emptyCoroutineContextInfo.kind, .object)
        XCTAssertTrue(emptyCoroutineContextInfo.flags.contains(.synthetic))

        let expectedEmptyCoroutineContextType = sema.types.make(.classType(ClassType(
            classSymbol: emptyCoroutineContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(
            sema.symbols.propertyType(for: emptyCoroutineContextSymbol),
            expectedEmptyCoroutineContextType
        )
        XCTAssertEqual(
            sema.symbols.directSupertypes(for: emptyCoroutineContextSymbol),
            [coroutineContextSymbol]
        )
    }

    func testEmptyCoroutineContextResolvesThroughWithContext() throws {
        let source = """
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlinx.coroutines.withContext

        suspend fun probe() {
            withContext(EmptyCoroutineContext) { 42 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty)
        }
    }
}
