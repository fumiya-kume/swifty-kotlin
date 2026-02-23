fun cumulativeNarrow(x: Int?): Int {
    return when {
        x == null -> 0
        x > 0 -> x
        else -> x
    }
}
