@testable import CompilerCore
import XCTest

final class JsExceptionSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsExceptionClassIsRegisteredAsThrowableSubtype() throws {
        let (sema, interner) = try makeSema()

        let kotlinJsFQName = ["kotlin", "js"].map { interner.intern($0) }
        let kotlinJsPackage = try XCTUnwrap(sema.symbols.lookup(fqName: kotlinJsFQName))

        let jsExceptionFQName = kotlinJsFQName + [interner.intern("JsException")]
        let jsExceptionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: jsExceptionFQName),
            "Expected kotlin.js.JsException to be registered"
        )
        let jsExceptionInfo = try XCTUnwrap(sema.symbols.symbol(jsExceptionSymbol))
        XCTAssertEqual(jsExceptionInfo.kind, .class)
        XCTAssertEqual(jsExceptionInfo.visibility, .public)
        XCTAssertTrue(jsExceptionInfo.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: jsExceptionSymbol), kotlinJsPackage)

        let throwableFQName = [interner.intern("kotlin"), interner.intern("Throwable")]
        let throwableSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: throwableFQName),
            "Expected kotlin.Throwable to be registered"
        )
        XCTAssertEqual(sema.symbols.directSupertypes(for: jsExceptionSymbol), [throwableSymbol])
        XCTAssertEqual(sema.types.directNominalSupertypes(for: jsExceptionSymbol), [throwableSymbol])

        let jsExceptionType = sema.types.make(.classType(ClassType(
            classSymbol: jsExceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.propertyType(for: jsExceptionSymbol), jsExceptionType)
    }
}
