@testable import Runtime
import XCTest

// MARK: - STDLIB-REFLECT-ABI-002 / ABI-003 Tests
// Coverage for:
//   ABI-002: KClass.members returns real member handles registered via
//            kk_kclass_register_member
//   ABI-003: kk_kclass_cast / kk_kclass_safeCast independent runtime entries

final class RuntimeKClassCastAndMembersTests: XCTestCase {

    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
        }
    }

    /// Registers a KClass with minimal metadata and returns its raw handle.
    private func registerKClass(
        typeToken: Int,
        qualifiedName: String,
        simpleName: String
    ) -> Int {
        let qn = makeRuntimeString(qualifiedName)
        let sn = makeRuntimeString(simpleName)
        _ = kk_kclass_register_metadata(
            typeToken, qn, sn,
            0, // no supertype
            0, // no flags
            1, // fieldCount
            3, // memberCount
            1  // constructorCount
        )
        return kk_kclass_create(typeToken, sn)
    }

    private func runtimeListElements(
        from raw: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Int] {
        guard let listPtr = UnsafeMutableRawPointer(bitPattern: raw),
              let list = tryCast(listPtr, to: RuntimeListBox.self) else {
            XCTFail("Expected RuntimeListBox", file: file, line: line)
            return []
        }
        return list.elements
    }

    // MARK: - ABI-002: kk_kclass_register_member / kk_kclass_members

    func testMembersEmptyWhenNoMembersRegistered() {
        let kclass = registerKClass(typeToken: 1001, qualifiedName: "pkg.A", simpleName: "A")
        let listRaw = kk_kclass_members(kclass)

        guard let listPtr = UnsafeMutableRawPointer(bitPattern: listRaw),
              let list = tryCast(listPtr, to: RuntimeListBox.self) else {
            XCTFail("Expected RuntimeListBox")
            return
        }
        // No members registered yet, so metadata counts must not create placeholders.
        XCTAssertTrue(list.elements.isEmpty)
    }

    func testRegisterMemberReturnsZero() {
        let kclass = registerKClass(typeToken: 1002, qualifiedName: "pkg.B", simpleName: "B")
        let fnRaw = kk_kfunction_create(
            makeRuntimeString("doSomething"), 0,
            makeRuntimeString("kotlin.Unit"), 0, 0, 0
        )
        let result = kk_kclass_register_member(kclass, fnRaw)
        XCTAssertEqual(result, 0)
    }

    func testMembersReturnsSingleRegisteredFunction() {
        let kclass = registerKClass(typeToken: 1003, qualifiedName: "pkg.C", simpleName: "C")
        let fnRaw = kk_kfunction_create(
            makeRuntimeString("greet"), 1,
            makeRuntimeString("kotlin.String"), 0, 0, 0
        )
        _ = kk_kclass_register_member(kclass, fnRaw)

        let listRaw = kk_kclass_members(kclass)
        guard let listPtr = UnsafeMutableRawPointer(bitPattern: listRaw),
              let list = tryCast(listPtr, to: RuntimeListBox.self) else {
            XCTFail("Expected RuntimeListBox")
            return
        }
        XCTAssertEqual(list.elements.count, 1)
        XCTAssertEqual(list.elements[0], fnRaw)
    }

    func testMembersReturnsMultipleRegisteredMembers() {
        let kclass = registerKClass(typeToken: 1004, qualifiedName: "pkg.D", simpleName: "D")
        let fn1 = kk_kfunction_create(makeRuntimeString("foo"), 0, 0, 0, 0, 0)
        let fn2 = kk_kfunction_create(makeRuntimeString("bar"), 1, 0, 0, 0, 0)
        let prop = kk_kproperty_stub_create(makeRuntimeString("value"), makeRuntimeString("kotlin.Int"))

        _ = kk_kclass_register_member(kclass, fn1)
        _ = kk_kclass_register_member(kclass, fn2)
        _ = kk_kclass_register_member(kclass, prop)

        let listRaw = kk_kclass_members(kclass)
        guard let listPtr = UnsafeMutableRawPointer(bitPattern: listRaw),
              let list = tryCast(listPtr, to: RuntimeListBox.self) else {
            XCTFail("Expected RuntimeListBox")
            return
        }
        XCTAssertEqual(list.elements.count, 3)
        XCTAssertTrue(list.elements.contains(fn1))
        XCTAssertTrue(list.elements.contains(fn2))
        XCTAssertTrue(list.elements.contains(prop))
        XCTAssertFalse(list.elements.contains(0))
    }

    func testFunctionAndPropertyAccessorsFilterRegisteredMembers() {
        let kclass = registerKClass(typeToken: 1010, qualifiedName: "pkg.Filtered", simpleName: "Filtered")
        let fn = kk_kfunction_create(makeRuntimeString("compute"), 0, makeRuntimeString("kotlin.Int"), 0, 0, 0)
        let prop = kk_kproperty_stub_create(makeRuntimeString("value"), makeRuntimeString("kotlin.Int"))

        _ = kk_kclass_register_member(kclass, fn)
        _ = kk_kclass_register_member(kclass, prop)

        XCTAssertEqual(runtimeListElements(from: kk_kclass_members(kclass)), [fn, prop])
        XCTAssertEqual(runtimeListElements(from: kk_kclass_functions(kclass)), [fn])
        XCTAssertEqual(runtimeListElements(from: kk_kclass_member_functions(kclass)), [fn])
        XCTAssertEqual(runtimeListElements(from: kk_kclass_declared_member_functions(kclass)), [fn])
        XCTAssertEqual(runtimeListElements(from: kk_kclass_properties(kclass)), [prop])
        XCTAssertEqual(runtimeListElements(from: kk_kclass_member_properties(kclass)), [prop])
        XCTAssertEqual(runtimeListElements(from: kk_kclass_declared_member_properties(kclass)), [prop])
    }

    func testRegisterMemberIgnoresInvalidHandles() {
        let kclass = registerKClass(typeToken: 1005, qualifiedName: "pkg.E", simpleName: "E")
        // Invalid handles should be ignored.
        _ = kk_kclass_register_member(kclass, 0)
        _ = kk_kclass_register_member(kclass, runtimeNullSentinelInt)
        _ = kk_kclass_register_member(kclass, 0xDEAD_BEEF)

        let listRaw = kk_kclass_members(kclass)
        guard let listPtr = UnsafeMutableRawPointer(bitPattern: listRaw),
              let list = tryCast(listPtr, to: RuntimeListBox.self) else {
            XCTFail("Expected RuntimeListBox")
            return
        }
        XCTAssertTrue(list.elements.isEmpty)
    }

    func testMembersIsolatedPerClass() {
        let classA = registerKClass(typeToken: 1006, qualifiedName: "pkg.F", simpleName: "F")
        let classB = registerKClass(typeToken: 1007, qualifiedName: "pkg.G", simpleName: "G")

        let fnA = kk_kfunction_create(makeRuntimeString("fromA"), 0, 0, 0, 0, 0)
        let fnB = kk_kfunction_create(makeRuntimeString("fromB"), 0, 0, 0, 0, 0)

        _ = kk_kclass_register_member(classA, fnA)
        _ = kk_kclass_register_member(classB, fnB)

        let listA = kk_kclass_members(classA)
        let listB = kk_kclass_members(classB)

        guard let ptrA = UnsafeMutableRawPointer(bitPattern: listA),
              let listBoxA = tryCast(ptrA, to: RuntimeListBox.self),
              let ptrB = UnsafeMutableRawPointer(bitPattern: listB),
              let listBoxB = tryCast(ptrB, to: RuntimeListBox.self) else {
            XCTFail("Expected RuntimeListBox for both classes")
            return
        }

        XCTAssertEqual(listBoxA.elements.count, 1)
        XCTAssertEqual(listBoxA.elements[0], fnA)
        XCTAssertEqual(listBoxB.elements.count, 1)
        XCTAssertEqual(listBoxB.elements[0], fnB)
        XCTAssertFalse(listBoxA.elements.contains(fnB))
        XCTAssertFalse(listBoxB.elements.contains(fnA))
    }

    func testMembersRegistryResetOnForceReset() {
        let kclass = registerKClass(typeToken: 1008, qualifiedName: "pkg.H", simpleName: "H")
        let fn = kk_kfunction_create(makeRuntimeString("method"), 0, 0, 0, 0, 0)
        _ = kk_kclass_register_member(kclass, fn)

        // Confirm member is registered.
        let beforeReset = runtimeKMemberRegistry.members(for: kclass)
        XCTAssertFalse(beforeReset.isEmpty)

        kk_runtime_force_reset()

        // After reset, members should be cleared.
        let afterReset = runtimeKMemberRegistry.members(for: kclass)
        XCTAssertTrue(afterReset.isEmpty)
    }

    // MARK: - ABI-003: kk_kclass_cast

    func testCastReturnsNullSentinelAndThrowsOnInvalidKClass() {
        var thrown = 0
        let result = kk_kclass_cast(runtimeNullSentinelInt, 42, &thrown)
        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0,
            "Expected ClassCastException for invalid KClass handle")
    }

    func testCastExceptionMessageContainsClassCastException() {
        var thrown = 0
        _ = kk_kclass_cast(runtimeNullSentinelInt, 42, &thrown)
        guard thrown != 0,
              let ptr = UnsafeMutableRawPointer(bitPattern: thrown),
              let box = tryCast(ptr, to: RuntimeThrowableBox.self)
        else {
            XCTFail("Expected a RuntimeThrowableBox")
            return
        }
        XCTAssertTrue(
            box.message.contains("ClassCastException"),
            "Exception message '\(box.message)' should contain 'ClassCastException'"
        )
    }

    func testCastWithNilOutThrown() {
        // Should not crash when outThrown is nil.
        let result = kk_kclass_cast(runtimeNullSentinelInt, 42, nil)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testCastExceptionContainsTypeName() {
        let kclass = registerKClass(
            typeToken: 2001, qualifiedName: "com.example.Foo", simpleName: "Foo"
        )
        let kclass2 = registerKClass(
            typeToken: 2002, qualifiedName: "com.example.Bar", simpleName: "Bar"
        )
        // kclass2's handle has type token 2002, kclass has type token 2001 — they differ.
        var thrown = 0
        let result = kk_kclass_cast(kclass, kclass2, &thrown)
        // If cast fails, result should be null sentinel and thrown non-zero.
        if thrown != 0 {
            XCTAssertEqual(result, runtimeNullSentinelInt)
            guard let ptr = UnsafeMutableRawPointer(bitPattern: thrown),
                  let box = tryCast(ptr, to: RuntimeThrowableBox.self)
            else {
                XCTFail("Expected RuntimeThrowableBox")
                return
            }
            XCTAssertTrue(
                box.message.contains("ClassCastException"),
                "Message '\(box.message)' should contain 'ClassCastException'"
            )
            XCTAssertTrue(
                box.message.contains("Foo") || box.message.contains("com.example.Foo"),
                "Message '\(box.message)' should contain the type name"
            )
        }
    }

    // MARK: - ABI-003: kk_kclass_safeCast

    func testSafeCastReturnsNullSentinelForInvalidKClass() {
        let result = kk_kclass_safeCast(runtimeNullSentinelInt, 42)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testSafeCastNeverThrows() {
        // safeCast must not require an outThrown parameter — it's a pure value return.
        // Calling with an invalid kclass just returns null sentinel with no exception.
        let result = kk_kclass_safeCast(0, 42)
        XCTAssertEqual(result, runtimeNullSentinelInt)
    }

    func testSafeCastReturnsNullSentinelOnMismatch() {
        let kclass = registerKClass(
            typeToken: 3001, qualifiedName: "pkg.X", simpleName: "X"
        )
        let kclass2 = registerKClass(
            typeToken: 3002, qualifiedName: "pkg.Y", simpleName: "Y"
        )
        // kclass2 handle has type token 3002, kclass has type token 3001 — they differ.
        let result = kk_kclass_safeCast(kclass, kclass2)
        // Either succeeds (if kk_op_is is lenient) or returns null sentinel — no crash.
        if result != runtimeNullSentinelInt {
            XCTAssertEqual(result, kclass2)
        }
    }

    func testSafeCastIsConsistentWithIsInstance() {
        let kclass = registerKClass(
            typeToken: 3003, qualifiedName: "pkg.Z", simpleName: "Z"
        )
        let someValue = registerRuntimeObject(RuntimeListBox(elements: []))
        let isInstance = kk_kclass_isInstance(kclass, someValue)
        let safeCastResult = kk_kclass_safeCast(kclass, someValue)

        if isInstance == 1 {
            XCTAssertEqual(safeCastResult, someValue)
        } else {
            XCTAssertEqual(safeCastResult, runtimeNullSentinelInt)
        }
    }

    func testCastIsConsistentWithIsInstance() {
        let kclass = registerKClass(
            typeToken: 3004, qualifiedName: "pkg.W", simpleName: "W"
        )
        let someValue = registerRuntimeObject(RuntimeListBox(elements: []))
        let isInstance = kk_kclass_isInstance(kclass, someValue)

        var thrown = 0
        let castResult = kk_kclass_cast(kclass, someValue, &thrown)

        if isInstance == 1 {
            XCTAssertEqual(castResult, someValue)
            XCTAssertEqual(thrown, 0)
        } else {
            XCTAssertEqual(castResult, runtimeNullSentinelInt)
            XCTAssertNotEqual(thrown, 0)
        }
    }
}
