#if canImport(Testing)
@testable import Runtime
import Testing

// STDLIB-004: Boundary and element-correctness tests for primitive arrays.
// These tests exercise the shared RuntimeArrayBox ABI at the level of actual
// element types (Int, Boolean, Char, Double, Long) and verify the thrown-
// channel protocol for out-of-bounds accesses.
@Suite
struct RuntimePrimitiveArrayElementTests {

    // MARK: - Int elements

    @Test
    func testIntArrayStoresAndRetrievesBoxedIntegers() {
        let array = kk_array_new(3)
        var thrown = 0

        let boxed42 = kk_box_int(42)
        let boxedNeg = kk_box_int(-100)

        #expect(kk_array_set(array, 0, boxed42, &thrown) == boxed42)
        #expect(thrown == 0)

        #expect(kk_array_set(array, 2, boxedNeg, &thrown) == boxedNeg)
        #expect(thrown == 0)

        let got0 = kk_array_get(array, 0, &thrown)
        #expect(thrown == 0)
        #expect(kk_unbox_int(got0) == 42)

        let got2 = kk_array_get(array, 2, &thrown)
        #expect(thrown == 0)
        #expect(kk_unbox_int(got2) == -100)
    }

    @Test
    func testIntArrayZeroInitializedAfterKkArrayNew() {
        let array = kk_array_new(4)
        for i in 0 ..< 4 {
            var thrown = 0
            let got = kk_array_get(array, i, &thrown)
            #expect(thrown == 0)
            // kk_array_new zero-fills slots; the raw value stored is 0.
            #expect(got == 0, "slot \(i) should be zero after kk_array_new")
        }
    }

    // MARK: - Boolean elements

    @Test
    func testBooleanArrayStoresTrueAndFalse() {
        let array = kk_array_new(2)
        var thrown = 0

        let trueBoxed = kk_box_bool(1)
        let falseBoxed = kk_box_bool(0)

        #expect(kk_array_set(array, 0, trueBoxed, &thrown) == trueBoxed)
        #expect(kk_array_set(array, 1, falseBoxed, &thrown) == falseBoxed)

        let got0 = kk_array_get(array, 0, &thrown)
        #expect(thrown == 0)
        #expect(kk_unbox_bool(got0) != 0, "element 0 should be true")

        let got1 = kk_array_get(array, 1, &thrown)
        #expect(thrown == 0)
        #expect(kk_unbox_bool(got1) == 0, "element 1 should be false")
    }

    // MARK: - Char elements

    @Test
    func testCharArrayPreservesUnicodeCodepoints() {
        let array = kk_array_new(3)
        var thrown = 0

        // 'A' = 65, 'Z' = 90, U+1F600 = 128512 (emoji)
        let charA = kk_box_char(65)
        let charZ = kk_box_char(90)
        let charEmoji = kk_box_char(128512)

        #expect(kk_array_set(array, 0, charA, &thrown) == charA)
        #expect(kk_array_set(array, 1, charZ, &thrown) == charZ)
        #expect(kk_array_set(array, 2, charEmoji, &thrown) == charEmoji)

        #expect(kk_unbox_char(kk_array_get(array, 0, &thrown)) == 65)
        #expect(thrown == 0)
        #expect(kk_unbox_char(kk_array_get(array, 1, &thrown)) == 90)
        #expect(kk_unbox_char(kk_array_get(array, 2, &thrown)) == 128512)
    }

    // MARK: - Double elements

    @Test
    func testDoubleArrayPreservesBitPattern() {
        let array = kk_array_new(2)
        var thrown = 0

        // Pass Double values as their bit-pattern integers; this mirrors how
        // the compiled Kotlin path uses kk_box_double / kk_unbox_double.
        let piInt = Int(bitPattern: UInt(Double.pi.bitPattern))
        let e = 2.718281828459045
        let eInt = Int(bitPattern: UInt(e.bitPattern))

        let boxedPi = kk_box_double(piInt)
        let boxedE = kk_box_double(eInt)

        #expect(kk_array_set(array, 0, boxedPi, &thrown) == boxedPi)
        #expect(kk_array_set(array, 1, boxedE, &thrown) == boxedE)

        let gotPi = kk_unbox_double(kk_array_get(array, 0, &thrown))
        #expect(thrown == 0)
        // Compare bit patterns to avoid floating-point comparison issues.
        #expect(
            gotPi == piInt,
            "Double bit-pattern must survive round-trip through array"
        )

        let gotE = kk_unbox_double(kk_array_get(array, 1, &thrown))
        #expect(gotE == eInt)
    }

    @Test
    func testCheckedDoubleArrayAllocationPreservesConstructorContract() throws {
        var thrown = 0
        let array = kk_array_new_checked(3, &thrown)

        #expect(thrown == 0)
        for index in 0 ..< 3 {
            #expect(kk_array_get(array, index, &thrown) == 0)
            #expect(thrown == 0)
        }

        var negativeThrown = 0
        let negative = kk_array_new_checked(-1, &negativeThrown)

        #expect(negative == 0)
        #expect(negativeThrown != 0)
        let ptr = try #require(
            UnsafeMutableRawPointer(bitPattern: negativeThrown),
            "negative allocation must return a throwable"
        )
        let box = try #require(
            tryCast(ptr, to: RuntimeThrowableBox.self),
            "negative allocation must return a RuntimeThrowableBox"
        )
        #expect(
            box.exceptionHierarchyFQNames.contains("kotlin.NegativeArraySizeException"),
            "negative allocation must throw NegativeArraySizeException"
        )
    }

    // MARK: - Long elements

    @Test
    func testLongArrayPreservesLargeSignedValues() {
        let array = kk_array_new(3)
        var thrown = 0

        let minLong = kk_box_long(Int.min)
        let maxLong = kk_box_long(Int.max)
        let negOne = kk_box_long(-1)

        #expect(kk_array_set(array, 0, minLong, &thrown) == minLong)
        #expect(kk_array_set(array, 1, maxLong, &thrown) == maxLong)
        #expect(kk_array_set(array, 2, negOne, &thrown) == negOne)

        #expect(kk_unbox_long(kk_array_get(array, 0, &thrown)) == Int.min)
        #expect(thrown == 0)
        #expect(kk_unbox_long(kk_array_get(array, 1, &thrown)) == Int.max)
        #expect(kk_unbox_long(kk_array_get(array, 2, &thrown)) == -1)
    }

    // MARK: - Boundary behaviour

    @Test
    func testReadNegativeIndexSetsThrown() {
        let array = kk_array_new(3)
        var thrown = 0

        _ = kk_array_get(array, -1, &thrown)

        #expect(thrown != 0, "negative index must set the thrown channel")
    }

    @Test
    func testReadIndexEqualToSizeSetsThrown() {
        let size = 5
        let array = kk_array_new(size)
        var thrown = 0

        _ = kk_array_get(array, size, &thrown)

        #expect(thrown != 0, "index == size must set the thrown channel (one past end)")
    }

    @Test
    func testReadIndexFarBeyondSizeSetsThrown() {
        let array = kk_array_new(2)
        var thrown = 0

        _ = kk_array_get(array, 1000, &thrown)

        #expect(thrown != 0, "large out-of-bounds index must set the thrown channel")
    }

    @Test
    func testWriteOutOfBoundsSetsThrown() {
        let array = kk_array_new(2)
        var thrown = 0

        _ = kk_array_set(array, 2, kk_box_int(99), &thrown)

        #expect(thrown != 0, "out-of-bounds write must set the thrown channel")
    }

    @Test
    func testThrownExceptionIsArrayIndexOutOfBounds() throws {
        let array = kk_array_new(1)
        var thrown = 0

        _ = kk_array_get(array, 5, &thrown)

        #expect(thrown != 0)
        let ptr = try #require(
            UnsafeMutableRawPointer(bitPattern: thrown),
            "thrown channel value is not a valid pointer"
        )
        let box = try #require(
            tryCast(ptr, to: RuntimeThrowableBox.self),
            "thrown value must be a RuntimeThrowableBox"
        )
        #expect(
            box.exceptionHierarchyFQNames.contains("kotlin.ArrayIndexOutOfBoundsException"),
            "thrown exception must be kotlin.ArrayIndexOutOfBoundsException; got: \(box.exceptionFQName)"
        )
    }

    // MARK: - In-bounds reads do not set thrown

    @Test
    func testInBoundsAccessClearsThrownChannel() {
        let array = kk_array_new(3)
        var thrown = 99  // pre-set to a non-zero value

        _ = kk_array_set(array, 1, kk_box_int(7), &thrown)
        #expect(thrown == 0, "in-bounds set must clear the thrown channel")

        _ = kk_array_get(array, 1, &thrown)
        #expect(thrown == 0, "in-bounds get must clear the thrown channel")
    }
}
#endif
