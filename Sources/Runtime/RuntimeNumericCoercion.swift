
// UByte / UShort / Char conversions (STDLIB-PRIM-002).
//
// Split out from `RuntimeNumericCompat.swift`.



@_cdecl("kk_uint_to_int")
public func kk_uint_to_int(_ value: Int) -> Int {
    Int(Int32(truncatingIfNeeded: value))
}

@_cdecl("kk_ulong_to_int")
public func kk_ulong_to_int(_ value: Int) -> Int {
    Int(Int32(truncatingIfNeeded: value))
}

@_cdecl("kk_int_to_uint")
public func kk_int_to_uint(_ value: Int) -> Int {
    Int(UInt32(truncatingIfNeeded: kk_unbox_int(value)))
}

@_cdecl("kk_long_to_uint")
public func kk_long_to_uint(_ value: Int) -> Int {
    Int(UInt32(truncatingIfNeeded: value))
}

@_cdecl("kk_int_to_long")
public func kk_int_to_long(_ value: Int) -> Int {
    // value may be a boxed Int (RuntimeIntBox) when converting from a nullable
    // Int expression (e.g. `digitToIntOrNull(radix)!!.toLong()`), so unbox first
    // before reinterpreting the raw bits as a Long.
    kk_unbox_int(value)
}

@_cdecl("kk_uint_to_long")
public func kk_uint_to_long(_ value: Int) -> Int {
    value
}

@_cdecl("kk_int_to_ulong")
public func kk_int_to_ulong(_ value: Int) -> Int {
    kk_unbox_int(value)
}

@_cdecl("kk_long_to_ulong")
public func kk_long_to_ulong(_ value: Int) -> Int {
    value
}

@_cdecl("kk_uint_to_ulong")
public func kk_uint_to_ulong(_ value: Int) -> Int {
    value
}

// MARK: - Unsigned toByte / toShort Conversions (SPEC-NUM-0007)

@_cdecl("kk_uint_to_byte")
public func kk_uint_to_byte(_ value: Int) -> Int {
    Int(Int8(truncatingIfNeeded: value))
}

@_cdecl("kk_uint_to_short")
public func kk_uint_to_short(_ value: Int) -> Int {
    Int(Int16(truncatingIfNeeded: value))
}

@_cdecl("kk_ulong_to_byte")
public func kk_ulong_to_byte(_ value: Int) -> Int {
    Int(Int8(truncatingIfNeeded: value))
}

@_cdecl("kk_ulong_to_short")
public func kk_ulong_to_short(_ value: Int) -> Int {
    Int(Int16(truncatingIfNeeded: value))
}

@_cdecl("kk_ubyte_to_byte")
public func kk_ubyte_to_byte(_ value: Int) -> Int {
    Int(Int8(truncatingIfNeeded: value))
}

@_cdecl("kk_ubyte_to_short")
public func kk_ubyte_to_short(_ value: Int) -> Int {
    // UByte (0..255) always fits in Int16, identity
    value
}

@_cdecl("kk_ushort_to_byte")
public func kk_ushort_to_byte(_ value: Int) -> Int {
    Int(Int8(truncatingIfNeeded: value))
}

@_cdecl("kk_ushort_to_short")
public func kk_ushort_to_short(_ value: Int) -> Int {
    Int(Int16(truncatingIfNeeded: value))
}

// MARK: - Unsigned toFloat / toDouble Conversions

@_cdecl("kk_uint_to_float")
public func kk_uint_to_float(_ value: Int) -> Int {
    kk_float_to_bits(Float(UInt32(truncatingIfNeeded: value)))
}

@_cdecl("kk_uint_to_double")
public func kk_uint_to_double(_ value: Int) -> Int {
    kk_double_to_bits(Double(UInt32(truncatingIfNeeded: value)))
}

@_cdecl("kk_ulong_to_float")
public func kk_ulong_to_float(_ value: Int) -> Int {
    kk_float_to_bits(Float(UInt64(bitPattern: Int64(value))))
}

@_cdecl("kk_ulong_to_double")
public func kk_ulong_to_double(_ value: Int) -> Int {
    kk_double_to_bits(Double(UInt64(bitPattern: Int64(value))))
}

@_cdecl("kk_ubyte_to_float")
public func kk_ubyte_to_float(_ value: Int) -> Int {
    kk_float_to_bits(Float(value))
}

@_cdecl("kk_ubyte_to_double")
public func kk_ubyte_to_double(_ value: Int) -> Int {
    kk_double_to_bits(Double(value))
}

@_cdecl("kk_ushort_to_float")
public func kk_ushort_to_float(_ value: Int) -> Int {
    kk_float_to_bits(Float(value))
}

@_cdecl("kk_ushort_to_double")
public func kk_ushort_to_double(_ value: Int) -> Int {
    kk_double_to_bits(Double(value))
}

// MARK: - UByte and UShort Conversions (STDLIB-PRIM-002)

@_cdecl("kk_int_to_ubyte")
public func kk_int_to_ubyte(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: kk_unbox_int(value)))
}

@_cdecl("kk_int_to_ushort")
public func kk_int_to_ushort(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: kk_unbox_int(value)))
}

@_cdecl("kk_long_to_ubyte")
public func kk_long_to_ubyte(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_long_to_ushort")
public func kk_long_to_ushort(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_uint_to_ubyte")
public func kk_uint_to_ubyte(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_uint_to_ushort")
public func kk_uint_to_ushort(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_ulong_to_ubyte")
public func kk_ulong_to_ubyte(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_ulong_to_ushort")
public func kk_ulong_to_ushort(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_ubyte_to_int")
public func kk_ubyte_to_int(_ value: Int) -> Int {
    // UByte is always in valid range for Int
    value
}

@_cdecl("kk_ushort_to_int")
public func kk_ushort_to_int(_ value: Int) -> Int {
    // UShort is always in valid range for Int
    value
}

@_cdecl("kk_ubyte_to_long")
public func kk_ubyte_to_long(_ value: Int) -> Int {
    // UByte is always in valid range for Long
    value
}

@_cdecl("kk_ushort_to_long")
public func kk_ushort_to_long(_ value: Int) -> Int {
    // UShort is always in valid range for Long
    value
}

@_cdecl("kk_ubyte_to_ushort")
public func kk_ubyte_to_ushort(_ value: Int) -> Int {
    // UByte (0-255) always fits in UShort (0-65535), identity
    value
}

@_cdecl("kk_ushort_to_ubyte")
public func kk_ushort_to_ubyte(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_ubyte_to_uint")
public func kk_ubyte_to_uint(_ value: Int) -> Int {
    // UByte is always in valid range for UInt
    value
}

@_cdecl("kk_ushort_to_uint")
public func kk_ushort_to_uint(_ value: Int) -> Int {
    // UShort is always in valid range for UInt
    value
}

@_cdecl("kk_ubyte_to_ulong")
public func kk_ubyte_to_ulong(_ value: Int) -> Int {
    // UByte is always in valid range for ULong
    value
}

@_cdecl("kk_ushort_to_ulong")
public func kk_ushort_to_ulong(_ value: Int) -> Int {
    // UShort is always in valid range for ULong
    value
}

// MARK: - Char Conversions (STDLIB-PRIM-002)

@_cdecl("kk_int_to_char")
public func kk_int_to_char(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: kk_unbox_int(value)))
}

@_cdecl("kk_uint_to_char")
public func kk_uint_to_char(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_ulong_to_char")
public func kk_ulong_to_char(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_ubyte_to_char")
public func kk_ubyte_to_char(_ value: Int) -> Int {
    // UByte is always in valid range for Char
    value
}

@_cdecl("kk_ushort_to_char")
public func kk_ushort_to_char(_ value: Int) -> Int {
    // UShort is always in valid range for Char
    value
}

// MARK: - Additional Unsigned Conversions (STDLIB-PRIM-002)


@_cdecl("kk_byte_to_uint")
public func kk_byte_to_uint(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_short_to_uint")
public func kk_short_to_uint(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_byte_to_ulong")
public func kk_byte_to_ulong(_ value: Int) -> Int {
    Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_short_to_ulong")
public func kk_short_to_ulong(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: value))
}

// MARK: - Additional Char Conversions (STDLIB-PRIM-002)

@_cdecl("kk_byte_to_char")
public func kk_byte_to_char(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: Int8(truncatingIfNeeded: value)))
}

@_cdecl("kk_short_to_char")
public func kk_short_to_char(_ value: Int) -> Int {
    Int(UInt16(truncatingIfNeeded: Int16(truncatingIfNeeded: value)))
}

func runtimeMakeStringPointer(_ value: String) -> UnsafeMutableRawPointer {
    value.withCString { cString in
        cString.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    }
}

func runtimeNormalizedShift(_ value: Int) -> Int {
    Int(UInt(bitPattern: value) & UInt(Int.bitWidth - 1))
}
