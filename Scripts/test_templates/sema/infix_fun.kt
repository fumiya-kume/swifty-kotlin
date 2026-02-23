package golden.sema

infix fun Int.add(other: Int): Int = this + other

fun useInfix(): Int = 1 add 2
