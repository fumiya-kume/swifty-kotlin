fun precedence(): Boolean {
    val a = 1 + 2 * 3
    val b = true || false && false
    val c = 1 + 2 == 3
    val d = 4 / 2 - 1
    return a == 7 && b && c && d == 1
}
