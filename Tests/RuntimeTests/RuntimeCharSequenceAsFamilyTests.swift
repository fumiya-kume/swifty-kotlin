#if canImport(Testing)
import Testing
@testable import Runtime

private let ksp1365IteratorHasNextThunk: @convention(c) (
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    return 1
}

private let ksp1365IteratorNextThunk: @convention(c) (
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, outThrown in
    outThrown?.pointee = 0
    return 0x61
}

private let ksp1365ThrowingIteratorNextThunk: @convention(c) (
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "iterator failure")
    return 0x61
}

@Suite(.serialized)
struct RuntimeCharSequenceAsFamilyTests {
    @Test
    func testGenericIteratorNextBoxesSourceCharIteratorValue() {
        let typeID = runtimeStableNominalTypeID(fqName: "kotlin.text.CharSequenceCharIterator")
        let iterator = RuntimeObjectBox(length: 0, classID: typeID)
        let iteratorRaw = registerRuntimeObject(iterator)
        runtimeRegisterObjectType(rawValue: iteratorRaw, classID: typeID)
        registerIteratorItable(
            raw: iteratorRaw,
            hasNext: ksp1365IteratorHasNextThunk,
            next: ksp1365IteratorNextThunk
        )

        let next = kk_iterator_next(iteratorRaw)

        #expect(next != 0x61)
        #expect(kk_unbox_char(next) == 0x61)
    }

    @Test
    func testGenericIteratorNextDoesNotBoxFailureSentinel() {
        let typeID = runtimeStableNominalTypeID(fqName: "kotlin.text.CharSequenceCharIterator")
        let iterator = RuntimeObjectBox(length: 0, classID: typeID)
        let iteratorRaw = registerRuntimeObject(iterator)
        runtimeRegisterObjectType(rawValue: iteratorRaw, classID: typeID)
        registerIteratorItable(
            raw: iteratorRaw,
            hasNext: ksp1365IteratorHasNextThunk,
            next: ksp1365ThrowingIteratorNextThunk
        )

        var thrown = 0
        let next = kk_iterator_next(iteratorRaw, &thrown)

        #expect(next == 0)
        #expect(thrown != 0)
    }
}
#endif
