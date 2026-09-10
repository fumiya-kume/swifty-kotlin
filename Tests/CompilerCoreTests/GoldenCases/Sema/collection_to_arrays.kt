// RF-FIXTURE-016: Collection.toMutableList and the toXxxArray conversion
// matrix for the signed, unsigned, Boolean, Char, and floating-point element
// types.
@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

package golden.sema

fun collectionToMutable(values: Collection<Int>) {
    val mutable = values.toMutableList()
    val checked: MutableList<Int> = mutable
}

fun collectionToArrays(
    booleans: Collection<Boolean>,
    bytes: Collection<Byte>,
    chars: Collection<Char>,
    doubles: Collection<Double>,
    floats: Collection<Float>,
    ints: Collection<Int>,
    longs: Collection<Long>,
    shorts: Collection<Short>,
    ubytes: Collection<UByte>,
    ushorts: Collection<UShort>,
    uints: Collection<UInt>,
    ulongs: Collection<ULong>
) {
    val booleanArray = booleans.toBooleanArray()
    val checkedBoolean: BooleanArray = booleanArray
    val byteArray = bytes.toByteArray()
    val checkedByte: ByteArray = byteArray
    val charArray = chars.toCharArray()
    val checkedChar: CharArray = charArray
    val doubleArray = doubles.toDoubleArray()
    val checkedDouble: DoubleArray = doubleArray
    val floatArray = floats.toFloatArray()
    val checkedFloat: FloatArray = floatArray
    val intArray = ints.toIntArray()
    val checkedInt: IntArray = intArray
    val longArray = longs.toLongArray()
    val checkedLong: LongArray = longArray
    val shortArray = shorts.toShortArray()
    val checkedShort: ShortArray = shortArray
    val ubyteArray = ubytes.toUByteArray()
    val checkedUByte: UByteArray = ubyteArray
    val ushortArray = ushorts.toUShortArray()
    val checkedUShort: UShortArray = ushortArray
    val uintArray = uints.toUIntArray()
    val checkedUInt: UIntArray = uintArray
    val ulongArray = ulongs.toULongArray()
    val checkedULong: ULongArray = ulongArray
}
