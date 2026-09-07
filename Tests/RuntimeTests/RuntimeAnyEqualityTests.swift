#if canImport(Testing)
@testable import Runtime
import Testing

private let runtimeAnyEqualityOverride: @convention(c) (
    Int,
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { lhs, rhs, outThrown in
    outThrown?.pointee = 0
    return kk_array_get(lhs, 0, nil) == kk_array_get(rhs, 0, nil) ? 1 : 0
}

@Suite
struct RuntimeAnyEqualityTests {
    private func boolValue(_ raw: Int) -> Bool {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(pointer, to: RuntimeBoolBox.self)
        else {
            return false
        }
        return box.value
    }

    @Test
    func testUnregisteredRuntimeObjectUsesReferenceIdentity() {
        let classID = 0x51_11
        let first = kk_object_new(1, classID)
        let second = kk_object_new(1, classID)
        _ = kk_array_set(first, 0, 7, nil)
        _ = kk_array_set(second, 0, 7, nil)

        #expect(boolValue(kk_any_equals(first, 0, first, 0)))
        #expect(!boolValue(kk_any_equals(first, 0, second, 0)))
    }

    @Test
    func testRegisteredDataClassKeepsStructuralEquality() {
        let classID = 0x51_12
        _ = kk_runtime_register_data_class(classID)
        let first = kk_object_new(1, classID)
        let second = kk_object_new(1, classID)
        _ = kk_array_set(first, 0, 7, nil)
        _ = kk_array_set(second, 0, 7, nil)

        #expect(boolValue(kk_any_equals(first, 0, second, 0)))

        _ = kk_array_set(second, 0, 8, nil)
        #expect(!boolValue(kk_any_equals(first, 0, second, 0)))
    }

    @Test
    func testRegisteredEqualsOverrideWinsAfterTypeErasure() {
        let classID = 0x51_13
        let first = kk_object_new(2, classID)
        let second = kk_object_new(2, classID)
        _ = kk_array_set(first, 0, 7, nil)
        _ = kk_array_set(first, 1, 1, nil)
        _ = kk_array_set(second, 0, 7, nil)
        _ = kk_array_set(second, 1, 2, nil)
        _ = kk_object_register_equals_override(
            first,
            unsafeBitCast(runtimeAnyEqualityOverride, to: Int.self)
        )

        #expect(boolValue(kk_any_equals(first, 0, second, 0)))
        #expect(kk_structural_eq(first, second) == 1)
    }

    // Tuples allocated for Kotlin's `Pair`/`Triple` carry a nominal type ID, so
    // they compare and hash by their components even when they reach the
    // runtime through `Any` (set membership, map keys) rather than the Kotlin
    // `equals` written in `Tuples.kt`.
    @Test
    func testTaggedPairAndTripleCompareAndHashStructurally() {
        let first = kk_pair_new(1, 2)
        let second = kk_pair_new(1, 2)
        let different = kk_pair_new(1, 3)

        #expect(boolValue(kk_any_equals(first, 0, second, 0)))
        #expect(!boolValue(kk_any_equals(first, 0, different, 0)))
        #expect(kk_any_hashCode(first, 0) == kk_any_hashCode(second, 0))

        let triple = kk_triple_new(1, 2, 3)
        let sameTriple = kk_triple_new(1, 2, 3)
        let otherTriple = kk_triple_new(1, 2, 4)

        #expect(boolValue(kk_any_equals(triple, 0, sameTriple, 0)))
        #expect(!boolValue(kk_any_equals(triple, 0, otherTriple, 0)))
        #expect(kk_any_hashCode(triple, 0) == kk_any_hashCode(sameTriple, 0))

        #expect(!boolValue(kk_any_equals(first, 0, triple, 0)))
    }

    // Pairs the runtime allocates for its own plumbing (comparator pairs and
    // the like) stay untagged and keep reference identity, so they never look
    // like a Kotlin `Pair` to `is`/`==`.
    @Test
    func testUntaggedRuntimePairKeepsReferenceIdentity() {
        let first = registerRuntimeObject(RuntimePairBox(first: 1, second: 2))
        let second = registerRuntimeObject(RuntimePairBox(first: 1, second: 2))

        #expect(boolValue(kk_any_equals(first, 0, first, 0)))
        #expect(!boolValue(kk_any_equals(first, 0, second, 0)))
    }
}
#endif
