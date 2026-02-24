package golden.sema

value class Meter(val amount: Int)

fun measure(m: Meter): Int = m.amount

fun toAny(m: Meter): Any = m
