fun classify(x: Int, y: Int): Int {
    return when {
        x > 0 -> 1
        y > 0 -> 2
        else -> 0
    }
}
