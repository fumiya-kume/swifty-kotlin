fun precedence(x: Int, y: Int): Boolean {
    val a = 1 + 2 * 3
    val b = true || false && false
    val c = 1 + 2 == 3
    val d = 4 / 2 - 1
    val e = a + d * 2 - d / 3
    val f = 1..10 step 2
    val g = 10 downTo 1 step 2
    val h = x shl 2 or y
    return a == 7 && b && c && d == 1
}
