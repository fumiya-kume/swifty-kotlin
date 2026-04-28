@testable import CompilerCore
import XCTest

final class IntegerFloorDivMemberCallTests: XCTestCase {
    func testSignedAndUnsignedFloorDivMemberCallsInferExpectedTypes() throws {
        let source = """
        fun sample(b: Byte, s: Short, i: Int, l: Long, ub: UByte, us: UShort, ui: UInt, ul: ULong) {
            val byteShort: Int = b.floorDiv(s)
            val intLong: Long = i.floorDiv(l)
            val longByte: Long = l.floorDiv(b)
            val ubyteUshort: UInt = ub.floorDiv(us)
            val uintUbyte: UInt = ui.floorDiv(ub)
            val ulongUInt: ULong = ul.floorDiv(ui)
            val uintULong: ULong = ui.floorDiv(ul)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        XCTAssertTrue(ctx.diagnostics.diagnostics.isEmpty, "Expected floorDiv overload matrix to type-check cleanly")
    }

    func testFloorDivRejectsFloatingAndMixedSignednessReceivers() {
        let source = """
        fun sample(i: Int, ui: UInt, d: Double) {
            i.floorDiv(ui)
            ui.floorDiv(i)
            d.floorDiv(2.0)
        }
        """

        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are asserted below.
        }

        XCTAssertGreaterThanOrEqual(
            ctx.diagnostics.diagnostics.count,
            3,
            "Expected floorDiv to reject mixed signedness and floating receivers"
        )
    }
}
