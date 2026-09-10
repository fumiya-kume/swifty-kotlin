#if canImport(Testing)
import Testing
@testable import Runtime

@Suite(.serialized)
struct RuntimeStringBuilderTests {
    @Test
    func testBridgeCreatesAppendsAndRendersStringBuilder() {
        let builder = __kk_string_builder_new()
        let returned = __kk_string_builder_append_obj(builder, makeRuntimeString("hello"))

        #expect(returned == builder)
        #expect(__kk_string_builder_length_prop(builder) == 5)
        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "hello")
    }

    // KSP-817: runtime-backed CharSequence values must expose the same method
    // and property slots as source-defined implementations.
    @Test
    func testCharSequenceItableRegistrationForRuntimeObjects() {
        let builder = makeBuilder("abc")
        let string = makeRuntimeString("hello")
        let interfaceTypeID = Int(runtimeStableNominalTypeID(fqName: "kotlin.CharSequence"))
        let getRaw = kk_itable_lookup_dynamic(builder, interfaceTypeID, 0)
        let stringGetRaw = kk_itable_lookup_dynamic(string, interfaceTypeID, 0)
        let subSequenceRaw = kk_itable_lookup_dynamic(builder, interfaceTypeID, 1)
        let stringSubSequenceRaw = kk_itable_lookup_dynamic(string, interfaceTypeID, 1)
        let lengthRaw = kk_itable_lookup_dynamic(builder, interfaceTypeID, 2)
        let stringLengthRaw = kk_itable_lookup_dynamic(string, interfaceTypeID, 2)

        #expect(getRaw != 0)
        #expect(stringGetRaw != 0)
        #expect(subSequenceRaw != 0)
        #expect(stringSubSequenceRaw != 0)
        #expect(lengthRaw != 0)
        #expect(stringLengthRaw != 0)

        let get = unsafeBitCast(
            getRaw,
            to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var getThrown = 0
        #expect(get(builder, 1, &getThrown) == 98)
        #expect(getThrown == 0)

        let length = unsafeBitCast(
            lengthRaw,
            to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var lengthThrown = 0
        #expect(length(builder, &lengthThrown) == 3)
        #expect(lengthThrown == 0)

        let subSequence = unsafeBitCast(
            subSequenceRaw,
            to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var subSequenceThrown = 0
        let suffix = subSequence(builder, 1, 3, &subSequenceThrown)
        #expect(subSequenceThrown == 0)
        #expect(runtimeStringValue(suffix) == "bc")

        let stringSubSequence = unsafeBitCast(
            stringSubSequenceRaw,
            to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var stringSubSequenceThrown = 0
        let stringSuffix = stringSubSequence(string, 1, 5, &stringSubSequenceThrown)
        #expect(stringSubSequenceThrown == 0)
        #expect(runtimeStringValue(stringSuffix) == "ello")

        let empty = makeRuntimeString("")
        var emptyLengthThrown = 0
        #expect(length(empty, &emptyLengthThrown) == 0)
        #expect(emptyLengthThrown == 0)
        var emptySubSequenceThrown = 0
        let emptySubSequence = subSequence(empty, 0, 0, &emptySubSequenceThrown)
        #expect(emptySubSequenceThrown == 0)
        #expect(runtimeStringValue(emptySubSequence) == "")

        var invalidRangeThrown = 0
        _ = subSequence(string, 2, 1, &invalidRangeThrown)
        #expect(invalidRangeThrown != 0)

        let emojiBuilder = makeBuilder("🥦")
        let emojiString = makeRuntimeString("🥦")
        var emojiBuilderGetThrown = 0
        var emojiStringGetThrown = 0
        #expect(get(emojiBuilder, 0, &emojiBuilderGetThrown) == 55358)
        #expect(get(emojiBuilder, 1, &emojiBuilderGetThrown) == 56678)
        #expect(get(emojiString, 0, &emojiStringGetThrown) == 55358)
        #expect(get(emojiString, 1, &emojiStringGetThrown) == 56678)
        #expect(emojiBuilderGetThrown == 0)
        #expect(emojiStringGetThrown == 0)
    }

    // KSP-817: temporary String boxes created through the low-level UTF-8
    // constructor must also participate in CharSequence.length dispatch.
    @Test
    func testUTF8StringConstructorRegistersCharSequenceItable() {
        let bytes = Array("window".utf8)
        let raw = bytes.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
        let interfaceTypeID = Int(runtimeStableNominalTypeID(fqName: "kotlin.CharSequence"))
        let getterRaw = kk_itable_lookup_dynamic(raw, interfaceTypeID, 2)

        #expect(getterRaw != 0)

        let getter = unsafeBitCast(
            getterRaw,
            to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var thrown = 0
        #expect(getter(raw, &thrown) == 6)
        #expect(thrown == 0)
    }

    @Test
    func testFlatConstructorAndFlatAppendUseFlattenedStringFields() {
        let builder = withFlatString("ab") { data, length, byteCount, hash in
            __kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }

        let returned = withFlatString("cd") { data, length, byteCount, hash in
            __kk_string_builder_append_obj_flat(builder, data, length, byteCount, hash)
        }

        #expect(returned == builder)
        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "abcd")
    }

    @Test
    func testClearResetsMutableBufferAndReturnsReceiver() {
        let builder = makeBuilder("abc")

        let returned = __kk_string_builder_clear(builder)

        #expect(returned == builder)
        #expect(__kk_string_builder_length_prop(builder) == 0)
        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "")
    }

    @Test
    func testAppendObjAcceptsStringRepresentations() {
        let builder = __kk_string_builder_new()

        _ = __kk_string_builder_append_obj(builder, makeRuntimeString("A"))
        _ = __kk_string_builder_append_obj(builder, makeRuntimeString("B"))

        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "AB")
    }

    private func makeRuntimeString(_ value: String) -> Int {
        registerRuntimeObject(RuntimeStringBox(value))
    }

    private func makeBuilder(_ value: String) -> Int {
        withFlatString(value) { data, length, byteCount, hash in
            __kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }
    }

    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(value.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, value.unicodeScalars.count, value.utf8.count, 0)
        }
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
#endif
