#if canImport(Testing)
@testable import Runtime
import Testing

// Expected values below are cross-checked against real kotlinc/JVM output
// (BUG-230): Long/ULong.hashCode() is `(this xor (this ushr 32)).toInt()`,
// Double.hashCode() folds the same way over its IEEE 754 bit pattern, and
// Float.hashCode() is the sign-extended IEEE 754 bit pattern.
@Suite
struct RuntimeNumericHashCodeTests {
    // MARK: - Unboxed (statically-typed, non-Any receiver) dispatch

    @Test
    func testUnboxedLongHashCode() {
        #expect(kk_any_hashCode(1_099_511_627_776, 8) == 256) // 1L shl 40
        #expect(kk_any_hashCode(-5, 8) == 4)
        #expect(kk_any_hashCode(0, 8) == 0)
        #expect(kk_any_hashCode(-1, 8) == 0)
        #expect(kk_any_hashCode(Int(Int64.max), 8) == -2_147_483_648) // Long.MAX_VALUE
    }

    @Test
    func testUnboxedDoubleHashCode() {
        #expect(kk_any_hashCode(kk_double_to_bits(1.5), 6) == 1_073_217_536)
        #expect(kk_any_hashCode(kk_double_to_bits(-2.5), 6) == -1_073_479_680)
        #expect(kk_any_hashCode(kk_double_to_bits(0.0), 6) == 0)
        #expect(kk_any_hashCode(kk_double_to_bits(Double.nan), 6) == 2_146_959_360)
    }

    @Test
    func testUnboxedFloatHashCode() {
        #expect(kk_any_hashCode(kk_float_to_bits(-2.5), 5) == -1_071_644_672)
        #expect(kk_any_hashCode(kk_float_to_bits(0.0), 5) == 0)
        #expect(kk_any_hashCode(kk_float_to_bits(-0.0), 5) == -2_147_483_648)
        #expect(kk_any_hashCode(kk_float_to_bits(Float.nan), 5) == 2_143_289_344)
    }

    @Test
    func testUnboxedULongHashCode() {
        #expect(kk_any_hashCode(1_099_511_627_776, 7) == 256) // 1UL shl 40
        #expect(kk_any_hashCode(Int(bitPattern: UInt.max), 7) == 0) // ULong.MAX_VALUE
    }

    // MARK: - Boxed (Any-erased receiver) dispatch

    @Test
    func testBoxedLongHashCode() {
        let shifted = registerRuntimeObject(RuntimeLongBox(1_099_511_627_776))
        #expect(kk_any_hashCode(shifted, 0) == 256)

        // A boxed Long is a heap pointer, not the raw value, so it never
        // collides with runtimeNullSentinelInt the way the unboxed slot does.
        let minValue = registerRuntimeObject(RuntimeLongBox(Int(Int64.min)))
        #expect(minValue != runtimeNullSentinelInt)
        #expect(kk_any_hashCode(minValue, 0) == -2_147_483_648)
    }

    @Test
    func testBoxedULongHashCode() {
        let shifted = registerRuntimeObject(RuntimeULongBox(1_099_511_627_776))
        #expect(kk_any_hashCode(shifted, 0) == 256)

        let signBit = registerRuntimeObject(RuntimeULongBox(Int(Int64.min))) // 2^63
        #expect(kk_any_hashCode(signBit, 0) == -2_147_483_648)
    }

    @Test
    func testBoxedFloatHashCode() {
        let negative = registerRuntimeObject(RuntimeFloatBox(-2.5))
        #expect(kk_any_hashCode(negative, 0) == -1_071_644_672)

        let nan = registerRuntimeObject(RuntimeFloatBox(Float.nan))
        #expect(kk_any_hashCode(nan, 0) == 2_143_289_344)
    }

    @Test
    func testBoxedDoubleHashCode() {
        let positive = registerRuntimeObject(RuntimeDoubleBox(1.5))
        #expect(kk_any_hashCode(positive, 0) == 1_073_217_536)

        // A boxed Double also sidesteps the null-sentinel collision that
        // -0.0 hits when unboxed (its bit pattern equals Int.min).
        let negativeZero = registerRuntimeObject(RuntimeDoubleBox(-0.0))
        #expect(negativeZero != runtimeNullSentinelInt)
        #expect(kk_any_hashCode(negativeZero, 0) == -2_147_483_648)
    }

    @Test
    func testDataClassObjectHashCodeUsesTypedFieldsAnd32BitFolding() {
        let classID = 0x51_232
        _ = kk_runtime_register_data_class(classID)
        let object = kk_object_new(6, classID)

        _ = kk_array_set_typed(object, 2, 1_099_511_627_776, 8) // Long: 1L shl 40
        _ = kk_array_set_typed(object, 3, kk_float_to_bits(-2.5), 5)
        _ = kk_array_set_typed(object, 4, kk_double_to_bits(-2.5), 6)
        _ = kk_array_set_typed(object, 5, 1_099_511_627_776, 7) // ULong: 1uL shl 40

        // The two header slots are excluded, and every combine step wraps as
        // Kotlin Int rather than accumulating in the host Int width.
        #expect(kk_any_hashCode(object, 0) == 2_031_116_288)

        _ = kk_array_set(object, 2, 1_099_511_627_776, nil)
        #expect(kk_any_hashCode(object, 0) == 2_031_116_288)
    }

    // MARK: - List/Set/Map (structural hash over boxed elements)

    @Test
    func testListHashCode() {
        // A generic List<Long> element is boxed (like Any-erasure), so this
        // also exercises the boxed-Long branch through the recursive
        // kk_any_hashCode(element, 0) call.
        let longElement = registerRuntimeObject(RuntimeLongBox(1_099_511_627_776)) // 1L shl 40
        let single = registerRuntimeObject(RuntimeListBox(elements: [longElement]))
        #expect(kk_any_hashCode(single, 0) == 287) // 31*1 + 256

        // 10 elements is long enough that Kotlin's 32-bit-wrapping
        // fold(1) { acc, e -> 31*acc + e.hashCode() } wraps mid-fold; an
        // accumulator that wraps only at 64 bits would diverge here.
        let ints = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
        #expect(kk_any_hashCode(ints, 0) == -975_991_962)
    }

    @Test
    func testSetHashCode() {
        let a = registerRuntimeObject(RuntimeFloatBox(-2.5))
        let b = registerRuntimeObject(RuntimeDoubleBox(1.5))
        let set = registerRuntimeObject(RuntimeSetBox(elements: [a, b]))
        #expect(kk_any_hashCode(set, 0) == 1_572_864) // -1071644672 + 1073217536

        let ints = registerRuntimeObject(RuntimeSetBox(elements: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
        #expect(kk_any_hashCode(ints, 0) == 55) // sum, no overflow at this size
    }

    @Test
    func testMapHashCode() {
        let key = registerRuntimeObject(RuntimeStringBox("k"))
        let value = registerRuntimeObject(RuntimeLongBox(1_099_511_627_776)) // 1L shl 40
        let map = registerRuntimeObject(RuntimeMapBox(keys: [key], values: [value]))
        #expect(kk_any_hashCode(map, 0) == 363) // "k".hashCode() (107) xor 256
    }
}
#endif
