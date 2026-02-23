fun multiGuard(a: Int, b: Int, c: Int): String {
    return when {
        a > 0 -> "positive_a"
        b > 0 -> "positive_b"
        c > 0 -> "positive_c"
        else -> "all_non_positive"
    }
}

fun noElseGuard(x: Int): Int {
    val result = 0
    when {
        x > 10 -> result
        x > 0 -> result
    }
    return result
}

fun boolExhaustive(): Int {
    return when {
        true -> 1
        false -> 0
    }
}
