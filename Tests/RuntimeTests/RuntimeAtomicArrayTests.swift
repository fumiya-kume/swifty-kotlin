import Foundation
@testable import Runtime
import XCTest

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

private let atomicArrayIndexTimesTen: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { index, _ in
    index * 10
}

private let atomicArrayIncrement: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { value, _ in
    value + 1
}

final class RuntimeAtomicArrayTests: IsolatedRuntimeXCTestCase {
    private func capturePrintln(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let savedFD = dup(STDOUT_FILENO)
        fflush(nil)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        block()
        fflush(nil)
        dup2(savedFD, STDOUT_FILENO)
        close(savedFD)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func makeArrayRaw(_ elements: [Int]) -> Int {
        let raw = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(raw, index, element, &thrown)
            XCTAssertEqual(thrown, 0)
        }
        return raw
    }

    private func makeRuntimeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func throwableMessage(_ raw: Int) -> String {
        let messageRaw = kk_throwable_message(raw)
        return extractString(from: UnsafeMutableRawPointer(bitPattern: messageRaw)) ?? ""
    }

    func testAtomicArrayCreateCopiesSourceStorage() {
        let source = makeArrayRaw([1, 2, 3])
        let atomic = kk_atomic_array_create(source)

        var thrown = 0
        XCTAssertEqual(kk_atomic_array_size(atomic), 3)
        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 1, &thrown), 2)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(kk_atomic_array_exchangeAt(atomic, 2, 77, &thrown), 3)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 2, &thrown), 77)
        XCTAssertEqual(thrown, 0)

        _ = kk_array_set(source, 1, 99, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 1, &thrown), 2)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_array_get(source, 1, &thrown), 99)
        XCTAssertEqual(thrown, 0)
    }

    func testAtomicArrayFactoryUpdateAndPrinting() {
        var thrown = 0
        let atomic = kk_atomic_array_new(3, unsafeBitCast(atomicArrayIndexTimesTen, to: Int.self), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(atomic, 0)
        XCTAssertEqual(kk_atomic_array_size(atomic), 3)

        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 0, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 1, &thrown), 10)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 2, &thrown), 20)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(kk_atomic_array_storeAt(atomic, 1, 11, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_exchangeAt(atomic, 1, 12, &thrown), 11)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_fetchAndUpdateAt(atomic, 1, unsafeBitCast(atomicArrayIncrement, to: Int.self), &thrown), 12)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_updateAndFetchAt(atomic, 1, unsafeBitCast(atomicArrayIncrement, to: Int.self), &thrown), 14)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_updateAt(atomic, 1, unsafeBitCast(atomicArrayIncrement, to: Int.self), &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 1, &thrown), 15)
        XCTAssertEqual(thrown, 0)

        let atomicNulls = kk_atomic_array_ofNulls(2)
        XCTAssertEqual(kk_atomic_array_size(atomicNulls), 2)
        XCTAssertEqual(extractString(from: kk_atomic_array_toString(atomicNulls)), "[null, null]")
        let printedNulls = capturePrintln { kk_println_any(kk_atomic_array_toString(atomicNulls)) }
        XCTAssertEqual(printedNulls, "[null, null]")

        let rendered = extractString(from: kk_atomic_array_toString(atomic))
        XCTAssertEqual(rendered, "[0, 15, 20]")
        let printed = capturePrintln { kk_println_any(kk_atomic_array_toString(atomic)) }
        XCTAssertEqual(printed, "[0, 15, 20]")
    }

    func testAtomicArrayCompareAndSetUsesRawHandleEquality() {
        let left = makeRuntimeStringRaw("same")
        let sameContentsDifferentHandle = makeRuntimeStringRaw("same")
        let replacement = makeRuntimeStringRaw("other")

        let source = makeArrayRaw([left])
        let atomic = kk_atomic_array_create(source)
        var thrown = 0

        XCTAssertEqual(kk_atomic_array_compareAndSetAt(atomic, 0, sameContentsDifferentHandle, replacement, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 0, &thrown), left)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(kk_atomic_array_compareAndSetAt(atomic, 0, left, replacement, &thrown), 1)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 0, &thrown), replacement)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(kk_atomic_array_compareAndExchangeAt(atomic, 0, sameContentsDifferentHandle, left, &thrown), replacement)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 0, &thrown), replacement)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(kk_atomic_array_compareAndExchangeAt(atomic, 0, replacement, left, &thrown), replacement)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 0, &thrown), left)
        XCTAssertEqual(thrown, 0)
    }

    func testAtomicArrayBoundsAndNegativeSizeErrors() {
        let atomic = kk_atomic_array_ofNulls(1)
        var thrown = 0

        XCTAssertEqual(kk_atomic_array_loadAt(atomic, 10, &thrown), 0)
        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(throwableMessage(thrown), "AtomicArray index 10 out of bounds for length 1.")

        thrown = 0
        XCTAssertEqual(kk_atomic_array_storeAt(atomic, -1, 5, &thrown), 0)
        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(throwableMessage(thrown), "AtomicArray index -1 out of bounds for length 1.")

        thrown = 0
        let negative = kk_atomic_array_new(-1, unsafeBitCast(atomicArrayIndexTimesTen, to: Int.self), &thrown)
        XCTAssertEqual(negative, 0)
        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(throwableMessage(thrown), "IllegalArgumentException: size must be non-negative, but was -1.")
    }
}
