@testable import Runtime
import XCTest

private final class MockCounterService {
    let mock = RuntimeMockBox()

    func tick(_ value: Int) -> Int {
        mock.invoke(methodName: "tick", arguments: [value])
    }
}

final class RuntimeMockTests: IsolatedRuntimeXCTestCase {
    func testMockReturnsStubbedValuesInOrder() {
        let service = MockCounterService()
        service.mock.whenever(methodName: "tick", matchers: [.eq(7)]).thenReturn(10).thenReturn(20)

        XCTAssertEqual(service.tick(7), 10)
        XCTAssertEqual(service.tick(7), 20)
        XCTAssertEqual(service.tick(7), 20, "The last stubbed value should keep being returned.")
        XCTAssertEqual(service.mock.verify(methodName: "tick", matchers: [.eq(7)]), 3)
    }

    func testAnyMatcherMatchesEveryInvocation() {
        let service = MockCounterService()
        service.mock.whenever(methodName: "tick", matchers: [.any]).thenReturn(99)

        XCTAssertEqual(service.tick(1), 99)
        XCTAssertEqual(service.tick(2), 99)
        XCTAssertEqual(service.mock.verify(methodName: "tick", matchers: [.any]), 2)
    }

    func testFallbackActsLikeASpyWhenNoStubMatches() {
        let spy = RuntimeMockBox(fallback: { _, arguments in
            (arguments.first ?? 0) + 1
        })
        spy.whenever(methodName: "tick", matchers: [.eq(5)]).thenReturn(42)

        XCTAssertEqual(spy.invoke(methodName: "tick", arguments: [3]), 4)
        XCTAssertEqual(spy.invoke(methodName: "tick", arguments: [5]), 42)
        XCTAssertEqual(spy.verify(methodName: "tick", matchers: [.eq(5)]), 1)
    }

    func testResetClearsRecordedCallsAndStubs() {
        let service = MockCounterService()
        service.mock.whenever(methodName: "tick", matchers: [.eq(1)]).thenReturn(11)
        XCTAssertEqual(service.tick(1), 11)

        service.mock.reset()

        XCTAssertEqual(service.mock.verify(methodName: "tick", matchers: [.eq(1)]), 0)
        XCTAssertEqual(service.tick(1), 0)
    }
}
