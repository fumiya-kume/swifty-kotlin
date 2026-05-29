import XCTest
@testable import Runtime

private nonisolated(unsafe) var kpropertyDispatchStorage: [Int: Int] = [:]

private let kpropertyDirectGetter: @convention(c) (Int) -> Int = { receiver in
    kpropertyDispatchStorage[receiver] ?? runtimeNullSentinelInt
}

private let kpropertyDirectSetter: @convention(c) (Int, Int) -> Int = { receiver, value in
    kpropertyDispatchStorage[receiver] = value
    return receiver
}

final class RuntimeKPropertyDirectDispatchTests: XCTestCase {
    func testKPropertyGetInvokesAttachedGetter() {
        let receiver = 0x4b50
        kpropertyDispatchStorage[receiver] = 42
        let property = kk_kproperty_stub_create(0, 0)
        _ = kk_kproperty_stub_set_getter(
            property,
            unsafeBitCast(kpropertyDirectGetter, to: Int.self),
            receiver
        )

        var thrown = 123
        let value = kk_kproperty_get(property, &thrown)

        XCTAssertEqual(value, 42)
        XCTAssertEqual(thrown, 0)
    }

    func testKPropertySetInvokesAttachedSetter() {
        let receiver = 0x4b51
        kpropertyDispatchStorage[receiver] = 1
        let property = kk_kproperty_stub_create(0, 0)
        _ = kk_kproperty_stub_set_setter(
            property,
            unsafeBitCast(kpropertyDirectSetter, to: Int.self)
        )
        _ = kk_kproperty_stub_set_getter(
            property,
            unsafeBitCast(kpropertyDirectGetter, to: Int.self),
            receiver
        )

        var thrown = 123
        let result = kk_kproperty_set(property, 99, &thrown)

        XCTAssertEqual(result, receiver)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_kproperty_get(property, nil), 99)
    }

    func testKPropertyGetWithoutGetterReportsUnsupportedOperation() {
        let property = kk_kproperty_stub_create(0, 0)

        var thrown = 0
        let value = kk_kproperty_get(property, &thrown)

        XCTAssertEqual(value, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
    }
}
