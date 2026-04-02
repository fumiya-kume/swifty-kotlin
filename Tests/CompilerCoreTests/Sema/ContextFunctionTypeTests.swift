@testable import CompilerCore
import XCTest

final class ContextFunctionTypeTests: XCTestCase {
    func testFunctionSubtypingContextReceiverCountMismatch() {
        let ts = TypeSystem()
        let intType = ts.intType
        let left = ts.make(.functionType(FunctionType(
            contextReceivers: [intType],
            params: [],
            returnType: intType
        )))
        let right = ts.make(.functionType(FunctionType(
            contextReceivers: [intType, intType],
            params: [],
            returnType: intType
        )))

        XCTAssertFalse(ts.isSubtype(left, right))
        XCTAssertFalse(ts.isSubtype(right, left))
    }

    func testFunctionSubtypingContextReceiversAreOrderedAndContravariant() {
        let ts = TypeSystem()
        let intType = ts.intType
        let anyType = ts.anyType
        let left = ts.make(.functionType(FunctionType(
            contextReceivers: [anyType, intType],
            params: [],
            returnType: intType
        )))
        let right = ts.make(.functionType(FunctionType(
            contextReceivers: [intType, intType],
            params: [],
            returnType: intType
        )))
        let reordered = ts.make(.functionType(FunctionType(
            contextReceivers: [intType, anyType],
            params: [],
            returnType: intType
        )))

        XCTAssertTrue(ts.isSubtype(left, right))
        XCTAssertFalse(ts.isSubtype(right, left))
        XCTAssertFalse(ts.isSubtype(left, reordered))
    }

    func testWithNullabilityPreservesContextReceivers() {
        let ts = TypeSystem()
        let intType = ts.intType
        let stringType = ts.stringType
        let fn = ts.make(.functionType(FunctionType(
            contextReceivers: [stringType],
            params: [intType],
            returnType: intType
        )))
        let nullable = ts.withNullability(.nullable, for: fn)

        guard case let .functionType(result) = ts.kind(of: nullable) else {
            return XCTFail("Expected function type")
        }
        XCTAssertEqual(result.contextReceivers, [stringType])
        XCTAssertEqual(result.params, [intType])
        XCTAssertEqual(result.returnType, intType)
        XCTAssertEqual(result.nullability, .nullable)
    }
}
