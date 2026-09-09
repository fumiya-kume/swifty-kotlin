package golden.sema

fun makeULongArray(): ULongArray {
    val empty = ulongArrayOf()
    val values = ulongArrayOf(0uL, 9223372036854775808uL, ULong.MAX_VALUE)
    return ulongArrayOf(1uL, *values, empty.size.toULong())
}

fun compareULong(): Int {
    val high = 9223372036854775808uL
    return if (0uL < high && high > 0uL && ULong.MAX_VALUE >= high) 1 else 0
}

fun divideULong(): ULong = 17663719463477156090uL / 2uL

fun remainderULong(): ULong = 17663719463477156090uL % 7uL

fun convertULongToDouble(value: ULong): Double = value.toDouble()

fun convertULongToFloat(value: ULong): Float = value.toFloat()
