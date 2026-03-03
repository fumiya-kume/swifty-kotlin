package golden.sema

enum class Color { Red, Green, Blue }

fun classify(x: Int): String = when (x) {
    1, 2, 3 -> "few"
    4, 5 -> "some"
    else -> "many"
}

fun classifyColor(c: Color): String = when (c) {
    Color.Red, Color.Green -> "warm"
    Color.Blue -> "cold"
}

fun classifyBool(b: Boolean): String = when (b) {
    true, false -> "always"
}
