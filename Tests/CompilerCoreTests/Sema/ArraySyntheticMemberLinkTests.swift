@testable import CompilerCore
import Foundation
import XCTest

final class ArraySyntheticMemberLinkTests: XCTestCase {
    func testArrayBinarySearchComparatorOverloadUsesRuntimeExternalLink() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let symbolID = try XCTUnwrap(
                sema.symbols.lookupAll(
                    fqName: [
                        ctx.interner.intern("kotlin"),
                        ctx.interner.intern("Array"),
                        ctx.interner.intern("binarySearch$compare"),
                    ]
                ).first(where: { sema.symbols.externalLinkName(for: $0) == "kk_array_binarySearch_compare" }),
                "Expected synthetic Array member binarySearch to be registered"
            )
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbolID))
            XCTAssertEqual(signature.parameterTypes.count, 4)
            XCTAssertEqual(signature.valueParameterHasDefaultValues, [false, false, true, true])
            XCTAssertEqual(signature.valueParameterIsVararg, [false, false, false, false])

            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of: receiverType),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
            else {
                return XCTFail("Expected Array receiver type")
            }
            XCTAssertEqual(ctx.interner.resolve(receiverSymbol.name), "Array")
            XCTAssertEqual(receiverClass.args.count, 1)

            guard case let .classType(comparatorType) = sema.types.kind(of: signature.parameterTypes[1]),
                  let comparatorSymbol = sema.symbols.symbol(comparatorType.classSymbol)
            else {
                return XCTFail("Expected Comparator parameter type")
            }
            XCTAssertEqual(ctx.interner.resolve(comparatorSymbol.name), "Comparator")
            XCTAssertEqual(comparatorType.args.count, 1)
        }
    }
}
