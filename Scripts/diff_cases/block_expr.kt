fun ifBlock(flag: Boolean): Int {
    val result = if (flag) {
        val x = 10; x + 1
    } else {
        val y = 20; y + 2
    }
    return result
}

fun whenBlock(v: Int): Int {
    val result = when (v) {
        0 -> { val a = 100; a + 1 }
        else -> { val b = 200; b + 2 }
    }
    return result
}

fun main() {
    println(ifBlock(true))
    println(ifBlock(false))
    println(whenBlock(0))
    println(whenBlock(5))
}
