import Foundation
@testable import Runtime
import XCTest

private let exceptionID = 12345

private let lambdaThatThrows: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

private let lambdaThatThrows2: @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, _, _, outThrown in
    outThrown?.pointee = exceptionID
    return 0
}

final class RuntimeCollectionHOFThrowTests: XCTestCase {
    
    func testListMapThrows() {
        let array = kk_array_new(3)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        _ = kk_array_set(array, 1, 2, &thrown)
        _ = kk_array_set(array, 2, 3, &thrown)
        let listWithData = kk_list_of(array, 3)
        
        var outThrown = 0
        let result = kk_list_map(listWithData, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListFilterThrows() {
        let array = kk_array_new(1)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        let list = kk_list_of(array, 1)
        
        var outThrown = 0
        let result = kk_list_filter(list, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListForEachThrows() {
        let array = kk_array_new(1)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        let list = kk_list_of(array, 1)
        
        var outThrown = 0
        let result = kk_list_forEach(list, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testArrayMapThrows() {
        let array = kk_array_new(1)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        
        var outThrown = 0
        let result = kk_array_map(array, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testMapForEachThrows() {
        let map = kk_map_of(kk_array_new(0), kk_array_new(0), 0)
        var thrown = 0
        _ = kk_mutable_map_put(map, 1, 10)
        
        var outThrown = 0
        let result = kk_map_forEach(map, unsafeBitCast(lambdaThatThrows, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListReduceEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_reduce(list, 0, 0, &outThrown)
        
        XCTAssertNotEqual(outThrown, 0)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListFirstEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_first(list, 0, 0, &outThrown)
        
        XCTAssertNotEqual(outThrown, 0)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListLastEmptyThrows() {
        let list = kk_list_of(kk_array_new(0), 0)
        var outThrown = 0
        let result = kk_list_last(list, 0, 0, &outThrown)
        
        XCTAssertNotEqual(outThrown, 0)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
    
    func testListFoldThrows() {
        let array = kk_array_new(1)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        let list = kk_list_of(array, 1)
        
        var outThrown = 0
        let result = kk_list_fold(list, 0, unsafeBitCast(lambdaThatThrows2, to: Int.self), 0, &outThrown)
        
        XCTAssertEqual(outThrown, exceptionID)
        XCTAssertEqual(result, runtimeExceptionCaughtSentinel)
    }
}
