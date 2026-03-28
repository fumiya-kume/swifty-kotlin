@testable import Runtime
import XCTest

final class RuntimeCacheTests: IsolatedRuntimeXCTestCase {
    func testCacheEvictsLeastRecentlyUsedEntry() {
        let cache = kk_cache_new(2)
        _ = kk_cache_put(cache, 1, 10)
        _ = kk_cache_put(cache, 2, 20)
        XCTAssertEqual(kk_cache_get(cache, 1), 10)
        _ = kk_cache_put(cache, 3, 30)
        XCTAssertEqual(kk_cache_get(cache, 2), runtimeNullSentinelInt)
        XCTAssertEqual(kk_cache_size(cache), 2)
    }
}
