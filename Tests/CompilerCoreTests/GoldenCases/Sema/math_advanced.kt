package golden.sema

import kotlin.math.*

fun testAtan2(): Double = atan2(1.0, 1.0)
fun testHypot(): Double = hypot(3.0, 4.0)

fun testCoerceIn(x: Int): Int = x.coerceIn(1, 10)
fun testCoerceAtLeast(x: Int): Int = x.coerceAtLeast(0)
fun testCoerceAtMost(x: Int): Int = x.coerceAtMost(100)

fun testMaxOf3(a: Int, b: Int, c: Int): Int = maxOf(a, b, c)
fun testMinOf3(a: Int, b: Int, c: Int): Int = minOf(a, b, c)
