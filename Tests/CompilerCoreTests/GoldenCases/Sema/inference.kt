fun choose(flag: Boolean, left: Int, right: Int): Int = if (flag) left else right

fun useWhen(v: Int) = when (v) {
    1 -> choose(true, v, 0)
    else -> choose(false, 0, v)
}
