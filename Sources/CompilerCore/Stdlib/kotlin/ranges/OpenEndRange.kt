package kotlin.ranges

// KSP-1288: source-backed cross-type contains overloads for OpenEndRange.
// Narrowing conversions must reject values that cannot be represented by the
// range element type; a plain toByte()/toShort()/toInt() would wrap instead.

@kotlin.jvm.JvmName("byteRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Byte>.contains(value: Int): Boolean {
    if (value < -128 || value > 127) return false
    return this.contains(value.toByte())
}

@kotlin.jvm.JvmName("byteRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Byte>.contains(value: Long): Boolean {
    if (value < -128L || value > 127L) return false
    return this.contains(value.toByte())
}

@kotlin.jvm.JvmName("byteRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Byte>.contains(value: Short): Boolean {
    if (value < -128 || value > 127) return false
    return this.contains(value.toByte())
}

@kotlin.jvm.JvmName("doubleRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Double>.contains(value: Float): Boolean =
    this.contains(value.toDouble())

@kotlin.jvm.JvmName("intRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Int>.contains(value: Byte): Boolean =
    this.contains(value.toInt())

@kotlin.jvm.JvmName("intRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Int>.contains(value: Long): Boolean {
    if (value < -2147483648L || value > 2147483647L) return false
    return this.contains(value.toInt())
}

@kotlin.jvm.JvmName("intRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Int>.contains(value: Short): Boolean =
    this.contains(value.toInt())

@kotlin.jvm.JvmName("longRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Long>.contains(value: Byte): Boolean =
    this.contains(value.toLong())

@kotlin.jvm.JvmName("longRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Long>.contains(value: Int): Boolean =
    this.contains(value.toLong())

@kotlin.jvm.JvmName("longRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Long>.contains(value: Short): Boolean =
    this.contains(value.toLong())

@kotlin.jvm.JvmName("shortRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Short>.contains(value: Byte): Boolean =
    this.contains(value.toShort())

@kotlin.jvm.JvmName("shortRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Short>.contains(value: Int): Boolean {
    if (value < -32768 || value > 32767) return false
    return this.contains(value.toShort())
}

@kotlin.jvm.JvmName("shortRangeContains")
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun OpenEndRange<Short>.contains(value: Long): Boolean {
    if (value < -32768L || value > 32767L) return false
    return this.contains(value.toShort())
}
