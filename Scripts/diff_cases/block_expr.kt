fun whenBlock(v: Int): Int = when (v) {
    0 -> { val a = 100; a + 1 }
    1 -> { val b = 200; b + 2 }
    else -> { val c = 300; c + 3 }
}

fun main() {
    println(whenBlock(0))
    println(whenBlock(1))
    println(whenBlock(5))
}
