package golden.sema

fun classify(x: Int): String = when (x) {
    1, 2, 3 -> "few"
    in 4..10 -> "some"
    else -> "many"
}
