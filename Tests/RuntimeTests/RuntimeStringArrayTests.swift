@testable import Runtime
import XCTest

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

final class RuntimeStringArrayTests: IsolatedRuntimeXCTestCase {
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

    // MARK: - kk_string_from_utf8

    func testStringFromUTF8CreatesBoxedString() {
        let text = "Hello"
        let result = text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                kk_string_from_utf8(ptr, Int32(text.utf8.count))
            }
        }
        XCTAssertNotNil(result)
        // Verify via println
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "Hello")
    }

    func testStringFromUTF8EmptyString() {
        let text = ""
        let result = text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: 1) { ptr in
                kk_string_from_utf8(ptr, 0)
            }
        }
        XCTAssertNotNil(result)
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "")
    }

    // MARK: - kk_string_concat

    func testStringConcatTwoStrings() {
        let firstStr = makeRuntimeString("Hello, ")
        let secondStr = makeRuntimeString("World!")
        let result = kk_string_concat(firstStr, secondStr)
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "Hello, World!")
    }

    func testStringConcatWithNilLeftReturnsRightOnly() {
        let rightStr = makeRuntimeString("World")
        let result = kk_string_concat(nil, rightStr)
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "World")
    }

    func testStringConcatWithNilRightReturnsLeftOnly() {
        let leftStr = makeRuntimeString("Hello")
        let result = kk_string_concat(leftStr, nil)
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "Hello")
    }

    func testStringConcatBothNilReturnsEmptyString() {
        let result = kk_string_concat(nil, nil)
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "")
    }

    // MARK: - kk_string_compareTo

    func testStringCompareToEqual() {
        let firstStr = makeRuntimeString("abc")
        let secondStr = makeRuntimeString("abc")
        XCTAssertEqual(kk_string_compareTo(firstStr, secondStr), 0)
    }

    func testStringCompareToLessThan() {
        let firstStr = makeRuntimeString("abc")
        let secondStr = makeRuntimeString("xyz")
        XCTAssertEqual(kk_string_compareTo(firstStr, secondStr), -1)
    }

    func testStringCompareToGreaterThan() {
        let firstStr = makeRuntimeString("xyz")
        let secondStr = makeRuntimeString("abc")
        XCTAssertEqual(kk_string_compareTo(firstStr, secondStr), 1)
    }

    func testStringCompareToNils() {
        // Both nil -> equal empty strings
        XCTAssertEqual(kk_string_compareTo(nil, nil), 0)
    }

    func testCompareAnyDecodesBoxedDoubleValues() {
        let lhs = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 1.25.bitPattern)))
        let rhs = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern)))

        XCTAssertEqual(kk_compare_any(lhs, rhs), -1)
        XCTAssertEqual(kk_compare_any(rhs, lhs), 1)
    }

    func testCompareAnyPromotesMixedFloatingAndIntegerValues() {
        let lhs = kk_box_float(Int(Float(3).bitPattern))

        XCTAssertEqual(kk_compare_any(lhs, 5), -1)
        XCTAssertEqual(kk_compare_any(5, lhs), 1)
        XCTAssertEqual(kk_compare_any(lhs, 3), 0)
    }

    func testCompareAnyOrdersNaNAfterNonNaNValues() {
        let nan = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: Double.nan.bitPattern)))
        let finite = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 4.0.bitPattern)))

        XCTAssertEqual(kk_compare_any(nan, finite), 1)
        XCTAssertEqual(kk_compare_any(finite, nan), -1)
        XCTAssertEqual(kk_compare_any(nan, nan), 0)
    }

    // MARK: - STDLIB-006 string runtime ABI

    func testStringTrimRemovesLeadingAndTrailingWhitespace() {
        let raw = kk_string_trim(rawFromRuntimeString("  hello  "))
        XCTAssertEqual(runtimeStringValue(raw), "hello")
    }

    func testStringSplitProducesListOfStrings() {
        let splitRaw = kk_string_split(
            rawFromRuntimeString("1,2,3"),
            rawFromRuntimeString(",")
        )
        let list = runtimeListBox(from: splitRaw)
        XCTAssertEqual(list?.elements.count, 3)
        XCTAssertEqual(list?.elements.map(runtimeStringValue), ["1", "2", "3"])
    }

    func testStringReplaceSupportsLiteralReplacement() {
        let replaced = kk_string_replace(
            rawFromRuntimeString("aba"),
            rawFromRuntimeString("a"),
            rawFromRuntimeString("z")
        )
        XCTAssertEqual(runtimeStringValue(replaced), "zbz")
    }

    func testStringStartsWithEndsWithContains() {
        let source = rawFromRuntimeString("HelloWorld")
        XCTAssertEqual(kk_unbox_bool(kk_string_startsWith(source, rawFromRuntimeString("Hello"))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_string_endsWith(source, rawFromRuntimeString("World"))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_string_contains_str(source, rawFromRuntimeString("World"))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_string_contains_str(source, rawFromRuntimeString(""))), 1)
    }

    func testStringToIntSuccessAndFailure() {
        var thrown = 0
        let value = kk_string_toInt(rawFromRuntimeString("42"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(value, 42)

        _ = kk_string_toInt(rawFromRuntimeString("4x"), &thrown)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("NumberFormatException"))
    }

    func testStringToDoubleParsesSpecialValuesAndThrowsOnInvalidInput() {
        var thrown = 0
        let parsed = kk_string_toDouble(rawFromRuntimeString("  -Infinity "), &thrown)
        XCTAssertEqual(thrown, 0)
        let parsedValue = Double(bitPattern: UInt64(bitPattern: Int64(parsed)))
        XCTAssertEqual(parsedValue, -.infinity)

        let nanRaw = kk_string_toDouble(rawFromRuntimeString("NaN"), &thrown)
        XCTAssertEqual(thrown, 0)
        let nanValue = Double(bitPattern: UInt64(bitPattern: Int64(nanRaw)))
        XCTAssertTrue(nanValue.isNaN)

        _ = kk_string_toDouble(rawFromRuntimeString("nope"), &thrown)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("NumberFormatException"))
    }

    func testStringFormatSupportsStringIntAndDoubleSpecifiers() {
        let args = makeRuntimeArray([
            rawFromRuntimeString("age"),
            7,
            Int(bitPattern: UInt(truncatingIfNeeded: 3.5.bitPattern)),
        ])

        let formatted = kk_string_format(rawFromRuntimeString("%s:%d %.2f"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "age:7 3.50")
    }

    func testStringFormatSupportsFloatingSpecifiersForIntegersAndBoxedFloats() {
        let args = makeRuntimeArray([
            3,
            kk_box_float(Int(Float(1.5).bitPattern)),
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern))),
        ])

        let formatted = kk_string_format(rawFromRuntimeString("%.1f %.1f %.1f"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "3.0 1.5 2.5")
    }

    func testStringFormatSupportsPositionalArguments() {
        let args = makeRuntimeArray([
            7,
            rawFromRuntimeString("age"),
        ])

        let formatted = kk_string_format(rawFromRuntimeString("%2$s:%1$d"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "age:7")
    }

    func testStringFormatSupportsBooleanSpecifiers() {
        let args = makeRuntimeArray([
            kk_box_bool(1),
            kk_box_bool(0),
            runtimeNullSentinelInt,
        ])

        let formatted = kk_string_format(rawFromRuntimeString("%b %B %b"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "true FALSE false")
    }

    func testStringFormatPreservesSixtyFourBitIntegerWidth() {
        let signed = Int(Int64.max)
        let unsigned = Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max))
        let args = makeRuntimeArray([signed, unsigned])

        let formatted = kk_string_format(rawFromRuntimeString("%d %x"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "9223372036854775807 ffffffffffffffff")
    }

    func testStringFormatSupportsBoxedIntegerSpecifiers() {
        let boxedSigned = kk_box_long(Int(Int64.max))
        let boxedUnsigned = kk_box_long(Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max)))
        let args = makeRuntimeArray([boxedSigned, boxedUnsigned])

        let formatted = kk_string_format(rawFromRuntimeString("%d %x"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "9223372036854775807 ffffffffffffffff")
    }

    func testStringFormatSupportsBoxedScalarStringSpecifiers() {
        let args = makeRuntimeArray([
            kk_box_long(Int(Int64.max)),
            kk_box_float(Int(Float(1.5).bitPattern)),
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern))),
            kk_box_char(Int(Character("A").unicodeScalars.first?.value ?? 0)),
            kk_box_bool(1),
        ])

        let formatted = kk_string_format(rawFromRuntimeString("%s %s %s %s %s"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "9223372036854775807 1.5 2.5 A true")
    }

    func testStringFormatSupportsEscapedPercentWithoutArguments() {
        let formatted = kk_string_format(rawFromRuntimeString("progress=100%%"), kk_array_new(0))
        XCTAssertEqual(runtimeStringValue(formatted), "progress=100%")
    }

    func testStringFormatTreatsUnsupportedUnsignedConversionAsLiteral() {
        let args = makeRuntimeArray([7])
        let formatted = kk_string_format(rawFromRuntimeString("%u"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "%u")
    }

    func testStringFormatTreatsUnsupportedGroupingFlagsAsLiteral() {
        let args = makeRuntimeArray([1234])
        let formatted = kk_string_format(rawFromRuntimeString("%,d"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "%,d")
    }

    // MARK: - kk_throwable_new

    func testThrowableNewCreatesThrowable() {
        let msg = makeRuntimeString("error occurred")
        let throwable = kk_throwable_new(msg)
        XCTAssertNotNil(throwable)
        let output = capturePrintln { kk_println_any(throwable) }
        XCTAssertTrue(output.contains("error occurred"))
    }

    func testThrowableNewWithNilUsesDefaultMessage() {
        let throwable = kk_throwable_new(nil)
        XCTAssertNotNil(throwable)
        let output = capturePrintln { kk_println_any(throwable) }
        XCTAssertTrue(output.contains("Throwable"))
    }

    func testThrowableIsCancellationReturnsFalseForNil() {
        XCTAssertEqual(kk_throwable_is_cancellation(0), 0)
    }

    func testThrowableIsCancellationReturnsFalseForRegularThrowable() {
        let throwable = kk_throwable_new(makeRuntimeString("not cancellation"))
        let raw = Int(bitPattern: throwable)
        XCTAssertEqual(kk_throwable_is_cancellation(raw), 0)
    }

    // MARK: - kk_array_new

    func testArrayNewCreatesArray() {
        let array = kk_array_new(5)
        XCTAssertNotEqual(array, 0)
    }

    func testArrayNewZeroLengthCreatesEmptyArray() {
        let array = kk_array_new(0)
        XCTAssertNotEqual(array, 0)
    }

    // MARK: - kk_array_get / kk_array_set

    func testArraySetAndGetMultipleIndices() {
        let array = kk_array_new(3)
        var thrown = 0
        kk_array_set(array, 0, 10, &thrown)
        XCTAssertEqual(thrown, 0)
        kk_array_set(array, 1, 20, &thrown)
        XCTAssertEqual(thrown, 0)
        kk_array_set(array, 2, 30, &thrown)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(kk_array_get(array, 0, &thrown), 10)
        XCTAssertEqual(kk_array_get(array, 1, &thrown), 20)
        XCTAssertEqual(kk_array_get(array, 2, &thrown), 30)
    }

    func testArrayGetOutOfBoundsNegativeIndex() {
        let array = kk_array_new(2)
        var thrown = 0
        _ = kk_array_get(array, -1, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testArraySetOutOfBoundsThrows() {
        let array = kk_array_new(2)
        var thrown = 0
        _ = kk_array_set(array, 5, 99, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testArrayGetNullArrayThrows() {
        var thrown = 0
        _ = kk_array_get(0, 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testArraySetNullArrayThrows() {
        var thrown = 0
        _ = kk_array_set(0, 0, 42, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - kk_vararg_spread_concat

    func testVarargSpreadConcatSingleElements() {
        // pairs: [0, 10, 0, 20] means two scalar elements (marker=0)
        let pairs = kk_array_new(4)
        var thrown = 0
        kk_array_set(pairs, 0, 0, &thrown) // marker: scalar
        kk_array_set(pairs, 1, 10, &thrown) // value: 10
        kk_array_set(pairs, 2, 0, &thrown) // marker: scalar
        kk_array_set(pairs, 3, 20, &thrown) // value: 20

        let result = kk_vararg_spread_concat(pairs, 2)
        XCTAssertNotEqual(result, 0)

        XCTAssertEqual(kk_array_get(result, 0, &thrown), 10)
        XCTAssertEqual(kk_array_get(result, 1, &thrown), 20)
    }

    func testVarargSpreadConcatWithSpread() {
        // Create an inner array [100, 200]
        let inner = kk_array_new(2)
        var thrown = 0
        kk_array_set(inner, 0, 100, &thrown)
        kk_array_set(inner, 1, 200, &thrown)

        // pairs: [-1, innerRef, 0, 300] means spread + scalar
        let pairs = kk_array_new(4)
        kk_array_set(pairs, 0, -1, &thrown) // marker: spread
        kk_array_set(pairs, 1, inner, &thrown) // value: array ref
        kk_array_set(pairs, 2, 0, &thrown) // marker: scalar
        kk_array_set(pairs, 3, 300, &thrown) // value: 300

        let result = kk_vararg_spread_concat(pairs, 2)
        XCTAssertEqual(kk_array_get(result, 0, &thrown), 100)
        XCTAssertEqual(kk_array_get(result, 1, &thrown), 200)
        XCTAssertEqual(kk_array_get(result, 2, &thrown), 300)
    }

    func testVarargSpreadConcatEmptyPairsReturnsEmptyArray() {
        let result = kk_vararg_spread_concat(0, 0)
        // pairCount is 0, should return empty array
        XCTAssertNotEqual(result, 0)
    }

    // MARK: - kk_println_any with boxed values

    func testPrintlnBoxedInt() {
        let boxed = kk_box_int(42)
        let ptr = UnsafeMutableRawPointer(bitPattern: boxed)
        let output = capturePrintln { kk_println_any(ptr) }
        XCTAssertEqual(output, "42")
    }

    func testPrintlnBoxedBoolTrue() {
        let boxed = kk_box_bool(1)
        let ptr = UnsafeMutableRawPointer(bitPattern: boxed)
        let output = capturePrintln { kk_println_any(ptr) }
        XCTAssertEqual(output, "true")
    }

    func testPrintlnBoxedBoolFalse() {
        let boxed = kk_box_bool(0)
        let ptr = UnsafeMutableRawPointer(bitPattern: boxed)
        let output = capturePrintln { kk_println_any(ptr) }
        XCTAssertEqual(output, "false")
    }

    func testPrintlnBoxedString() {
        let str = makeRuntimeString("hello world")
        let output = capturePrintln { kk_println_any(str) }
        XCTAssertEqual(output, "hello world")
    }

    func testPrintlnThrowable() {
        let msg = makeRuntimeString("some error")
        let throwable = kk_throwable_new(msg)
        let output = capturePrintln { kk_println_any(throwable) }
        XCTAssertTrue(output.contains("some error"))
    }

    // MARK: - Helpers

    private func makeRuntimeString(_ value: String) -> UnsafeMutableRawPointer {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                kk_string_from_utf8(ptr, Int32(value.utf8.count))
            }
        }
    }

    private func rawFromRuntimeString(_ value: String) -> Int {
        Int(bitPattern: makeRuntimeString(value))
    }

    private func makeRuntimeArray(_ values: [Int]) -> Int {
        let array = kk_array_new(values.count)
        var thrown = 0
        for (index, value) in values.enumerated() {
            kk_array_set(array, index, value, &thrown)
            XCTAssertEqual(thrown, 0)
        }
        return array
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
