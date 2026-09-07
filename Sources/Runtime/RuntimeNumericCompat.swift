
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@_cdecl("kk_any_to_string")
public func kk_any_to_string(_ value: Int, _ tag: Int) -> UnsafeMutableRawPointer {
    let tag = Int32(truncatingIfNeeded: tag)
    if runtimeIsUnitBox(value) {
        return runtimeMakeStringPointer("kotlin.Unit")
    }
    // Float/Double/ULong MUST be decoded before the null-sentinel check:
    // -0.0 (Double) has bit pattern 0x8000000000000000 == Int.min == runtimeNullSentinelInt,
    // and a ULong of exactly 2^63 has the identical raw bit pattern. Elevating
    // tags 5/6/7 preserves the sign bit of negative zero/NaN payloads and the
    // top bit of large ULong values instead of misreading them as null.
    if tag == 5 {
        return runtimeMakeStringPointer(runtimeFormatFloatingPoint(runtimeTaggedFloatValue(value)))
    }
    if tag == 6 {
        return runtimeMakeStringPointer(runtimeFormatFloatingPoint(runtimeTaggedDoubleValue(value)))
    }
    if tag == 7 {
        return runtimeMakeStringPointer(String(runtimeTaggedULongValue(value)))
    }
    if value == runtimeNullSentinelInt {
        return runtimeMakeStringPointer("null")
    }
    if tag == 2 {
        return runtimeMakeStringPointer(value != 0 ? "true" : "false")
    }
    if tag == 4 {
        let rendered = runtimeRenderTaggedChar(value)
        return runtimeMakeStringPointer(rendered)
    }
    if tag == 3,
       let pointer = UnsafeMutableRawPointer(bitPattern: value),
       extractString(from: pointer) != nil
    {
        return pointer
    }
    return runtimeMakeStringPointer(runtimeElementToString(value))
}

/// Nullable-aware variant of `kk_any_to_string`, for call sites that know
/// their *static* type is nullable but cannot safely add KIR-level branching
/// to guard tags 5/6/7 (Float?/Double?/ULong?) the way
/// `CallLowerer.emitAnyToStringWithNullGuard` does (e.g.
/// `OperatorLoweringPass.appendStringConversion`, which rewrites
/// already-lowered function bodies where introducing fresh label numbers
/// risks colliding with labels assigned during the earlier lowering phase).
///
/// For tags 5/6/7, a genuinely-null value is always represented as the raw
/// sentinel (never boxed), while a real non-null value of these tags is
/// *always* boxed (RuntimeFloatBox/RuntimeDoubleBox/RuntimeLongBox) — the
/// field/slot needs a representation for "null" distinct from every in-range
/// value, including ones that share the sentinel's bit pattern (-0.0, or a
/// ULong of exactly 2^63), so the ABI boxes any such value. That makes
/// "is this boxed" a safe, purely-runtime way to disambiguate a real value
/// from null — no compile-time knowledge of the specific value is needed,
/// only that the *type* is nullable, which the caller already guarantees by
/// choosing to call this entry point instead of `kk_any_to_string`. (For a
/// *non-nullable* tag-5/6/7 value this distinction would be unsafe — such a
/// value is never boxed even when in range, so callers must only use this
/// for genuinely nullable-typed values.) Other tags have no such ambiguity,
/// so this just forwards to `kk_any_to_string`.
@_cdecl("kk_any_to_string_nullable")
public func kk_any_to_string_nullable(_ value: Int, _ tag: Int) -> UnsafeMutableRawPointer {
    let tag32 = Int32(truncatingIfNeeded: tag)
    guard tag32 == 5 || tag32 == 6 || tag32 == 7 else {
        return kk_any_to_string(value, tag)
    }
    if let ptr = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObjectPointer {
            return kk_any_to_string(value, tag)
        }
    }
    if value == runtimeNullSentinelInt {
        return runtimeMakeStringPointer("null")
    }
    return kk_any_to_string(value, tag)
}

private func runtimeRenderTaggedChar(_ value: Int) -> String {
    if let ptr = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObjectPointer, let charBox = tryCast(ptr, to: RuntimeCharBox.self) {
            return UnicodeScalar(charBox.value).map(String.init) ?? "?"
        }
    }
    return UnicodeScalar(value).map(String.init) ?? "?"
}

private func runtimeTaggedFloatValue(_ value: Int) -> Float {
    if let ptr = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObjectPointer, let floatBox = tryCast(ptr, to: RuntimeFloatBox.self) {
            return floatBox.value
        }
    }
    return kk_bits_to_float(value)
}

private func runtimeTaggedDoubleValue(_ value: Int) -> Double {
    if let ptr = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObjectPointer, let doubleBox = tryCast(ptr, to: RuntimeDoubleBox.self) {
            return doubleBox.value
        }
    }
    return kk_bits_to_double(value)
}

/// This mirrors runtimeTaggedFloatValue/runtimeTaggedDoubleValue: unbox first
/// when the raw value is a GC-tracked object pointer (e.g. a nullable ULong?
/// data class property, which the ABI always boxes so its field slot can
/// also represent null), otherwise reinterpret the raw bits.
private func runtimeTaggedULongValue(_ value: Int) -> UInt {
    if let ptr = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObjectPointer, let ulongBox = tryCast(ptr, to: RuntimeULongBox.self) {
            return UInt(bitPattern: ulongBox.value)
        }
        if isObjectPointer, let longBox = tryCast(ptr, to: RuntimeLongBox.self) {
            return UInt(bitPattern: longBox.value)
        }
    }
    return UInt(bitPattern: value)
}

private func runtimeStringHashCode(_ value: String) -> Int {
    value.unicodeScalars.reduce(0) { partial, scalar in
        31 &* partial &+ Int(Int32(bitPattern: scalar.value))
    }
}

/// `(this xor (this ushr 32)).toInt()` — the formula behind Long/ULong/Double
/// `.hashCode()`, applied to the value's full 64-bit bit pattern. A Swift
/// arithmetic `>>` sign-extends instead of Kotlin's logical `ushr`, but the
/// extra high bits it introduces only ever land in the upper 32 bits of the
/// XOR — which `Int32(truncatingIfNeeded:)` below discards — so the two
/// shifts agree on the low 32 bits for every input (verified against
/// kotlinc for Long.MIN_VALUE/MAX_VALUE, -1, -5, and -2.5's Double bits).
private func runtimeXorFoldHashCode(_ bits: Int64) -> Int {
    Int(Int32(truncatingIfNeeded: bits ^ (bits >> 32)))
}

/// Float.hashCode(): the sign-extended IEEE 754 bit pattern, canonicalizing
/// NaN the way `floatToIntBits`/`__kk_float_toBits` do. `kk_float_to_bits` is
/// the wrong helper for this: it's a zero-extending bit-transport encoding
/// for the ABI boundary, not the sign-extended `Int` that Kotlin's
/// Float.hashCode()/toBits() expose.
private func runtimeFloatHashCode(_ value: Float) -> Int {
    if value.isNaN {
        return Int(Int32(bitPattern: 0x7FC0_0000 as UInt32))
    }
    return Int(Int32(bitPattern: value.bitPattern))
}

/// Unboxed (raw, non-pointer) `Any.hashCode()` fallback. Tags 5/6/7/8
/// (Float/Double/ULong/Long) need their raw slot value reinterpreted per
/// Kotlin's formula; every other tag's raw slot value already equals its
/// hashCode as-is (Int, Char), or is handled here directly (Boolean).
private func runtimeUnboxedAnyHashCode(_ value: Int, _ tag: Int32) -> Int {
    switch tag {
    case 2:
        return value != 0 ? 1231 : 1237
    case 5:
        return runtimeFloatHashCode(kk_bits_to_float(value))
    case 6, 7, 8:
        return runtimeXorFoldHashCode(Int64(value))
    default:
        return value
    }
}

private func runtimeAnyHashCode(_ value: Int, _ tag: Int32) -> Int {
    if value == runtimeNullSentinelInt {
        return 0
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: value) else {
        return runtimeUnboxedAnyHashCode(value, tag)
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return runtimeUnboxedAnyHashCode(value, tag)
    }
    if let stringBox = tryCast(pointer, to: RuntimeStringBox.self) {
        return runtimeStringHashCode(stringBox.value)
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return boolBox.value ? 1231 : 1237
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return intBox.value
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        return runtimeXorFoldHashCode(Int64(longBox.value))
    }
    if let ulongBox = tryCast(pointer, to: RuntimeULongBox.self) {
        // ULong.hashCode() uses the same (this xor (this ushr 32)) formula as
        // Long, and the bit pattern is identical either way, so this shares
        // runtimeXorFoldHashCode bit-for-bit with the Long branch above.
        return runtimeXorFoldHashCode(Int64(ulongBox.value))
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return runtimeFloatHashCode(floatBox.value)
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return runtimeXorFoldHashCode(Int64(kk_double_to_bits(doubleBox.value)))
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self) {
        return charBox.value
    }
    if runtimeIsUnitBox(value) {
        return 0
    }
    if let localeBox = tryCast(pointer, to: RuntimeLocaleBox.self) {
        let value = [localeBox.language, localeBox.country, localeBox.variant]
            .filter { !$0.isEmpty }
            .joined(separator: "#")
        return runtimeStringHashCode(value)
    }
    if let durationBox = tryCast(pointer, to: RuntimeDurationBox.self) {
        let nanoseconds = durationBox.nanoseconds
        return Int(truncatingIfNeeded: nanoseconds ^ (nanoseconds >> 32))
    }
    if let instantBox = tryCast(pointer, to: RuntimeInstantBox.self) {
        let epochHash = Int32(truncatingIfNeeded: instantBox.epochSeconds ^ (instantBox.epochSeconds >> 32))
        let nanoHash = Int32(instantBox.nanoOfSecond)
        return Int(epochHash &+ (51 &* nanoHash))
    }
    // List/Set/Map hash structurally, matching both runtimeValuesEqual's
    // List/Set/Map cases and kotlin.collections' List/Set/Map.hashCode()
    // contracts. Without this, these boxes fell through to the final
    // pointer-hash fallback below, which also broke `kk_any_to_string`
    // downstream (the pointer value round-tripped through kk_unbox_int/
    // kk_box_int as if it were still a live object, printing the
    // collection's toString() where an Int hashCode was expected).
    //
    // The accumulator is `Int32`, not `Int`: Kotlin's fold/sum runs in
    // 32-bit wrapping Int arithmetic at every step, so accumulating in a
    // 64-bit `Int` (even with `&+`/`&*`) only happens to agree while the
    // running total stays inside Int32 range and silently diverges once a
    // longer collection or a large-hashCode element pushes it past that.
    if let listBox = tryCast(pointer, to: RuntimeListBox.self) {
        var hash: Int32 = 1
        for element in listBox.elements {
            hash = 31 &* hash &+ Int32(truncatingIfNeeded: runtimeValueHash(element))
        }
        return Int(hash)
    }
    if let setBox = tryCast(pointer, to: RuntimeSetBox.self) {
        var hash: Int32 = 0
        for element in setBox.elements {
            hash = hash &+ Int32(truncatingIfNeeded: runtimeValueHash(element))
        }
        return Int(hash)
    }
    if let mapBox = tryCast(pointer, to: RuntimeMapBox.self) {
        var hash: Int32 = 0
        for (key, value) in zip(mapBox.keys, mapBox.values) {
            let entryHash = Int32(truncatingIfNeeded: runtimeValueHash(key))
                ^ Int32(truncatingIfNeeded: runtimeValueHash(value))
            hash = hash &+ entryHash
        }
        return Int(hash)
    }
    // Kotlin Set.hashCode() is the order-independent sum of element hashes.
    // RuntimeSetBox is shared by Set, MutableSet, LinkedHashSet, and HashSet,
    // so keep equal set instances consistent across all of those surfaces.
    if let setBox = tryCast(pointer, to: RuntimeSetBox.self) {
        return setBox.elements.reduce(0) { partial, element in
            partial &+ kk_any_hashCode(element, 0)
        }
    }
    // Tagged Pair/Triple boxes hash structurally, matching both
    // runtimeValuesEqual and kotlin/Tuples.kt's hashCode(); an untagged
    // RuntimePairBox is internal runtime state and keeps the pointer hash.
    if runtimeObjectTypeID(rawValue: value) == runtimePairNominalTypeID,
       let pairBox = tryCast(pointer, to: RuntimePairBox.self)
    {
        return 31 &* kk_any_hashCode(pairBox.first, 0) &+ kk_any_hashCode(pairBox.second, 0)
    }
    if runtimeObjectTypeID(rawValue: value) == runtimeTripleNominalTypeID,
       let tripleBox = tryCast(pointer, to: RuntimeTripleBox.self)
    {
        var hash = kk_any_hashCode(tripleBox.first, 0)
        hash = 31 &* hash &+ kk_any_hashCode(tripleBox.second, 0)
        return 31 &* hash &+ kk_any_hashCode(tripleBox.third, 0)
    }
    // Structural hash for data classes, boxed value classes (STDLIB-VALUECLASS),
    // and other user-defined objects reached via Any.hashCode() — must stay
    // consistent with runtimeValuesEqual's RuntimeObjectBox case (structural
    // equality by classID + elements). Without this, equal-by-content boxed
    // instances compared with `==` reported equal but had different
    // (pointer-derived) hashCode()s, breaking the hashCode/equals contract.
    if let objBox = tryCast(pointer, to: RuntimeObjectBox.self) {
        if let setBox = objBox.backingSetBox {
            // Some mutable set implementations use a RuntimeObjectBox shell
            // with a RuntimeSetBox backing store; preserve the same Set hash
            // contract for that representation.
            return setBox.values.reduce(0) { hash, element in
                hash &+ kk_any_hashCode(element.legacyRawValue, 0)
            }
        }
        var hash = Int(truncatingIfNeeded: objBox.classID)
        for element in objBox.elements {
            // KNOWN LIMITATION: RuntimeObjectBox.elements has no per-field type
            // tag, so a raw (unboxed) Boolean field hashes as tag 0 here — its
            // 0/1 value — instead of tag 2's Kotlin-standard 1231/1237. That
            // mismatches the compiler-synthesized data-class hashCode() (which
            // does know each field's declared type; see
            // appendSyntheticDataClassHashCodeIfNeeded), so the same instance's
            // hashCode() can differ between a direct call and this Any-erased
            // fallback for a Boolean field. A real fix needs per-field type
            // tags stored alongside RuntimeObjectBox's elements (a broader
            // change to object allocation), tracked as a follow-up rather than
            // rushed here; equal-by-content instances still hash equally to
            // each other through this same fallback path.
            hash = 31 &* hash &+ kk_any_hashCode(element, 0)
        }
        return hash
    }
    return Int(truncatingIfNeeded: UInt(bitPattern: pointer))
}

private func runtimeAnyKind(_ value: Int, _ tag: Int32) -> Int32 {
    if value == runtimeNullSentinelInt {
        return 0
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: value) else {
        return tag == 2 ? 2 : 1
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: pointer))
    }
    guard isObjectPointer else {
        return tag == 2 ? 2 : 1
    }
    if tryCast(pointer, to: RuntimeBoolBox.self) != nil {
        return 2
    }
    if tryCast(pointer, to: RuntimeStringBox.self) != nil {
        return 3
    }
    if tryCast(pointer, to: RuntimeIntBox.self) != nil {
        return 1
    }
    if tryCast(pointer, to: RuntimeLongBox.self) != nil {
        return 4
    }
    if tryCast(pointer, to: RuntimeFloatBox.self) != nil {
        return 5
    }
    if tryCast(pointer, to: RuntimeDoubleBox.self) != nil {
        return 6
    }
    if tryCast(pointer, to: RuntimeCharBox.self) != nil {
        return 7
    }
    if tryCast(pointer, to: RuntimeDurationBox.self) != nil {
        return 8
    }
    if tryCast(pointer, to: RuntimeInstantBox.self) != nil {
        return 9
    }
    if tryCast(pointer, to: RuntimeULongBox.self) != nil {
        return 10
    }
    if runtimeIsUnitBox(value) {
        return 11
    }
    return 100
}

/// Any.hashCode() — uses runtime-aware hashing for boxed values and raw primitives.
@_cdecl("kk_any_hashCode")
public func kk_any_hashCode(_ value: Int, _ tag: Int) -> Int {
    runtimeAnyHashCode(value, Int32(truncatingIfNeeded: tag))
}

/// Hashes an opaque runtime value with the same value-level semantics used by
/// RuntimeElementKey. The collection index must not hash object identity when
/// runtimeValuesEqual considers two handles equal by content.
func runtimeValueHash(_ value: Int) -> Int {
    var hash = kk_any_hashCode(value, 0)
    if let ptr = UnsafeMutableRawPointer(bitPattern: value) {
        let isObjectPointer = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObjectPointer {
            if let floatBox = tryCast(ptr, to: RuntimeFloatBox.self), floatBox.value == 0 {
                hash = kk_float_to_bits(Float(0))
            } else if let doubleBox = tryCast(ptr, to: RuntimeDoubleBox.self), doubleBox.value == 0 {
                let bits = Int64(bitPattern: UInt64(bitPattern: Int64(kk_double_to_bits(Double(0)))))
                hash = Int(truncatingIfNeeded: bits ^ (bits >> 32))
            }
        }
    }
    return hash
}

/// Any.equals(other) — uses runtime-aware equality for boxed values and tagged primitives.
@_cdecl("kk_any_equals")
public func kk_any_equals(_ lhs: Int, _ lhsTag: Int, _ rhs: Int, _ rhsTag: Int) -> Int {
    let lhsTag = Int32(truncatingIfNeeded: lhsTag)
    let rhsTag = Int32(truncatingIfNeeded: rhsTag)
    if runtimeAnyKind(lhs, lhsTag) != runtimeAnyKind(rhs, rhsTag) {
        return kk_box_bool(0)
    }
    let equal = runtimeAnyObjectEquality(lhs, rhs) ?? runtimeValuesEqual(lhs, rhs)
    return kk_box_bool(equal ? 1 : 0)
}

/// 1-arg member-dispatch wrappers for kotlin.Any virtual methods.
/// KIR lowers `obj.toString()` to `kk_any_member_to_string(receiver)` via the
/// registered externalLinkName; these shims delegate to the 2/4-arg forms with
/// tag=1 (object pointer, non-primitive).
@_cdecl("kk_any_member_to_string")
public func kk_any_member_to_string(_ raw: Int) -> UnsafeMutableRawPointer {
    if let throwableMethod = runtimeThrowableVtableMethodRaw(
        raw,
        slot: RuntimeThrowableVtableSlot.toString
    ) {
        let method = unsafeBitCast(
            throwableMethod,
            to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        if let rendered = UnsafeMutableRawPointer(bitPattern: method(raw, nil)) {
            return rendered
        }
    }
    return kk_any_to_string(raw, 1)
}

@_cdecl("kk_any_member_hashCode")
public func kk_any_member_hashCode(_ raw: Int) -> Int {
    kk_any_hashCode(raw, 1)
}

@_cdecl("kk_any_member_equals")
public func kk_any_member_equals(_ lhs: Int, _ rhs: Int) -> Int {
    kk_any_equals(lhs, 1, rhs, 1)
}

/// Encode a Float's IEEE 754 bit pattern into an Int for transport across the
/// C ABI boundary. Uses `bitPattern`-based (non-trapping) conversions throughout,
/// mirroring `kk_double_to_bits`. On 64-bit platforms `UInt(UInt32)` zero-extends;
/// on a hypothetical 32-bit target the cast is a no-op since UInt32 == UInt.
@_cdecl("kk_float_to_bits")
public func kk_float_to_bits(_ value: Float) -> Int {
    Int(bitPattern: UInt(value.bitPattern))
}

@_cdecl("kk_bits_to_float")
public func kk_bits_to_float(_ value: Int) -> Float {
    Float(bitPattern: UInt32(truncatingIfNeeded: value))
}

@_cdecl("kk_double_to_bits")
public func kk_double_to_bits(_ value: Double) -> Int {
    Int(bitPattern: UInt(value.bitPattern))
}

@_cdecl("kk_bits_to_double")
public func kk_bits_to_double(_ value: Int) -> Double {
    Double(bitPattern: UInt64(bitPattern: Int64(value)))
}

@_cdecl("kk_int_to_float_bits")
public func kk_int_to_float_bits(_ value: Int) -> Int {
    kk_float_to_bits(Float(kk_unbox_int(value)))
}

@_cdecl("kk_int_to_float")
public func kk_int_to_float(_ value: Int) -> Int {
    kk_float_to_bits(Float(kk_unbox_int(value)))
}

@_cdecl("kk_int_to_byte")
public func kk_int_to_byte(_ value: Int) -> Int {
    Int(Int8(truncatingIfNeeded: kk_unbox_int(value)))
}

@_cdecl("kk_int_to_short")
public func kk_int_to_short(_ value: Int) -> Int {
    Int(Int16(truncatingIfNeeded: kk_unbox_int(value)))
}

@_cdecl("kk_int_to_double_bits")
public func kk_int_to_double_bits(_ value: Int) -> Int {
    kk_double_to_bits(Double(kk_unbox_int(value)))
}

@_cdecl("__kk_float_to_double_bits")
public func __kk_float_to_double_bits(_ value: Int) -> Int {
    kk_double_to_bits(Double(kk_bits_to_float(value)))
}

@_cdecl("__kk_math_sqrt")
public func __kk_math_sqrt(_ value: Int) -> Int {
    kk_double_to_bits(sqrt(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_pow")
public func __kk_math_pow(_ base: Int, _ exp: Int) -> Int {
    let rawBase = kk_bits_to_double(base)
    let rawExp = kk_bits_to_double(exp)
    return kk_double_to_bits(pow(rawBase, rawExp))
}

@_cdecl("__kk_math_pow_float")
public func __kk_math_pow_float(_ base: Int, _ exp: Int) -> Int {
    kk_float_to_bits(powf(kk_bits_to_float(base), kk_bits_to_float(exp)))
}

@_cdecl("__kk_math_pow_int")
public func __kk_math_pow_int(_ base: Int, _ exp: Int) -> Int {
    kk_double_to_bits(pow(kk_bits_to_double(base), Double(exp)))
}

@_cdecl("__kk_math_pow_float_int")
public func __kk_math_pow_float_int(_ base: Int, _ exp: Int) -> Int {
    kk_float_to_bits(powf(kk_bits_to_float(base), Float(exp)))
}

// MARK: - minOf/maxOf Float/Double (STDLIB-COMP-FN NaN & signed-zero semantics)
//
// Kotlin's minOf(Float, Float) / maxOf(Float, Float) delegate to Java's
// Math.min/Math.max on JVM, whose semantics differ from a plain `<`/`>`
// comparison in two ways:
//   1. NaN propagates: if `a` is NaN, the result is `a` (NaN), regardless of `b`.
//      A plain `a < b` / `a > b` comparison is always false for NaN operands, so
//      it silently picks the non-NaN argument instead.
//   2. Signed zero is distinguished: minOf(-0.0, 0.0) == -0.0 and
//      maxOf(-0.0, 0.0) == 0.0, regardless of argument order, even though
//      -0.0 == 0.0 under IEEE 754 equality.
// These entry points take/return Float/Double bit patterns (matching the
// kk_math_* convention above) so they can be called directly from KIR-lowered
// minOf/maxOf without an extra bitcast step.

@_cdecl("kk_min_float")
public func kk_min_float(_ aBits: Int, _ bBits: Int) -> Int {
    let a = kk_bits_to_float(aBits)
    if a.isNaN { return aBits }
    let b = kk_bits_to_float(bBits)
    if a == 0.0, b == 0.0, b.sign == .minus {
        return bBits
    }
    return a <= b ? aBits : bBits
}

@_cdecl("kk_max_float")
public func kk_max_float(_ aBits: Int, _ bBits: Int) -> Int {
    let a = kk_bits_to_float(aBits)
    if a.isNaN { return aBits }
    let b = kk_bits_to_float(bBits)
    if a == 0.0, b == 0.0, a.sign == .minus {
        return bBits
    }
    return a >= b ? aBits : bBits
}

@_cdecl("kk_min_double")
public func kk_min_double(_ aBits: Int, _ bBits: Int) -> Int {
    let a = kk_bits_to_double(aBits)
    if a.isNaN { return aBits }
    let b = kk_bits_to_double(bBits)
    if a == 0.0, b == 0.0, b.sign == .minus {
        return bBits
    }
    return a <= b ? aBits : bBits
}

@_cdecl("kk_max_double")
public func kk_max_double(_ aBits: Int, _ bBits: Int) -> Int {
    let a = kk_bits_to_double(aBits)
    if a.isNaN { return aBits }
    let b = kk_bits_to_double(bBits)
    if a == 0.0, b == 0.0, a.sign == .minus {
        return bBits
    }
    return a >= b ? aBits : bBits
}

@_cdecl("__kk_math_ceil")
public func __kk_math_ceil(_ value: Int) -> Int {
    kk_double_to_bits(ceil(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_floor")
public func __kk_math_floor(_ value: Int) -> Int {
    kk_double_to_bits(floor(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_round")
public func __kk_math_round(_ value: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(value).rounded(.toNearestOrEven))
}

// Trigonometric functions (STDLIB-430)
//
// Architecture assumption: Double bit-pattern transport via Int/intptr_t relies
// on Int being 64-bit (MemoryLayout<Int>.size == 8) so that the full 64-bit
// IEEE 754 payload is preserved. This is true on all Apple Silicon and x86_64
// targets; 32-bit platforms are not supported by this runtime.
//
// Note: Each @_cdecl wrapper is spelled out individually rather than factored
// through a shared closure helper. This repetition is intentional — keeping
// every entry point as a plain, self-contained function ensures the C ABI
// surface is auditable in code review and prevents optimizer surprises from
// indirect-call thunks in hot numeric paths.

@_cdecl("__kk_math_sin")
public func __kk_math_sin(_ value: Int) -> Int {
    kk_double_to_bits(sin(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_cos")
public func __kk_math_cos(_ value: Int) -> Int {
    kk_double_to_bits(cos(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_tan")
public func __kk_math_tan(_ value: Int) -> Int {
    kk_double_to_bits(tan(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_sinh")
public func __kk_math_sinh(_ value: Int) -> Int {
    kk_double_to_bits(sinh(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_cosh")
public func __kk_math_cosh(_ value: Int) -> Int {
    kk_double_to_bits(cosh(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_tanh")
public func __kk_math_tanh(_ value: Int) -> Int {
    kk_double_to_bits(tanh(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_cbrt")
public func __kk_math_cbrt(_ value: Int) -> Int {
    kk_double_to_bits(cbrt(kk_bits_to_double(value)))
}

// MARK: - STDLIB-MATH-113: Inverse hyperbolic functions (Double)

@_cdecl("__kk_math_acosh")
public func __kk_math_acosh(_ value: Int) -> Int {
    kk_double_to_bits(acosh(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_asinh")
public func __kk_math_asinh(_ value: Int) -> Int {
    kk_double_to_bits(asinh(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_atanh")
public func __kk_math_atanh(_ value: Int) -> Int {
    kk_double_to_bits(atanh(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_asin")
public func __kk_math_asin(_ value: Int) -> Int {
    kk_double_to_bits(asin(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_acos")
public func __kk_math_acos(_ value: Int) -> Int {
    kk_double_to_bits(acos(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_atan")
public func __kk_math_atan(_ value: Int) -> Int {
    kk_double_to_bits(atan(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_atan2")
public func __kk_math_atan2(_ y: Int, _ x: Int) -> Int {
    kk_double_to_bits(atan2(kk_bits_to_double(y), kk_bits_to_double(x)))
}

// MARK: - STDLIB-431: exp/ln/log functions

@_cdecl("__kk_math_exp")
public func __kk_math_exp(_ value: Int) -> Int {
    kk_double_to_bits(exp(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_expm1")
public func __kk_math_expm1(_ value: Int) -> Int {
    kk_double_to_bits(expm1(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_ln")
public func __kk_math_ln(_ value: Int) -> Int {
    kk_double_to_bits(log(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_ln1p")
public func __kk_math_ln1p(_ value: Int) -> Int {
    kk_double_to_bits(log1p(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_log2")
public func __kk_math_log2(_ value: Int) -> Int {
    kk_double_to_bits(log2(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_log10")
public func __kk_math_log10(_ value: Int) -> Int {
    kk_double_to_bits(log10(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_log")
public func __kk_math_log(_ x: Int, _ base: Int) -> Int {
    let rawX = kk_bits_to_double(x)
    let rawBase = kk_bits_to_double(base)

    // Match Kotlin's special-case table instead of relying on raw ln(x) / ln(base).
    if rawX.isNaN || rawBase.isNaN {
        return kk_double_to_bits(Double.nan)
    }
    if rawX < 0 || rawBase <= 0 || rawBase == 1.0 {
        return kk_double_to_bits(Double.nan)
    }
    if rawX.isInfinite {
        if rawBase.isInfinite {
            return kk_double_to_bits(Double.nan)
        }
        return kk_double_to_bits(rawBase > 1.0 ? Double.infinity : -Double.infinity)
    }
    if rawX == 0.0 {
        return kk_double_to_bits(rawBase > 1.0 ? -Double.infinity : Double.infinity)
    }
    return kk_double_to_bits(log(rawX) / log(rawBase))
}

// MARK: - STDLIB-432: hypot

@_cdecl("__kk_math_hypot")
public func __kk_math_hypot(_ x: Int, _ y: Int) -> Int {
    let rawX = kk_bits_to_double(x)
    let rawY = kk_bits_to_double(y)
    return kk_double_to_bits(hypot(rawX, rawY))
}

// MARK: - STDLIB-500~509: Float trig/math overloads

//
// Float values are transported as bit-encoded Int (intptr_t), just like Double.
// The low 32 bits carry the IEEE 754 single-precision payload; upper bits are
// ignored on decode and zero-extended on encode.

/// Helper: decode bit-encoded Float, apply a unary operation, re-encode.
/// Reduces boilerplate across the Float math entry points below.
private func applyFloatUnaryOp(_ v: Int, _ op: (Float) -> Float) -> Int {
    kk_float_to_bits(op(kk_bits_to_float(v)))
}

@_cdecl("__kk_math_sin_float")
public func __kk_math_sin_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, sinf)
}

@_cdecl("__kk_math_cos_float")
public func __kk_math_cos_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, cosf)
}

@_cdecl("__kk_math_tan_float")
public func __kk_math_tan_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, tanf)
}

@_cdecl("__kk_math_sinh_float")
public func __kk_math_sinh_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, sinhf)
}

@_cdecl("__kk_math_cosh_float")
public func __kk_math_cosh_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, coshf)
}

@_cdecl("__kk_math_tanh_float")
public func __kk_math_tanh_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, tanhf)
}

@_cdecl("__kk_math_cbrt_float")
public func __kk_math_cbrt_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, cbrtf)
}

// MARK: - STDLIB-MATH-113: Inverse hyperbolic functions (Float)

@_cdecl("__kk_math_acosh_float")
public func __kk_math_acosh_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, acoshf)
}

@_cdecl("__kk_math_asinh_float")
public func __kk_math_asinh_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, asinhf)
}

@_cdecl("__kk_math_atanh_float")
public func __kk_math_atanh_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, atanhf)
}

@_cdecl("__kk_math_asin_float")
public func __kk_math_asin_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, asinf)
}

@_cdecl("__kk_math_acos_float")
public func __kk_math_acos_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, acosf)
}

@_cdecl("__kk_math_atan_float")
public func __kk_math_atan_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, atanf)
}

@_cdecl("__kk_math_atan2_float")
public func __kk_math_atan2_float(_ y: Int, _ x: Int) -> Int {
    let fy = kk_bits_to_float(y)
    let fx = kk_bits_to_float(x)
    return kk_float_to_bits(atan2f(fy, fx))
}

@_cdecl("__kk_math_sqrt_float")
public func __kk_math_sqrt_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, sqrtf)
}

@_cdecl("__kk_math_round_float")
public func __kk_math_round_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v) { $0.rounded(.toNearestOrEven) }
}

@_cdecl("__kk_math_ceil_float")
public func __kk_math_ceil_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, ceilf)
}

@_cdecl("__kk_math_floor_float")
public func __kk_math_floor_float(_ v: Int) -> Int {
    applyFloatUnaryOp(v, floorf)
}

// MARK: - STDLIB-430: additional Float overloads (exp, expm1, ln, ln1p, log2, log10, log, hypot)

@_cdecl("__kk_math_exp_float")
public func __kk_math_exp_float(_ value: Int) -> Int {
    kk_float_to_bits(exp(kk_bits_to_float(value)))
}

@_cdecl("__kk_math_expm1_float")
public func __kk_math_expm1_float(_ value: Int) -> Int {
    kk_float_to_bits(expm1f(kk_bits_to_float(value)))
}

@_cdecl("__kk_math_ln_float")
public func __kk_math_ln_float(_ value: Int) -> Int {
    kk_float_to_bits(log(kk_bits_to_float(value)))
}

@_cdecl("__kk_math_ln1p_float")
public func __kk_math_ln1p_float(_ value: Int) -> Int {
    kk_float_to_bits(log1pf(kk_bits_to_float(value)))
}

@_cdecl("__kk_math_log2_float")
public func __kk_math_log2_float(_ value: Int) -> Int {
    kk_float_to_bits(log2(kk_bits_to_float(value)))
}

@_cdecl("__kk_math_log10_float")
public func __kk_math_log10_float(_ value: Int) -> Int {
    kk_float_to_bits(log10(kk_bits_to_float(value)))
}

@_cdecl("__kk_math_log_float")
public func __kk_math_log_float(_ x: Int, _ base: Int) -> Int {
    let rawX = kk_bits_to_float(x)
    let rawBase = kk_bits_to_float(base)

    // Match Kotlin's special-case table instead of relying on raw ln(x) / ln(base).
    if rawX.isNaN || rawBase.isNaN {
        return kk_float_to_bits(Float.nan)
    }
    if rawX < 0 || rawBase <= 0 || rawBase == 1.0 {
        return kk_float_to_bits(Float.nan)
    }
    if rawX.isInfinite {
        if rawBase.isInfinite {
            return kk_float_to_bits(Float.nan)
        }
        return kk_float_to_bits(rawBase > 1.0 ? Float.infinity : -Float.infinity)
    }
    if rawX == 0.0 {
        return kk_float_to_bits(rawBase > 1.0 ? -Float.infinity : Float.infinity)
    }
    return kk_float_to_bits(log(rawX) / log(rawBase))
}

@_cdecl("__kk_math_hypot_float")
public func __kk_math_hypot_float(_ x: Int, _ y: Int) -> Int {
    let rawX = kk_bits_to_float(x)
    let rawY = kk_bits_to_float(y)
    return kk_float_to_bits(hypot(rawX, rawY))
}

// MARK: - STDLIB-510~511: roundToInt / roundToLong extensions

// Kotlin's roundToInt/roundToLong use Math.round() semantics: ties round
// towards positive infinity. For Float and Double, we use bit-manipulation
// algorithms matching Java 7+ Math.round(...) to avoid precision loss from
// floor(x + 0.5) near half-integer boundaries (JDK-6430675).

/// Bit-manipulation rounding for Float matching Java 7+ Math.round(float).
/// Avoids the precision loss of `floorf(raw + 0.5)` for values just below
/// half-integer boundaries (e.g. Float(bitPattern: 0x3EFFFFFF) ~ 0.49999997).
private func roundFloatJava7(_ raw: Float) -> Int64 {
    let bits = raw.bitPattern
    let biasedExp = Int((bits >> 23) & 0xFF)
    let shift = 149 - biasedExp // (23 - 1 + 127) - biasedExp
    if (shift & ~31) == 0 { // 0 <= shift <= 31
        var r = Int32(bitPattern: (bits & 0x7FFFFF) | 0x800000)
        if Int32(bitPattern: bits) < 0 { r = -r }
        return Int64((r >> shift) &+ 1) >> 1
    } else {
        // Exponent too small (magnitude < 0.5 → 0) or too large (already integral)
        if raw >= Float(Int64.max) { return Int64.max }
        if raw <= Float(Int64.min) { return Int64.min }
        return Int64(raw)
    }
}

/// Bit-manipulation rounding for Double matching Java 7+ Math.round(double).
/// Avoids the precision loss of `floor(raw + 0.5)` for values just below
/// half-integer boundaries (e.g. 0.49999999999999994).
private func roundDoubleJava7(_ raw: Double) -> Int64 {
    let bits = raw.bitPattern
    let biasedExp = Int((bits >> 52) & 0x7FF)
    let shift = 1074 - biasedExp // (52 - 1 + 1023) - biasedExp
    if (shift & ~63) == 0 { // 0 <= shift <= 63
        var r = Int64(bitPattern: (bits & 0xF_FFFF_FFFF_FFFF) | 0x10_0000_0000_0000)
        if Int64(bitPattern: bits) < 0 { r = -r }
        return ((r >> shift) &+ 1) >> 1
    } else {
        if raw >= Double(Int64.max) { return Int64.max }
        if raw <= Double(Int64.min) { return Int64.min }
        return Int64(raw)
    }
}

// Kotlin `Double.roundToInt()` / `roundToLong()` (and the Float overloads)
// throw IllegalArgumentException when the receiver is NaN. Infinity / out-of-range
// still saturate to MIN/MAX (no exception). These are therefore throwing callees
// (outThrown appended by ABILoweringPass — they must NOT be in nonThrowingCallees).
@_cdecl("__kk_float_roundToInt")
public func __kk_float_roundToInt(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let raw = kk_bits_to_float(value)
    if raw.isNaN {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Cannot round NaN value.")
        return 0
    }
    let r = roundFloatJava7(raw)
    if r >= Int64(Int32.max) { return Int(Int32.max) }
    if r <= Int64(Int32.min) { return Int(Int32.min) }
    return Int(Int32(r))
}

@_cdecl("__kk_double_roundToInt")
public func __kk_double_roundToInt(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let raw = kk_bits_to_double(value)
    if raw.isNaN {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Cannot round NaN value.")
        return 0
    }
    let r = roundDoubleJava7(raw)
    if r >= Int64(Int32.max) { return Int(Int32.max) }
    if r <= Int64(Int32.min) { return Int(Int32.min) }
    return Int(Int32(r))
}

@_cdecl("__kk_float_roundToLong")
public func __kk_float_roundToLong(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let raw = kk_bits_to_float(value)
    if raw.isNaN {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Cannot round NaN value.")
        return 0
    }
    let r = roundFloatJava7(raw)
    if r >= Int64.max { return Int(Int64.max) }
    if r <= Int64.min { return Int(Int64.min) }
    return Int(r)
}

@_cdecl("__kk_double_roundToLong")
public func __kk_double_roundToLong(_ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let raw = kk_bits_to_double(value)
    if raw.isNaN {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Cannot round NaN value.")
        return 0
    }
    let r = roundDoubleJava7(raw)
    if r >= Int64.max { return Int(Int64.max) }
    if r <= Int64.min { return Int(Int64.min) }
    return Int(r)
}

// MARK: - STDLIB-512~513: ulp / nextUp / nextDown extensions

@_cdecl("__kk_double_ulp")
public func __kk_double_ulp(_ value: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(value).ulp)
}

@_cdecl("__kk_double_nextUp")
public func __kk_double_nextUp(_ value: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(value).nextUp)
}

@_cdecl("__kk_double_nextDown")
public func __kk_double_nextDown(_ value: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(value).nextDown)
}

@_cdecl("__kk_float_ulp")
public func __kk_float_ulp(_ value: Int) -> Int {
    kk_float_to_bits(kk_bits_to_float(value).ulp)
}

@_cdecl("__kk_float_nextUp")
public func __kk_float_nextUp(_ value: Int) -> Int {
    kk_float_to_bits(kk_bits_to_float(value).nextUp)
}

@_cdecl("__kk_float_nextDown")
public func __kk_float_nextDown(_ value: Int) -> Int {
    kk_float_to_bits(kk_bits_to_float(value).nextDown)
}

// MARK: - STDLIB-NUM-130: Floating-point precision — toBits
//
// KSP-646: isNaN / isInfinite / isFinite are implemented in bundled Kotlin
// (Stdlib/kotlin/util/Numbers.kt) on top of toRawBits(), so no runtime export
// remains for them.

/// Double.toBits(): Long — returns IEEE 754 bit representation as Long.
/// Canonicalizes NaN to the standard quiet NaN bit pattern per Kotlin semantics.
@_cdecl("__kk_double_toBits")
public func __kk_double_toBits(_ value: Int) -> Int {
    let d = kk_bits_to_double(value)
    if d.isNaN { return Int(bitPattern: UInt(0x7FF8_0000_0000_0000 as UInt64)) }
    return kk_double_to_bits(d)
}

/// Double.toRawBits(): Long — same as toBits() for finite values; differs for NaN.
/// In Kotlin toRawBits returns the actual bit pattern without canonicalizing NaN.
@_cdecl("__kk_double_toRawBits")
public func __kk_double_toRawBits(_ value: Int) -> Int {
    value  // bit pattern is already canonical in our ABI
}

/// Double.Companion.fromBits(bits: Long): Double.
/// Double bit patterns occupy the full runtime ABI word, so this is an identity.
@_cdecl("__kk_double_fromBits")
public func __kk_double_fromBits(_ bits: Int) -> Int {
    bits
}

/// Float.toBits(): Int — returns IEEE 754 bit representation as Int.
/// Canonicalizes NaN to the standard quiet NaN bit pattern per Kotlin semantics.
/// The ABI carries Float as a zero-extended 32-bit pattern, so the result is
/// sign-extended back into the Int domain Kotlin expects.
@_cdecl("__kk_float_toBits")
public func __kk_float_toBits(_ value: Int) -> Int {
    let f = kk_bits_to_float(value)
    if f.isNaN { return Int(Int32(bitPattern: 0x7FC0_0000 as UInt32)) }
    return Int(Int32(bitPattern: f.bitPattern))
}

/// Float.toRawBits(): Int — actual bit pattern without canonicalizing NaN.
@_cdecl("__kk_float_toRawBits")
public func __kk_float_toRawBits(_ value: Int) -> Int {
    Int(Int32(truncatingIfNeeded: value))
}

/// Float.Companion.fromBits(bits: Int): Float.
/// Kotlin exposes the 32-bit IEEE pattern as a sign-extended Int, while the
/// runtime ABI carries Float payloads as a zero-extended word.
@_cdecl("__kk_float_fromBits")
public func __kk_float_fromBits(_ bits: Int) -> Int {
    Int(UInt32(truncatingIfNeeded: bits))
}

// MARK: - STDLIB-514: truncate, IEEErem, nextTowards

@_cdecl("__kk_math_truncate")
public func __kk_math_truncate(_ value: Int) -> Int {
    kk_double_to_bits(trunc(kk_bits_to_double(value)))
}

@_cdecl("__kk_math_truncate_float")
public func __kk_math_truncate_float(_ value: Int) -> Int {
    kk_float_to_bits(truncf(kk_bits_to_float(value)))
}

@_cdecl("__kk_math_IEEErem")
public func __kk_math_IEEErem(_ x: Int, _ y: Int) -> Int {
    kk_double_to_bits(remainder(kk_bits_to_double(x), kk_bits_to_double(y)))
}

@_cdecl("__kk_math_IEEErem_float")
public func __kk_math_IEEErem_float(_ x: Int, _ y: Int) -> Int {
    kk_float_to_bits(remainderf(kk_bits_to_float(x), kk_bits_to_float(y)))
}

@_cdecl("__kk_math_nextTowards")
public func __kk_math_nextTowards(_ from: Int, _ to: Int) -> Int {
    let rawFrom = kk_bits_to_double(from)
    let rawTo = kk_bits_to_double(to)
    return kk_double_to_bits(nextafter(rawFrom, rawTo))
}

@_cdecl("__kk_math_nextTowards_float")
public func __kk_math_nextTowards_float(_ from: Int, _ to: Int) -> Int {
    let rawFrom = kk_bits_to_float(from)
    let rawTo = kk_bits_to_float(to)
    return kk_float_to_bits(nextafterf(rawFrom, rawTo))
}

@_cdecl("kk_bitwise_and")
public func kk_bitwise_and(_ lhs: Int, _ rhs: Int) -> Int {
    lhs & rhs
}

@_cdecl("kk_bitwise_or")
public func kk_bitwise_or(_ lhs: Int, _ rhs: Int) -> Int {
    lhs | rhs
}

@_cdecl("kk_bitwise_xor")
public func kk_bitwise_xor(_ lhs: Int, _ rhs: Int) -> Int {
    lhs ^ rhs
}

@_cdecl("kk_op_not")
public func kk_op_not(_ value: Int) -> Int {
    value == 0 ? 1 : 0
}

@_cdecl("kk_op_inv")
public func kk_op_inv(_ value: Int) -> Int {
    ~value
}

@_cdecl("kk_op_shl")
public func kk_op_shl(_ lhs: Int, _ rhs: Int) -> Int {
    let shift = runtimeNormalizedShift(rhs)
    return Int(bitPattern: UInt(bitPattern: lhs) << shift)
}

@_cdecl("kk_op_shr")
public func kk_op_shr(_ lhs: Int, _ rhs: Int) -> Int {
    let shift = runtimeNormalizedShift(rhs)
    return lhs >> shift
}

@_cdecl("kk_op_ushr")
public func kk_op_ushr(_ lhs: Int, _ rhs: Int) -> Int {
    let shift = runtimeNormalizedShift(rhs)
    return Int(bitPattern: UInt(bitPattern: lhs) >> shift)
}

@_cdecl("__kk_double_to_int")
public func __kk_double_to_int(_ value: Int) -> Int {
    let d = kk_bits_to_double(value)
    if d.isNaN { return 0 }
    if d >= Double(Int32.max) { return Int(Int32.max) }
    if d <= Double(Int32.min) { return Int(Int32.min) }
    return Int(Int32(d))
}

@_cdecl("__kk_float_to_int")
public func __kk_float_to_int(_ value: Int) -> Int {
    let f = kk_bits_to_float(value)
    if f.isNaN { return 0 }
    if f >= Float(Int32.max) { return Int(Int32.max) }
    if f <= Float(Int32.min) { return Int(Int32.min) }
    return Int(Int32(f))
}

@_cdecl("__kk_double_to_long")
public func __kk_double_to_long(_ value: Int) -> Int {
    let d = kk_bits_to_double(value)
    if d.isNaN { return 0 }
    if d >= Double(Int64.max) { return Int(Int64.max) }
    if d <= Double(Int64.min) { return Int(Int64.min) }
    return Int(Int64(d))
}

@_cdecl("__kk_float_to_long")
public func __kk_float_to_long(_ value: Int) -> Int {
    let f = kk_bits_to_float(value)
    if f.isNaN { return 0 }
    if f >= Float(Int64.max) { return Int(Int64.max) }
    if f <= Float(Int64.min) { return Int(Int64.min) }
    return Int(Int64(f))
}

/// Long→* conversions: `Int` (intptr_t) is used for Long values.
/// This is correct on 64-bit macOS where Int == Int64.
@_cdecl("kk_long_to_int")
public func kk_long_to_int(_ value: Int) -> Int {
    Int(Int32(truncatingIfNeeded: value))
}

@_cdecl("kk_long_to_float")
public func kk_long_to_float(_ value: Int) -> Int {
    kk_float_to_bits(Float(value))
}

@_cdecl("kk_long_to_double")
public func kk_long_to_double(_ value: Int) -> Int {
    kk_double_to_bits(Double(value))
}

@_cdecl("kk_double_to_float")
public func kk_double_to_float(_ value: Int) -> Int {
    kk_float_to_bits(Float(kk_bits_to_double(value)))
}

@_cdecl("kk_long_to_byte")
public func kk_long_to_byte(_ value: Int) -> Int {
    Int(Int8(truncatingIfNeeded: value))
}

@_cdecl("kk_long_to_short")
public func kk_long_to_short(_ value: Int) -> Int {
    Int(Int16(truncatingIfNeeded: value))
}

// MARK: - Double arithmetic ops (bit-encoded intptr_t ABI)

@_cdecl("kk_op_dadd")
public func kk_op_dadd(_ lhs: Int, _ rhs: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(lhs) + kk_bits_to_double(rhs))
}

@_cdecl("kk_op_dsub")
public func kk_op_dsub(_ lhs: Int, _ rhs: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(lhs) - kk_bits_to_double(rhs))
}

@_cdecl("kk_op_dmul")
public func kk_op_dmul(_ lhs: Int, _ rhs: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(lhs) * kk_bits_to_double(rhs))
}

@_cdecl("kk_op_ddiv")
public func kk_op_ddiv(_ lhs: Int, _ rhs: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(lhs) / kk_bits_to_double(rhs))
}

@_cdecl("kk_op_dmod")
public func kk_op_dmod(_ lhs: Int, _ rhs: Int) -> Int {
    kk_double_to_bits(kk_bits_to_double(lhs).truncatingRemainder(dividingBy: kk_bits_to_double(rhs)))
}

private func runtimeDoubleFloorMod(_ lhs: Double, _ rhs: Double) -> Double {
    let remainder = lhs.truncatingRemainder(dividingBy: rhs)
    if remainder == 0.0 || remainder.isNaN {
        return remainder
    }
    if (remainder < 0.0 && rhs > 0.0) || (remainder > 0.0 && rhs < 0.0) {
        return remainder + rhs
    }
    return remainder
}

@_cdecl("kk_op_dfloor_mod")
public func kk_op_dfloor_mod(_ lhs: Int, _ rhs: Int) -> Int {
    kk_double_to_bits(runtimeDoubleFloorMod(kk_bits_to_double(lhs), kk_bits_to_double(rhs)))
}

@_cdecl("kk_op_deq")
public func kk_op_deq(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_double(lhs) == kk_bits_to_double(rhs) ? 1 : 0
}

@_cdecl("kk_op_dne")
public func kk_op_dne(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_double(lhs) != kk_bits_to_double(rhs) ? 1 : 0
}

@_cdecl("kk_op_dlt")
public func kk_op_dlt(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_double(lhs) < kk_bits_to_double(rhs) ? 1 : 0
}

@_cdecl("kk_op_dle")
public func kk_op_dle(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_double(lhs) <= kk_bits_to_double(rhs) ? 1 : 0
}

@_cdecl("kk_op_dgt")
public func kk_op_dgt(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_double(lhs) > kk_bits_to_double(rhs) ? 1 : 0
}

@_cdecl("kk_op_dge")
public func kk_op_dge(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_double(lhs) >= kk_bits_to_double(rhs) ? 1 : 0
}

// MARK: - Float arithmetic ops (bit-encoded intptr_t ABI)

@_cdecl("kk_op_fadd")
public func kk_op_fadd(_ lhs: Int, _ rhs: Int) -> Int {
    kk_float_to_bits(kk_bits_to_float(lhs) + kk_bits_to_float(rhs))
}

@_cdecl("kk_op_fsub")
public func kk_op_fsub(_ lhs: Int, _ rhs: Int) -> Int {
    kk_float_to_bits(kk_bits_to_float(lhs) - kk_bits_to_float(rhs))
}

@_cdecl("kk_op_fmul")
public func kk_op_fmul(_ lhs: Int, _ rhs: Int) -> Int {
    kk_float_to_bits(kk_bits_to_float(lhs) * kk_bits_to_float(rhs))
}

@_cdecl("kk_op_fdiv")
public func kk_op_fdiv(_ lhs: Int, _ rhs: Int) -> Int {
    kk_float_to_bits(kk_bits_to_float(lhs) / kk_bits_to_float(rhs))
}

@_cdecl("kk_op_fmod")
public func kk_op_fmod(_ lhs: Int, _ rhs: Int) -> Int {
    kk_float_to_bits(kk_bits_to_float(lhs).truncatingRemainder(dividingBy: kk_bits_to_float(rhs)))
}

private func runtimeFloatFloorMod(_ lhs: Float, _ rhs: Float) -> Float {
    let remainder = lhs.truncatingRemainder(dividingBy: rhs)
    if remainder == 0.0 || remainder.isNaN {
        return remainder
    }
    if (remainder < 0.0 && rhs > 0.0) || (remainder > 0.0 && rhs < 0.0) {
        return remainder + rhs
    }
    return remainder
}

@_cdecl("kk_op_ffloor_mod")
public func kk_op_ffloor_mod(_ lhs: Int, _ rhs: Int) -> Int {
    kk_float_to_bits(runtimeFloatFloorMod(kk_bits_to_float(lhs), kk_bits_to_float(rhs)))
}

@_cdecl("kk_op_feq")
public func kk_op_feq(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_float(lhs) == kk_bits_to_float(rhs) ? 1 : 0
}

@_cdecl("kk_op_fne")
public func kk_op_fne(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_float(lhs) != kk_bits_to_float(rhs) ? 1 : 0
}

@_cdecl("kk_op_flt")
public func kk_op_flt(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_float(lhs) < kk_bits_to_float(rhs) ? 1 : 0
}

@_cdecl("kk_op_fle")
public func kk_op_fle(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_float(lhs) <= kk_bits_to_float(rhs) ? 1 : 0
}

@_cdecl("kk_op_fgt")
public func kk_op_fgt(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_float(lhs) > kk_bits_to_float(rhs) ? 1 : 0
}

@_cdecl("kk_op_fge")
public func kk_op_fge(_ lhs: Int, _ rhs: Int) -> Int {
    kk_bits_to_float(lhs) >= kk_bits_to_float(rhs) ? 1 : 0
}

// MARK: - Int/Long comparison ops

@_cdecl("kk_op_eq")
public func kk_op_eq(_ lhs: Int, _ rhs: Int) -> Int {
    lhs == rhs ? 1 : 0
}

@_cdecl("kk_op_ne")
public func kk_op_ne(_ lhs: Int, _ rhs: Int) -> Int {
    lhs != rhs ? 1 : 0
}

@_cdecl("kk_op_lt")
public func kk_op_lt(_ lhs: Int, _ rhs: Int) -> Int {
    lhs < rhs ? 1 : 0
}

@_cdecl("kk_op_le")
public func kk_op_le(_ lhs: Int, _ rhs: Int) -> Int {
    lhs <= rhs ? 1 : 0
}

@_cdecl("kk_op_gt")
public func kk_op_gt(_ lhs: Int, _ rhs: Int) -> Int {
    lhs > rhs ? 1 : 0
}

@_cdecl("kk_op_ge")
public func kk_op_ge(_ lhs: Int, _ rhs: Int) -> Int {
    lhs >= rhs ? 1 : 0
}

// MARK: - Unsigned comparison ops (UInt/ULong/UByte/UShort)
//
// UByte/UShort/UInt are always zero-extended into this 64-bit container, so
// their positive range never sets bit 63 and kk_op_lt/le/gt/ge above already
// agree with unsigned ordering for them. ULong is the one unsigned type that
// spans the full 64 bits, so a value >= 2^63 looks negative under signed
// comparison. Reinterpreting both operands as UInt (bitPattern) fixes ULong
// while remaining a no-op for the narrower unsigned types.

@_cdecl("kk_op_ult")
public func kk_op_ult(_ lhs: Int, _ rhs: Int) -> Int {
    UInt(bitPattern: lhs) < UInt(bitPattern: rhs) ? 1 : 0
}

@_cdecl("kk_op_ule")
public func kk_op_ule(_ lhs: Int, _ rhs: Int) -> Int {
    UInt(bitPattern: lhs) <= UInt(bitPattern: rhs) ? 1 : 0
}

@_cdecl("kk_op_ugt")
public func kk_op_ugt(_ lhs: Int, _ rhs: Int) -> Int {
    UInt(bitPattern: lhs) > UInt(bitPattern: rhs) ? 1 : 0
}

@_cdecl("kk_op_uge")
public func kk_op_uge(_ lhs: Int, _ rhs: Int) -> Int {
    UInt(bitPattern: lhs) >= UInt(bitPattern: rhs) ? 1 : 0
}

// MARK: - Int/Long arithmetic ops (flooring division and modulo)

private func runtimeFloorDiv(_ lhs: Int, _ rhs: Int) -> Int {
    if rhs == 0 { return 0 }
    if lhs == Int.min && rhs == -1 { return lhs }
    let quotient = lhs / rhs
    let remainder = lhs % rhs
    if remainder != 0 && ((lhs < 0) != (rhs < 0)) {
        return quotient - 1
    }
    return quotient
}

@_cdecl("kk_op_floor_div")
public func kk_op_floor_div(_ lhs: Int, _ rhs: Int) -> Int {
    runtimeFloorDiv(lhs, rhs)
}

@_cdecl("kk_op_lfloor_div")
public func kk_op_lfloor_div(_ lhs: Int, _ rhs: Int) -> Int {
    // Long uses same Int representation on 64-bit platforms.
    runtimeFloorDiv(lhs, rhs)
}

// PEC-NUM-0002: integer division/remainder must throw ArithmeticException("/ by zero").
// kk_op_div is a throwing callee; outThrown is set and 0 is returned when rhs == 0.
// Int.MIN_VALUE / -1 wraps silently per Kotlin two's-complement semantics.
@_cdecl("kk_op_div")
public func kk_op_div(_ lhs: Int, _ rhs: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if rhs == 0 {
        outThrown?.pointee = runtimeAllocateArithmeticException(message: "/ by zero")
        return 0
    }
    if lhs == Int.min && rhs == -1 { return Int.min }
    return lhs / rhs
}

// PEC-NUM-0002: kk_op_mod is a throwing callee; outThrown is set and 0 returned when rhs == 0.
@_cdecl("kk_op_mod")
public func kk_op_mod(_ lhs: Int, _ rhs: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if rhs == 0 {
        outThrown?.pointee = runtimeAllocateArithmeticException(message: "/ by zero")
        return 0
    }
    if lhs == Int.min && rhs == -1 { return 0 }
    return lhs % rhs
}

// PEC-NUM-0002 / KSP-466: UInt/ULong/UByte/UShort division and remainder must
// reinterpret the raw 64-bit container as unsigned before dividing — plain
// signed `/`/`%` misreads any ULong with the high bit set (>= 2^63) as
// negative. UByte/UShort/UInt are always zero-extended into this container,
// so unsigned reinterpretation is a no-op for them; ULong is the one type
// that actually needs it. Unlike kk_op_div/kk_op_mod there is no INT_MIN/-1
// overflow case to special-case (unsigned division cannot overflow), but
// zero-divisor must still throw ArithmeticException via outThrown.
@_cdecl("kk_op_udiv")
public func kk_op_udiv(_ lhs: Int, _ rhs: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if rhs == 0 {
        outThrown?.pointee = runtimeAllocateArithmeticException(message: "/ by zero")
        return 0
    }
    return Int(bitPattern: UInt(bitPattern: lhs) / UInt(bitPattern: rhs))
}

@_cdecl("kk_op_urem")
public func kk_op_urem(_ lhs: Int, _ rhs: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    if rhs == 0 {
        outThrown?.pointee = runtimeAllocateArithmeticException(message: "/ by zero")
        return 0
    }
    return Int(bitPattern: UInt(bitPattern: lhs) % UInt(bitPattern: rhs))
}

private func runtimeFloorMod(_ lhs: Int, _ rhs: Int) -> Int {
    if rhs == 0 { return 0 }
    if lhs == Int.min && rhs == -1 { return 0 }
    let remainder = lhs % rhs
    if remainder != 0 && ((lhs < 0) != (rhs < 0)) {
        return remainder + rhs
    }
    return remainder
}

@_cdecl("kk_op_floor_mod")
public func kk_op_floor_mod(_ lhs: Int, _ rhs: Int) -> Int {
    runtimeFloorMod(lhs, rhs)
}

@_cdecl("kk_op_lfloor_mod")
public func kk_op_lfloor_mod(_ lhs: Int, _ rhs: Int) -> Int {
    runtimeFloorMod(lhs, rhs)
}

// MARK: - Char operations

@_cdecl("kk_char_rangeTo")
public func kk_char_rangeTo(_ startValue: Int, _ endValue: Int) -> Int {
    let startChar = kk_unbox_char(startValue)
    let endChar = kk_unbox_char(endValue)
    return registerRuntimeObject(RuntimeRangeBox(first: startChar, last: endChar, step: 1))
}
