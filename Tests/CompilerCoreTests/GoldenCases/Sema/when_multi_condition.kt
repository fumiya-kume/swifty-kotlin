package golden.sema

fun classify(x: Int): String = when (x) {
    1, 2, 3 -> "few"
    4, 5 -> "some"
    else -> "many"
}
