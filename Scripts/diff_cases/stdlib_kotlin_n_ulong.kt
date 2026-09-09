fun main() {
    val empty = ulongArrayOf()
    val values = ulongArrayOf(0uL, 9223372036854775808uL, ULong.MAX_VALUE)
    val spread = ulongArrayOf(1uL, *values, 9uL)
    val spreadOnly = ulongArrayOf(*values)
    spreadOnly[0] = 42uL

    println(empty.size)
    println(values.size)
    println(values[0])
    println(values[1])
    println(values[2])
    println(spread.size)
    println(spread[0])
    println(spread[1])
    println(spread[3])
    println(values[0])
    println(spreadOnly[0])

    println(0uL.compareTo(0uL))
    println(0uL.compareTo(9223372036854775808uL))
    println(9223372036854775808uL.compareTo(0uL))
    println(9223372036854775808uL.compareTo(ULong.MAX_VALUE))
    println(ULong.MAX_VALUE.compareTo(9223372036854775808uL))
    println(ULong.MAX_VALUE.compareTo(ULong.MAX_VALUE))
    println(ULong.MAX_VALUE.compareTo(0uL))

    val high = 17663719463477156090uL
    println(high / 2uL)
    println(high % 7uL)
    println(ULong.MAX_VALUE / 2uL)
    println(ULong.MAX_VALUE % 2uL)
    try {
        println(high / 0uL)
    } catch (error: ArithmeticException) {
        println("div by zero caught")
    }
    try {
        println(high % 0uL)
    } catch (error: ArithmeticException) {
        println("rem by zero caught")
    }

    println(0uL.toDouble())
    println(9223372036854775808uL.toDouble())
    println(ULong.MAX_VALUE.toDouble())
    println(0uL.toFloat())
    println(9223372036854775808uL.toFloat())
    println(ULong.MAX_VALUE.toFloat())
}
