@testable import Runtime
import XCTest

private let atomicIntArrayInitLambda: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { index, outThrown in
    outThrown?.pointee = 0
    return index * 10
}

private let atomicIntArrayIncrementLambda: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { value, outThrown in
    outThrown?.pointee = 0
    return value + 2
}

private let atomicIntArrayThrowingLambda: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0xBEEF
    return 0
}

final class RuntimeAtomicIntArrayTests: IsolatedRuntimeXCTestCase {
    private func functionPtr(
        _ fn: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
    ) -> Int {
        unsafeBitCast(fn, to: Int.self)
    }

    private func makeRuntimeArray(_ elements: [Int]) -> Int {
        let array = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            XCTAssertEqual(kk_array_set(array, index, element, &thrown), element)
            XCTAssertEqual(thrown, 0)
        }
        return array
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    func testSizeConstructorAndLengthAlias() {
        let array = kk_atomic_int_array_new(3)

        XCTAssertEqual(kk_atomic_int_array_size(array), 3)
        XCTAssertEqual(kk_atomic_int_array_size(kk_atomic_int_array_new(-7)), 0)

        var thrown = 0
        XCTAssertEqual(kk_atomic_int_array_loadAt(array, 0, &thrown), 0)
        XCTAssertEqual(thrown, 0)
    }

    func testCopyConstructorDoesNotShareStorage() {
        let source = makeRuntimeArray([1, 2, 3])
        let atomic = kk_atomic_int_array_fromArray(source)

        var thrown = 0
        XCTAssertEqual(kk_atomic_int_array_loadAt(atomic, 1, &thrown), 2)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(kk_array_set(source, 1, 99, &thrown), 99)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_loadAt(atomic, 1, &thrown), 2)
        XCTAssertEqual(thrown, 0)
    }

    func testFactoryInitializesValuesAndToString() {
        var thrown = 0
        let array = kk_atomic_int_array_create(4, functionPtr(atomicIntArrayInitLambda), &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_size(array), 4)

        var loadThrown = 0
        XCTAssertEqual(kk_atomic_int_array_loadAt(array, 3, &loadThrown), 30)
        XCTAssertEqual(loadThrown, 0)
        XCTAssertEqual(runtimeStringValue(kk_atomic_int_array_toString(array)), "[0, 10, 20, 30]")
    }

    func testFactoryPropagatesThrownLambda() {
        var thrown = 0
        let array = kk_atomic_int_array_create(3, functionPtr(atomicIntArrayThrowingLambda), &thrown)

        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_size(array), 0)
    }

    func testStoreLoadCompareAndExchange() {
        let array = kk_atomic_int_array_new(2)
        var thrown = 0

        XCTAssertEqual(kk_atomic_int_array_storeAt(array, 0, 7, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_loadAt(array, 0, &thrown), 7)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_compareAndSetAt(array, 0, 7, 9, &thrown), 1)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_compareAndSetAt(array, 0, 7, 11, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_compareAndExchangeAt(array, 0, 9, 13, &thrown), 9)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_loadAt(array, 0, &thrown), 13)
        XCTAssertEqual(thrown, 0)
    }

    func testArithmeticMethodsUpdateValues() {
        let array = kk_atomic_int_array_new(1)
        var thrown = 0

        XCTAssertEqual(kk_atomic_int_array_fetchAndAddAt(array, 0, 5, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_addAndFetchAt(array, 0, 3, &thrown), 8)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_fetchAndIncrementAt(array, 0, &thrown), 8)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_incrementAndFetchAt(array, 0, &thrown), 10)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_fetchAndDecrementAt(array, 0, &thrown), 10)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_decrementAndFetchAt(array, 0, &thrown), 8)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_loadAt(array, 0, &thrown), 8)
        XCTAssertEqual(thrown, 0)
    }

    func testUpdateLambdaMethodsAndThrowPropagation() {
        let array = kk_atomic_int_array_new(1)
        var thrown = 0

        XCTAssertEqual(kk_atomic_int_array_fetchAndUpdateAt(array, 0, functionPtr(atomicIntArrayIncrementLambda), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_updateAndFetchAt(array, 0, functionPtr(atomicIntArrayIncrementLambda), &thrown), 4)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_updateAt(array, 0, functionPtr(atomicIntArrayIncrementLambda), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_loadAt(array, 0, &thrown), 6)
        XCTAssertEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_atomic_int_array_updateAt(array, 0, functionPtr(atomicIntArrayThrowingLambda), &thrown), 0)
        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_loadAt(array, 0, &thrown), 6)
        XCTAssertEqual(thrown, 0)
    }

    func testOutOfBoundsReportsThrownChannel() {
        let array = kk_atomic_int_array_new(1)
        var thrown = 0

        XCTAssertEqual(kk_atomic_int_array_loadAt(array, 5, &thrown), 0)
        XCTAssertNotEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_atomic_int_array_storeAt(array, 5, 1, &thrown), 0)
        XCTAssertNotEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_atomic_int_array_fetchAndAddAt(array, 5, 1, &thrown), 0)
        XCTAssertNotEqual(thrown, 0)
    }
}
