@testable import Runtime
import XCTest

final class RuntimeArrayBoundsTests: IsolatedRuntimeXCTestCase {
    func testArrayGetAndSetInBounds() {
        let array = kk_array_new(2)
        XCTAssertNotEqual(array, 0)

        var outThrown = -1
        XCTAssertEqual(kk_array_set(array, 1, 42, &outThrown), 42)
        XCTAssertEqual(outThrown, 0)

        outThrown = -1
        XCTAssertEqual(kk_array_get(array, 1, &outThrown), 42)
        XCTAssertEqual(outThrown, 0)
    }

    func testArrayOutOfBoundsSetsThrownChannel() {
        let array = kk_array_new(1)
        XCTAssertNotEqual(array, 0)

        var outThrown = 0
        XCTAssertEqual(kk_array_get(array, 5, &outThrown), 0)
        XCTAssertNotEqual(outThrown, 0)
    }
}
