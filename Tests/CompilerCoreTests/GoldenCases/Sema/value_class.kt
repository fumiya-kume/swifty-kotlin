package golden.sema

value class Meter(val value: Int)

fun measure(m: Meter): Int = m.value

fun toAny(m: Meter): Any = m
