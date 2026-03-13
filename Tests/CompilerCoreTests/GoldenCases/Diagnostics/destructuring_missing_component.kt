class NoComponents(val value: Int)

fun destructuringError() {
    val nc = NoComponents(42)
    val (a, b) = nc
}

fun forDestructuringError() {
    val items = listOf(1, 2, 3)
    for ((x, y) in items) {
        println(x)
    }
}
