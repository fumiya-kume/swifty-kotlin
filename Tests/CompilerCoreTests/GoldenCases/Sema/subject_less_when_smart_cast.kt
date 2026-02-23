fun nullGuard(x: Int?, y: Int?): Int {
    return when {
        x != null -> x
        y != null -> y
        else -> 0
    }
}
