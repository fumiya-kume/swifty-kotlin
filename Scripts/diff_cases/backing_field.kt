class Clamped {
    var value: Int = 0
        set(v) { field = if (v < 0) 0 else v }
}

fun main() {
    println(42)
}
