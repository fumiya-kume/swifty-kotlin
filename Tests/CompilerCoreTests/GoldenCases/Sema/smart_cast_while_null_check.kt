fun whileNullCheck(x: Int?): Int {
    val y: Int = 0
    while (x != null) {
        return x
    }
    return y
}
