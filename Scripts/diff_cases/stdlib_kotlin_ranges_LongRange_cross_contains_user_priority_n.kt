operator fun LongRange.contains(value: Int): Boolean = false

fun main() {
    val small = 0L..100L
    val large = 0L..3000000000L
    val intValue: Int = 5
    val intParameter = intValue
    val byteValue: Byte = 5

    println("direct-literal=" + small.contains(5))
    println("in-literal=" + (5 in small))
    println("direct-int=" + small.contains(intValue))
    println("in-int=" + (intValue in small))
    println("direct-int-parameter=" + small.contains(intParameter))
    println("in-int-parameter=" + (intParameter in small))
    println("direct-byte=" + small.contains(byteValue))
    println("in-byte=" + (byteValue in small))
    println("direct-long=" + small.contains(5L))
    println("in-long=" + (5L in small))
    println("direct-large-literal=" + large.contains(2147483648))
    println("in-large-literal=" + (2147483648 in large))
}
