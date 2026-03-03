package golden.sema

val Int.doubled: Int
    get() = this * 2

val Int.isPositive: Boolean
    get() = this > 0

fun useExtProp(): Int = 5.doubled
