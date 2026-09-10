package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-1512: signed primitive-array member bridges. The public `size` and
// `toList` declarations below are bundled Kotlin source; these private
// declarations retain only the runtime allocation/boxing work.
@KsSymbolName("__kk_intArray_toList")
private external fun __kkIntArrayToList(array: IntArray): List<Int>

@KsSymbolName("__kk_longArray_toList")
private external fun __kkLongArrayToList(array: LongArray): List<Long>

@KsSymbolName("__kk_shortArray_toList")
private external fun __kkShortArrayToList(array: ShortArray): List<Short>

@KsSymbolName("__kk_byteArray_toList")
private external fun __kkByteArrayToList(array: ByteArray): List<Byte>

@KsSymbolName("__kk_charArray_toList")
private external fun __kkCharArrayToList(array: CharArray): List<Char>

@KsSymbolName("__kk_booleanArray_toList")
private external fun __kkBooleanArrayToList(array: BooleanArray): List<Boolean>

@KsSymbolName("__kk_doubleArray_toList")
private external fun __kkDoubleArrayToList(array: DoubleArray): List<Double>

@KsSymbolName("__kk_floatArray_toList")
private external fun __kkFloatArrayToList(array: FloatArray): List<Float>

@KsSymbolName("__kk_array_toList")
private external fun <T> __kkArrayToList(array: Array<out T>): List<T>

// KSP-1516: array asList() keeps the Kotlin view contract. The runtime bridge
// only creates a List view over the existing array storage; all public array
// conversion APIs below remain ordinary bundled Kotlin declarations.
@KsSymbolName("__kk_array_asList")
private external fun <T> __kkArrayAsList(array: Array<out T>): List<T>

@KsSymbolName("__kk_intArray_asList")
private external fun __kkIntArrayAsList(array: IntArray): List<Int>

@KsSymbolName("__kk_longArray_asList")
private external fun __kkLongArrayAsList(array: LongArray): List<Long>

@KsSymbolName("__kk_shortArray_asList")
private external fun __kkShortArrayAsList(array: ShortArray): List<Short>

@KsSymbolName("__kk_byteArray_asList")
private external fun __kkByteArrayAsList(array: ByteArray): List<Byte>

@KsSymbolName("__kk_charArray_asList")
private external fun __kkCharArrayAsList(array: CharArray): List<Char>

@KsSymbolName("__kk_booleanArray_asList")
private external fun __kkBooleanArrayAsList(array: BooleanArray): List<Boolean>

@KsSymbolName("__kk_doubleArray_asList")
private external fun __kkDoubleArrayAsList(array: DoubleArray): List<Double>

@KsSymbolName("__kk_floatArray_asList")
private external fun __kkFloatArrayAsList(array: FloatArray): List<Float>

// KSP-1512: public signed primitive-array members are source-backed. `size`
// uses the intrinsic declarations in kotlin.ArrayIntrinsics.kt, while
// `toList` delegates to the typed runtime bridge for correct primitive boxing.
public val IntArray.size: Int get() = __kkIntArraySize(this)
public val LongArray.size: Int get() = __kkLongArraySize(this)
public val ShortArray.size: Int get() = __kkShortArraySize(this)
public val ByteArray.size: Int get() = __kkByteArraySize(this)
public val CharArray.size: Int get() = __kkCharArraySize(this)
public val BooleanArray.size: Int get() = __kkBooleanArraySize(this)
public val DoubleArray.size: Int get() = __kkDoubleArraySize(this)
public val FloatArray.size: Int get() = __kkFloatArraySize(this)

// KSP-1513: generic Array<T> members are source-backed. `toList` delegates to
// a runtime copy bridge, while `size` keeps the generic element type intact.
// The parser does not accept a type-parameter list on an extension property;
// a star-projected receiver preserves the generic Array<T> surface.
public val Array<*>.size: Int get() = __kkArraySize(this)
public fun <T> Array<out T>.toList(): List<T> = __kkArrayToList(this)

public fun IntArray.toList(): List<Int> = __kkIntArrayToList(this)
public fun LongArray.toList(): List<Long> = __kkLongArrayToList(this)
public fun ShortArray.toList(): List<Short> = __kkShortArrayToList(this)
public fun ByteArray.toList(): List<Byte> = __kkByteArrayToList(this)
public fun CharArray.toList(): List<Char> = __kkCharArrayToList(this)
public fun BooleanArray.toList(): List<Boolean> = __kkBooleanArrayToList(this)
public fun DoubleArray.toList(): List<Double> = __kkDoubleArrayToList(this)
public fun FloatArray.toList(): List<Float> = __kkFloatArrayToList(this)

// KSP-1516: Array slicing/reversal and primitive-array object conversion are
// source-backed. Typed constructors and indexed access keep allocation and
// boxing at the compiler-provided array boundary.

@Suppress("UNCHECKED_CAST")
public fun <T> Array<T>.sliceArray(indices: Collection<Int>): Array<T> {
    val result = arrayOfNulls<T>(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result as Array<T>
}

public fun IntArray.sliceArray(indices: Collection<Int>): IntArray {
    val result = IntArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

public fun LongArray.sliceArray(indices: Collection<Int>): LongArray {
    val result = LongArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

public fun ShortArray.sliceArray(indices: Collection<Int>): ShortArray {
    val result = ShortArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

public fun ByteArray.sliceArray(indices: Collection<Int>): ByteArray {
    val result = ByteArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

public fun CharArray.sliceArray(indices: Collection<Int>): CharArray {
    val result = CharArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

public fun BooleanArray.sliceArray(indices: Collection<Int>): BooleanArray {
    val result = BooleanArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

public fun DoubleArray.sliceArray(indices: Collection<Int>): DoubleArray {
    val result = DoubleArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

public fun FloatArray.sliceArray(indices: Collection<Int>): FloatArray {
    val result = FloatArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

public fun UByteArray.sliceArray(indices: Collection<Int>): UByteArray {
    val result = UByteArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

public fun UShortArray.sliceArray(indices: Collection<Int>): UShortArray {
    val result = UShortArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

public fun UIntArray.sliceArray(indices: Collection<Int>): UIntArray {
    val result = UIntArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

public fun ULongArray.sliceArray(indices: Collection<Int>): ULongArray {
    val result = ULongArray(indices.size)
    var targetIndex = 0
    for (sourceIndex in indices) {
        result[targetIndex++] = this[sourceIndex]
    }
    return result
}

@Suppress("UNCHECKED_CAST")
public fun <T> Array<T>.sliceArray(indices: IntRange): Array<T> {
    if (indices.start > indices.endInclusive) return copyOfRange(0, 0)
    val result = copyOfRange(indices.start, indices.endInclusive + 1)
    return result as Array<T>
}

public fun IntArray.sliceArray(indices: IntRange): IntArray =
    if (indices.start > indices.endInclusive) IntArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

public fun LongArray.sliceArray(indices: IntRange): LongArray =
    if (indices.start > indices.endInclusive) LongArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

public fun ShortArray.sliceArray(indices: IntRange): ShortArray =
    if (indices.start > indices.endInclusive) ShortArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

public fun ByteArray.sliceArray(indices: IntRange): ByteArray =
    if (indices.start > indices.endInclusive) ByteArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

public fun CharArray.sliceArray(indices: IntRange): CharArray =
    if (indices.start > indices.endInclusive) CharArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

public fun BooleanArray.sliceArray(indices: IntRange): BooleanArray =
    if (indices.start > indices.endInclusive) BooleanArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

public fun DoubleArray.sliceArray(indices: IntRange): DoubleArray =
    if (indices.start > indices.endInclusive) DoubleArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

public fun FloatArray.sliceArray(indices: IntRange): FloatArray =
    if (indices.start > indices.endInclusive) FloatArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

public fun UByteArray.sliceArray(indices: IntRange): UByteArray =
    if (indices.start > indices.endInclusive) UByteArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

public fun UShortArray.sliceArray(indices: IntRange): UShortArray =
    if (indices.start > indices.endInclusive) UShortArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

public fun UIntArray.sliceArray(indices: IntRange): UIntArray =
    if (indices.start > indices.endInclusive) UIntArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

public fun ULongArray.sliceArray(indices: IntRange): ULongArray =
    if (indices.start > indices.endInclusive) ULongArray(0) else copyOfRange(indices.start, indices.endInclusive + 1)

@Suppress("UNCHECKED_CAST")
public fun <T> Array<T>.reversedArray(): Array<T> {
    val length = __kkArraySize(this)
    if (length == 0) return this
    val result = arrayOfNulls<T>(length) as Array<T>
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun IntArray.reversedArray(): IntArray {
    val length = __kkIntArraySize(this)
    if (length == 0) return this
    val result = IntArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun LongArray.reversedArray(): LongArray {
    val length = __kkLongArraySize(this)
    if (length == 0) return this
    val result = LongArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun ShortArray.reversedArray(): ShortArray {
    val length = __kkShortArraySize(this)
    if (length == 0) return this
    val result = ShortArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun ByteArray.reversedArray(): ByteArray {
    val length = __kkByteArraySize(this)
    if (length == 0) return this
    val result = ByteArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun CharArray.reversedArray(): CharArray {
    val length = __kkCharArraySize(this)
    if (length == 0) return this
    val result = CharArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun BooleanArray.reversedArray(): BooleanArray {
    val length = __kkBooleanArraySize(this)
    if (length == 0) return this
    val result = BooleanArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun DoubleArray.reversedArray(): DoubleArray {
    val length = __kkDoubleArraySize(this)
    if (length == 0) return this
    val result = DoubleArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun FloatArray.reversedArray(): FloatArray {
    val length = __kkFloatArraySize(this)
    if (length == 0) return this
    val result = FloatArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun UByteArray.reversedArray(): UByteArray {
    val length = __kkUByteArraySize(this)
    if (length == 0) return this
    val result = UByteArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun UShortArray.reversedArray(): UShortArray {
    val length = __kkUShortArraySize(this)
    if (length == 0) return this
    val result = UShortArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun UIntArray.reversedArray(): UIntArray {
    val length = __kkUIntArraySize(this)
    if (length == 0) return this
    val result = UIntArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun ULongArray.reversedArray(): ULongArray {
    val length = __kkULongArraySize(this)
    if (length == 0) return this
    val result = ULongArray(length)
    var index = 0
    while (index < length) {
        result[length - index - 1] = this[index]
        index++
    }
    return result
}

public fun <T> Array<out T>.asList(): List<T> = __kkArrayAsList(this)
public fun IntArray.asList(): List<Int> = __kkIntArrayAsList(this)
public fun LongArray.asList(): List<Long> = __kkLongArrayAsList(this)
public fun ShortArray.asList(): List<Short> = __kkShortArrayAsList(this)
public fun ByteArray.asList(): List<Byte> = __kkByteArrayAsList(this)
public fun CharArray.asList(): List<Char> = __kkCharArrayAsList(this)
public fun BooleanArray.asList(): List<Boolean> = __kkBooleanArrayAsList(this)
public fun DoubleArray.asList(): List<Double> = __kkDoubleArrayAsList(this)
public fun FloatArray.asList(): List<Float> = __kkFloatArrayAsList(this)

@Suppress("UNCHECKED_CAST")
public fun IntArray.toTypedArray(): Array<Int> {
    val length = __kkIntArraySize(this)
    val result = arrayOfNulls<Int>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<Int>
}

@Suppress("UNCHECKED_CAST")
public fun LongArray.toTypedArray(): Array<Long> {
    val length = __kkLongArraySize(this)
    val result = arrayOfNulls<Long>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<Long>
}

@Suppress("UNCHECKED_CAST")
public fun ShortArray.toTypedArray(): Array<Short> {
    val length = __kkShortArraySize(this)
    val result = arrayOfNulls<Short>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<Short>
}

@Suppress("UNCHECKED_CAST")
public fun ByteArray.toTypedArray(): Array<Byte> {
    val length = __kkByteArraySize(this)
    val result = arrayOfNulls<Byte>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<Byte>
}

@Suppress("UNCHECKED_CAST")
public fun CharArray.toTypedArray(): Array<Char> {
    val length = __kkCharArraySize(this)
    val result = arrayOfNulls<Char>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<Char>
}

@Suppress("UNCHECKED_CAST")
public fun BooleanArray.toTypedArray(): Array<Boolean> {
    val length = __kkBooleanArraySize(this)
    val result = arrayOfNulls<Boolean>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<Boolean>
}

@Suppress("UNCHECKED_CAST")
public fun DoubleArray.toTypedArray(): Array<Double> {
    val length = __kkDoubleArraySize(this)
    val result = arrayOfNulls<Double>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<Double>
}

@Suppress("UNCHECKED_CAST")
public fun FloatArray.toTypedArray(): Array<Float> {
    val length = __kkFloatArraySize(this)
    val result = arrayOfNulls<Float>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<Float>
}

@Suppress("UNCHECKED_CAST")
public fun UByteArray.toTypedArray(): Array<UByte> {
    val length = __kkUByteArraySize(this)
    val result = arrayOfNulls<UByte>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<UByte>
}

@Suppress("UNCHECKED_CAST")
public fun UShortArray.toTypedArray(): Array<UShort> {
    val length = __kkUShortArraySize(this)
    val result = arrayOfNulls<UShort>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<UShort>
}

@Suppress("UNCHECKED_CAST")
public fun UIntArray.toTypedArray(): Array<UInt> {
    val length = __kkUIntArraySize(this)
    val result = arrayOfNulls<UInt>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<UInt>
}

@Suppress("UNCHECKED_CAST")
public fun ULongArray.toTypedArray(): Array<ULong> {
    val length = __kkULongArraySize(this)
    val result = arrayOfNulls<ULong>(length)
    var index = 0
    while (index < length) {
        result[index] = this[index]
        index++
    }
    return result as Array<ULong>
}

// KSP-628 + KSP-629
// List → array conversions (object + signed/unsigned primitive element types).
// Migration source: Sources/Runtime/RuntimeArrayBasics.swift
//   (kk_list_toTypedArray / kk_list_to{Char,Boolean,Short,Double,Float,Int,Long,Byte,UByte,UShort,UInt,ULong}Array)
//
// Fresh storage comes from the array constructors / arrayOfNulls, so only the
// per-array-type allocation core stays in the Swift runtime.

@Suppress("UNCHECKED_CAST")
public fun <T> List<T>.toTypedArray(): Array<T> {
    val size = this.size
    val result = arrayOfNulls<T>(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result as Array<T>
}

public fun List<Char>.toCharArray(): CharArray {
    val size = this.size
    val result = CharArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Boolean>.toBooleanArray(): BooleanArray {
    val size = this.size
    val result = BooleanArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Short>.toShortArray(): ShortArray {
    val size = this.size
    val result = ShortArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Double>.toDoubleArray(): DoubleArray {
    val size = this.size
    val result = DoubleArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Float>.toFloatArray(): FloatArray {
    val size = this.size
    val result = FloatArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Int>.toIntArray(): IntArray {
    val size = this.size
    val result = IntArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Long>.toLongArray(): LongArray {
    val size = this.size
    val result = LongArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Byte>.toByteArray(): ByteArray {
    val size = this.size
    val result = ByteArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<UByte>.toUByteArray(): UByteArray {
    val size = this.size
    val result = UByteArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<UShort>.toUShortArray(): UShortArray {
    val size = this.size
    val result = UShortArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<UInt>.toUIntArray(): UIntArray {
    val size = this.size
    val result = UIntArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<ULong>.toULongArray(): ULongArray {
    val size = this.size
    val result = ULongArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}
