package golden.sema

fun twoArgInt(): Int = maxOf(3, 7)
fun twoArgMinInt(): Int = minOf(3, 7)

fun threeArgMaxInt(a: Int, b: Int, c: Int): Int = maxOf(a, b, c)
fun threeArgMinInt(a: Int, b: Int, c: Int): Int = minOf(a, b, c)

fun threeArgMaxLong(a: Long, b: Long, c: Long): Long = maxOf(a, b, c)
fun threeArgMinLong(a: Long, b: Long, c: Long): Long = minOf(a, b, c)

fun threeArgMaxDouble(a: Double, b: Double, c: Double): Double = maxOf(a, b, c)
fun threeArgMinDouble(a: Double, b: Double, c: Double): Double = minOf(a, b, c)
