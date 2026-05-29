@testable import Runtime
import XCTest

final class RuntimeSecureRandomTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    private func runtimeListInts(_ raw: Int) -> [Int] {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeListBox.self) else {
            return []
        }
        return box.elements
    }

    func testSecureRandomGenerateSeedProducesRequestedLength() {
        let secure = kk_secure_random_get_instance()
        let bytes = runtimeListInts(kk_secure_random_generate_seed(secure, 8))

        XCTAssertEqual(bytes.count, 8)
    }

    func testSecureRandomSetSeedMakesOutputDeterministic() {
        let a = kk_secure_random_get_instance()
        let b = kk_secure_random_get_instance()
        _ = kk_secure_random_set_seed(a, 12345)
        _ = kk_secure_random_set_seed(b, 12345)

        let first = runtimeListInts(kk_secure_random_generate_seed(a, 6))
        let second = runtimeListInts(kk_secure_random_generate_seed(b, 6))

        XCTAssertEqual(first, second)
    }

    func testSecureRandomNextBytesUsesInputLength() {
        let secure = kk_secure_random_get_instance()
        let input = registerRuntimeObject(RuntimeListBox(elements: Array(repeating: 0, count: 5)))
        let output = runtimeListInts(kk_secure_random_next_bytes(secure, input))

        XCTAssertEqual(output.count, 5)
    }

    func testSecureRandomNextBytesSizeProducesRequestedLengthAndRejectsNegativeSize() {
        let secure = kk_secure_random_get_instance()
        var thrown = 0

        let output = runtimeListInts(kk_secure_random_next_bytes_size(secure, 7, &thrown))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(output.count, 7)

        _ = kk_secure_random_next_bytes_size(secure, -1, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }
}
