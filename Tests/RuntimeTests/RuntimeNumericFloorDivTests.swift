@testable import Runtime
import XCTest

final class RuntimeNumericFloorDivTests: XCTestCase {
    func testSignedFloorDivMatchesKotlinSemantics() {
        XCTAssertEqual(kk_op_floor_div(7, 3), 2)
        XCTAssertEqual(kk_op_floor_div(-7, 3), -3)
        XCTAssertEqual(kk_op_floor_div(7, -3), -3)
        XCTAssertEqual(kk_op_floor_div(-7, -3), 2)
        XCTAssertEqual(kk_op_floor_div(1, 0), 0)
    }

    func testLongFloorDivUsesSameRuntimeSemantics() {
        XCTAssertEqual(kk_op_lfloor_div(7, 3), 2)
        XCTAssertEqual(kk_op_lfloor_div(-7, 3), -3)
        XCTAssertEqual(kk_op_lfloor_div(7, -3), -3)
        XCTAssertEqual(kk_op_lfloor_div(-7, -3), 2)
        XCTAssertEqual(kk_op_lfloor_div(Int.min, -1), Int.min)
    }
}
