@testable import Runtime
import XCTest

/// Tests for STDLIB-REFLECT-ABI-001: Unit::class token encoding and runtime KClass handle.
final class RuntimeUnitClassTests: IsolatedRuntimeXCTestCase {

    // MARK: - Helpers

    private func makeRuntimeString(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func runtimeStringValue(_ raw: Int) -> String? {
        guard raw != runtimeNullSentinelInt, raw != 0 else { return nil }
        return extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
    }

    /// The type token for Unit (unitBase = 15, non-nullable).
    private var unitTypeToken: Int {
        // encode(base: 15, nullable: false) = 15 & 0xFF = 15
        return 15
    }

    // MARK: - Token Stability

    func testUnitBaseHasStableValue15() {
        // STDLIB-REFLECT-ABI-001 specifies unitBase == 15.
        let tokenBase = Int64(unitTypeToken) & 0xFF
        XCTAssertEqual(tokenBase, 15, "unitBase must be stable at 15")
    }

    // MARK: - KClass Handle Identity (same handle for repeated calls)

    func testUnitClassProducesSameHandle() {
        let handle1 = kk_kclass_create(unitTypeToken, 0)
        let handle2 = kk_kclass_create(unitTypeToken, 0)
        XCTAssertEqual(handle1, handle2, "Unit::class must return the same interned KClass handle")
    }

    // MARK: - simpleName == "Unit"

    func testUnitClassSimpleNameIsUnit() {
        let kclass = kk_kclass_create(unitTypeToken, 0)
        let nameRaw = kk_kclass_simple_name(kclass)
        XCTAssertEqual(runtimeStringValue(nameRaw), "Unit")
    }

    func testUnitTokenSimpleNameIsUnit() {
        let nameRaw = kk_type_token_simple_name(unitTypeToken, 0)
        XCTAssertEqual(runtimeStringValue(nameRaw), "Unit")
    }

    // MARK: - qualifiedName == "kotlin.Unit"

    func testUnitClassQualifiedNameIsKotlinUnit() {
        let kclass = kk_kclass_create(unitTypeToken, 0)
        let nameRaw = kk_kclass_qualified_name(kclass)
        XCTAssertEqual(runtimeStringValue(nameRaw), "kotlin.Unit")
    }

    func testUnitTokenQualifiedNameIsKotlinUnit() {
        let nameRaw = kk_type_token_qualified_name(unitTypeToken, 0)
        XCTAssertEqual(runtimeStringValue(nameRaw), "kotlin.Unit")
    }

    // MARK: - Unit::class != Any::class

    func testUnitClassDoesNotEqualAnyClass() {
        let unitHandle = kk_kclass_create(unitTypeToken, 0)
        let anyToken = 1  // anyBase == 1
        let anyHandle = kk_kclass_create(anyToken, 0)
        XCTAssertNotEqual(unitHandle, anyHandle, "Unit::class must not equal Any::class")
    }

    // MARK: - isInstance(Unit) — kk_op_is with unitBase

    func testIsInstanceUnitValueIsTrue() {
        // The Unit runtime value is the integer 0.
        let unitValue = 0
        let result = kk_op_is(unitValue, unitTypeToken)
        XCTAssertEqual(result, 1, "kk_op_is should return 1 for the Unit singleton value")
    }

    func testIsInstanceNonUnitValueIsFalse() {
        // A non-zero value is not Unit.
        let nonUnitValue = 42
        let result = kk_op_is(nonUnitValue, unitTypeToken)
        XCTAssertEqual(result, 0, "kk_op_is should return 0 for a non-Unit value")
    }

    func testIsInstanceNullIsNotUnit() {
        let result = kk_op_is(runtimeNullSentinelInt, unitTypeToken)
        XCTAssertEqual(result, 0, "null is not an instance of Unit")
    }
}
