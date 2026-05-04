import Foundation
@testable import Runtime
import XCTest

// MARK: - AtomicArray<T> runtime tests (STDLIB-033-ABI-002)
//
// Covers kk_atomic_ref_array_* cdecl entries introduced for the generic
// kotlin.concurrent.atomics.AtomicArray<T> class.
// CAS uses identity semantics (pointer equality), not structural equality.

private let refArrayThunkReturn42: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in 42 }
private let refArrayThunkReturn42Ptr = unsafeBitCast(refArrayThunkReturn42, to: Int.self)

final class RuntimeAtomicRefArrayTests: XCTestCase {

    // MARK: - new / size

    func testNewReturnsNonZeroHandle() {
        let handle = kk_atomic_ref_array_new(4)
        XCTAssertNotEqual(handle, 0)
    }

    func testSizeMatchesRequestedCapacity() {
        let handle = kk_atomic_ref_array_new(7)
        XCTAssertEqual(kk_atomic_ref_array_size(handle), 7)
    }

    func testZeroSizeArrayIsAllowed() {
        let handle = kk_atomic_ref_array_new(0)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_atomic_ref_array_size(handle), 0)
    }

    func testInvalidHandleSizeReturnsZero() {
        XCTAssertEqual(kk_atomic_ref_array_size(0), 0)
    }

    // MARK: - loadAt / storeAt

    func testInitialElementsAreZero() {
        let handle = kk_atomic_ref_array_new(3)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 0), 0)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 1), 0)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 2), 0)
    }

    func testStoreAndLoadRoundTrip() {
        let handle = kk_atomic_ref_array_new(5)
        let ref = kk_atomic_int_create(42) // use a managed object pointer as the "reference"
        kk_atomic_ref_array_storeAt(handle, 2, ref)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 2), ref)
    }

    func testStoreAtFirstAndLastIndex() {
        let handle = kk_atomic_ref_array_new(4)
        let refA = kk_atomic_int_create(1)
        let refB = kk_atomic_int_create(2)
        kk_atomic_ref_array_storeAt(handle, 0, refA)
        kk_atomic_ref_array_storeAt(handle, 3, refB)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 0), refA)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 3), refB)
    }

    func testLoadAtOutOfBoundsReturnsZero() {
        let handle = kk_atomic_ref_array_new(2)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 5), 0)
    }

    func testStoreAtOutOfBoundsIsNoop() {
        let handle = kk_atomic_ref_array_new(2)
        let ref = kk_atomic_int_create(99)
        kk_atomic_ref_array_storeAt(handle, 10, ref)
        // No crash and indices within bounds remain zero
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 0), 0)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 1), 0)
    }

    func testStoreReturnsZeroUnit() {
        let handle = kk_atomic_ref_array_new(1)
        let ref = kk_atomic_int_create(1)
        let result = kk_atomic_ref_array_storeAt(handle, 0, ref)
        XCTAssertEqual(result, 0)
    }

    // MARK: - compareAndSetAt (identity-based)

    func testCompareAndSetAtSucceedsWhenExpectMatches() {
        let handle = kk_atomic_ref_array_new(3)
        let refA = kk_atomic_int_create(10)
        let refB = kk_atomic_int_create(20)
        kk_atomic_ref_array_storeAt(handle, 1, refA)

        let result = kk_atomic_ref_array_compareAndSetAt(handle, 1, refA, refB)
        XCTAssertEqual(result, 1, "CAS must succeed (return 1) when expected identity matches")
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 1), refB)
    }

    func testCompareAndSetAtFailsWhenExpectMismatches() {
        let handle = kk_atomic_ref_array_new(3)
        let refA = kk_atomic_int_create(10)
        let refB = kk_atomic_int_create(20)
        let refC = kk_atomic_int_create(30)
        kk_atomic_ref_array_storeAt(handle, 1, refA)

        let result = kk_atomic_ref_array_compareAndSetAt(handle, 1, refC, refB)
        XCTAssertEqual(result, 0, "CAS must fail (return 0) on identity mismatch")
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 1), refA, "Value must not change on failure")
    }

    func testCompareAndSetAtOutOfBoundsReturnsFalse() {
        let handle = kk_atomic_ref_array_new(2)
        let ref = kk_atomic_int_create(1)
        let result = kk_atomic_ref_array_compareAndSetAt(handle, 99, 0, ref)
        XCTAssertEqual(result, 0)
    }

    func testCompareAndSetAtIsIdempotentWhenAlreadyNew() {
        let handle = kk_atomic_ref_array_new(1)
        let ref = kk_atomic_int_create(7)
        kk_atomic_ref_array_storeAt(handle, 0, ref)

        // Successful CAS sets value to ref; subsequent CAS with old=ref and same new=ref succeeds
        let r1 = kk_atomic_ref_array_compareAndSetAt(handle, 0, ref, ref)
        XCTAssertEqual(r1, 1)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 0), ref)
    }

    // MARK: - compareAndExchangeAt (identity-based)

    func testCompareAndExchangeAtReturnsOldValueOnSuccess() {
        let handle = kk_atomic_ref_array_new(2)
        let refA = kk_atomic_int_create(1)
        let refB = kk_atomic_int_create(2)
        kk_atomic_ref_array_storeAt(handle, 0, refA)

        let old = kk_atomic_ref_array_compareAndExchangeAt(handle, 0, refA, refB)
        XCTAssertEqual(old, refA, "compareAndExchangeAt must return the old value on success")
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 0), refB)
    }

    func testCompareAndExchangeAtReturnsCurrentValueOnFailure() {
        let handle = kk_atomic_ref_array_new(2)
        let refA = kk_atomic_int_create(1)
        let refB = kk_atomic_int_create(2)
        let refC = kk_atomic_int_create(3)
        kk_atomic_ref_array_storeAt(handle, 0, refA)

        let old = kk_atomic_ref_array_compareAndExchangeAt(handle, 0, refC, refB)
        XCTAssertEqual(old, refA, "compareAndExchangeAt must return current value on failure")
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 0), refA, "Value must not change on failure")
    }

    func testCompareAndExchangeAtOutOfBoundsReturnsZero() {
        let handle = kk_atomic_ref_array_new(2)
        let ref = kk_atomic_int_create(1)
        let old = kk_atomic_ref_array_compareAndExchangeAt(handle, 99, 0, ref)
        XCTAssertEqual(old, 0)
    }

    // MARK: - fetchAndUpdateAt

    func testFetchAndUpdateAtReturnsOldValueAndStoresTransformedValue() {
        let handle = kk_atomic_ref_array_new(1)
        kk_atomic_ref_array_storeAt(handle, 0, 10)

        let old = kk_atomic_ref_array_fetchAndUpdateAt(handle, 0, refArrayThunkReturn42Ptr, nil)

        XCTAssertEqual(old, 10)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 0), 42)
    }

    func testFetchAndUpdateAtOutOfBoundsReturnsZero() {
        let handle = kk_atomic_ref_array_new(1)

        let old = kk_atomic_ref_array_fetchAndUpdateAt(handle, 2, refArrayThunkReturn42Ptr, nil)

        XCTAssertEqual(old, 0)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handle, 0), 0)
    }

    // MARK: - Multiple independent arrays

    func testTwoArraysDoNotInterfere() {
        let handleA = kk_atomic_ref_array_new(3)
        let handleB = kk_atomic_ref_array_new(3)
        let refA = kk_atomic_int_create(100)
        let refB = kk_atomic_int_create(200)

        kk_atomic_ref_array_storeAt(handleA, 0, refA)
        kk_atomic_ref_array_storeAt(handleB, 0, refB)

        XCTAssertEqual(kk_atomic_ref_array_loadAt(handleA, 0), refA)
        XCTAssertEqual(kk_atomic_ref_array_loadAt(handleB, 0), refB)
    }

    // MARK: - Invalid handle safety

    func testInvalidHandleLoadAtReturnsZero() {
        XCTAssertEqual(kk_atomic_ref_array_loadAt(0, 0), 0)
    }

    func testInvalidHandleStoreAtIsNoop() {
        let ref = kk_atomic_int_create(1)
        let result = kk_atomic_ref_array_storeAt(0, 0, ref)
        XCTAssertEqual(result, 0)
    }

    func testInvalidHandleCompareAndSetAtReturnsFalse() {
        let result = kk_atomic_ref_array_compareAndSetAt(0, 0, 0, 1)
        XCTAssertEqual(result, 0)
    }

    func testInvalidHandleCompareAndExchangeAtReturnsZero() {
        let result = kk_atomic_ref_array_compareAndExchangeAt(0, 0, 0, 1)
        XCTAssertEqual(result, 0)
    }
}
