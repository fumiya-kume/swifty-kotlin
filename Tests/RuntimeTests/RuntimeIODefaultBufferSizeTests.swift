@testable import Runtime
import XCTest

final class RuntimeIODefaultBufferSizeTests: XCTestCase {
    func testDefaultBufferSizeMatchesKotlinStdlibValue() {
        XCTAssertEqual(kk_io_default_buffer_size(), 8192)
    }
}
