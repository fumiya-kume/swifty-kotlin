@testable import Runtime
import XCTest

// MARK: - ABI-004 / ABI-005 Runtime Tests

/// Tests for STDLIB-NATIVE-REF-ABI-004 (recursive freeze) and
/// ABI-005 (idempotent kk_unpin_object).
final class RuntimeNativeABIEdgeCaseTests: IsolatedRuntimeXCTestCase {
    override func resetIsolatedRuntimeTestState() {
        // kk_runtime_force_reset() is called by the base class setUp/tearDown.
    }

    // MARK: - ABI-004: Recursive freeze

    /// Freezing a parent object must also freeze a directly referenced child.
    func testFreezeParentAlsoFreezesDirectChild() {
        // Create parent and child as RuntimeObjectBox objects with 1 field slot.
        let child = RuntimeObjectBox(length: 0, classID: 1)
        let childRaw = registerRuntimeObject(child)

        let parent = RuntimeObjectBox(length: 1, classID: 2)
        parent.elements[0] = childRaw
        let parentRaw = registerRuntimeObject(parent)

        // Before freeze: neither is frozen.
        XCTAssertEqual(kk_is_frozen(parentRaw), 0, "parent should not be frozen before freeze()")
        XCTAssertEqual(kk_is_frozen(childRaw), 0, "child should not be frozen before freeze()")

        _ = kk_freeze_object(parentRaw)

        XCTAssertEqual(kk_is_frozen(parentRaw), 1, "parent must be frozen after freeze()")
        XCTAssertEqual(kk_is_frozen(childRaw), 1, "child reachable from parent must be frozen (ABI-004)")
    }

    /// Freezing the root of a two-level chain must freeze all levels.
    func testFreezeRecursiveTwoLevels() {
        let grandchild = RuntimeObjectBox(length: 0, classID: 10)
        let grandchildRaw = registerRuntimeObject(grandchild)

        let child = RuntimeObjectBox(length: 1, classID: 11)
        child.elements[0] = grandchildRaw
        let childRaw = registerRuntimeObject(child)

        let parent = RuntimeObjectBox(length: 1, classID: 12)
        parent.elements[0] = childRaw
        let parentRaw = registerRuntimeObject(parent)

        _ = kk_freeze_object(parentRaw)

        XCTAssertEqual(kk_is_frozen(parentRaw), 1, "root must be frozen")
        XCTAssertEqual(kk_is_frozen(childRaw), 1, "mid-level child must be frozen")
        XCTAssertEqual(kk_is_frozen(grandchildRaw), 1, "leaf grandchild must be frozen")
    }

    /// Freeze on a cyclic graph (A → B → A) must terminate and freeze all nodes.
    func testFreezeWithCycleTerminates() {
        // A and B each have 1 element slot. We create them then set up A.elements[0] = B
        // and B.elements[0] = A.
        let a = RuntimeObjectBox(length: 1, classID: 20)
        let b = RuntimeObjectBox(length: 1, classID: 21)
        let aRaw = registerRuntimeObject(a)
        let bRaw = registerRuntimeObject(b)

        a.elements[0] = bRaw
        b.elements[0] = aRaw

        // This must return (not hang) and mark both objects frozen.
        _ = kk_freeze_object(aRaw)

        XCTAssertEqual(kk_is_frozen(aRaw), 1, "node A must be frozen in cyclic graph")
        XCTAssertEqual(kk_is_frozen(bRaw), 1, "node B must be frozen in cyclic graph")
    }

    /// Freezing a node with a zero child ref must not crash (zero refs are skipped).
    func testFreezeObjectWithZeroChildRef() {
        let obj = RuntimeObjectBox(length: 1, classID: 30)
        obj.elements[0] = 0 // null / zero ref
        let raw = registerRuntimeObject(obj)

        // Must not crash.
        _ = kk_freeze_object(raw)
        XCTAssertEqual(kk_is_frozen(raw), 1, "object with zero child ref must still be frozen")
    }

    /// Freezing an already-frozen object must be idempotent and not crash.
    func testFreezingAlreadyFrozenObjectIsIdempotent() {
        let obj = RuntimeObjectBox(length: 0, classID: 40)
        let raw = registerRuntimeObject(obj)

        _ = kk_freeze_object(raw)
        _ = kk_freeze_object(raw) // second call must not crash

        XCTAssertEqual(kk_is_frozen(raw), 1)
    }

    /// Freeze using a RuntimeListBox — list elements must be frozen too.
    func testFreezeListBoxChildrenAreFrozen() {
        let item = RuntimeObjectBox(length: 0, classID: 50)
        let itemRaw = registerRuntimeObject(item)

        let list = RuntimeListBox(elements: [itemRaw])
        let listRaw = registerRuntimeObject(list)

        _ = kk_freeze_object(listRaw)

        XCTAssertEqual(kk_is_frozen(listRaw), 1, "list must be frozen")
        XCTAssertEqual(kk_is_frozen(itemRaw), 1, "list element must be frozen")
    }

    // MARK: - ABI-005: Idempotent kk_unpin_object

    /// Calling kk_unpin_object twice on the same handle must not crash.
    func testUnpinObjectTwiceDoesNotCrash() {
        let obj = RuntimeObjectBox(length: 0, classID: 100)
        let objRaw = registerRuntimeObject(obj)
        let pinHandle = kk_pin_object(objRaw)

        XCTAssertNotEqual(pinHandle, 0, "pin handle must be non-zero")

        let result1 = kk_unpin_object(pinHandle)
        XCTAssertEqual(result1, objRaw, "first unpin must return the original object raw")

        // Second unpin on the same handle: must be a no-op (not crash or UB).
        let result2 = kk_unpin_object(pinHandle)
        // result2 may be 0 (handle no longer valid) or objRaw (box still accessible).
        // The critical requirement is that it does not crash.
        _ = result2
    }

    /// Calling kk_unpin_object three times on the same handle must not crash.
    func testUnpinObjectThreeTimesDoesNotCrash() {
        let obj = RuntimeObjectBox(length: 0, classID: 101)
        let objRaw = registerRuntimeObject(obj)
        let pinHandle = kk_pin_object(objRaw)

        _ = kk_unpin_object(pinHandle)
        _ = kk_unpin_object(pinHandle) // second — no-op
        _ = kk_unpin_object(pinHandle) // third — no-op
    }

    /// After a valid unpin the returned raw must equal the original pinned object.
    func testUnpinObjectReturnsCorrectRaw() {
        let obj = RuntimeObjectBox(length: 0, classID: 102)
        let objRaw = registerRuntimeObject(obj)
        let pinHandle = kk_pin_object(objRaw)

        let returned = kk_unpin_object(pinHandle)
        XCTAssertEqual(returned, objRaw, "kk_unpin_object must return the pinned object's raw handle")
    }

    /// kk_unpin_object on a zero handle must return 0 and not crash.
    func testUnpinObjectZeroHandleIsNoop() {
        let result = kk_unpin_object(0)
        XCTAssertEqual(result, 0)
    }
}
