@testable import CompilerCore
import Foundation
import XCTest

final class SuspendFunctionSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testSuspendFunctionMarkerInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fqName = ["kotlin", "coroutines", "SuspendFunction"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.coroutines.SuspendFunction to be registered"
        )
        XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .interface)
        XCTAssertTrue(sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == true)

        let typeParameters = sema.types.nominalTypeParameterSymbols(for: symbol)
        XCTAssertEqual(typeParameters.count, 1)
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: symbol), [.out])

        let propertyType = try XCTUnwrap(sema.symbols.propertyType(for: symbol))
        guard case let .classType(classType) = sema.types.kind(of: propertyType) else {
            return XCTFail("Expected SuspendFunction property type to be a class type")
        }
        XCTAssertEqual(classType.classSymbol, symbol)
        XCTAssertEqual(classType.args.count, 1)
        guard case let .out(returnType) = classType.args[0],
              case let .typeParam(typeParam) = sema.types.kind(of: returnType)
        else {
            return XCTFail("Expected SuspendFunction<R> to expose covariant R")
        }
        XCTAssertEqual(typeParam.symbol, typeParameters[0])
    }
}
