#if os(Linux)
import XCTest

// Linux test discovery in Swift 6.2 can emit @Sendable test function references.
// Provide matching overloads to avoid runtime force-casts to non-sendable signatures.
public func testCase<T: XCTestCase>(
    _ allTests: [(String, @Sendable (T) -> () -> Void)]
) -> XCTestCaseEntry {
    let bridged: [(String, (T) -> () -> Void)] = allTests.map { name, function in
        (name, { instance in
            let body = function(instance)
            return { body() }
        })
    }
    return XCTest.testCase(bridged)
}

public func testCase<T: XCTestCase>(
    _ allTests: [(String, @Sendable (T) -> () throws -> Void)]
) -> XCTestCaseEntry {
    let bridged: [(String, (T) -> () throws -> Void)] = allTests.map { name, function in
        (name, { instance in
            let body = function(instance)
            return { try body() }
        })
    }
    return XCTest.testCase(bridged)
}
#endif
