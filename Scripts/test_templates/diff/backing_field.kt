class Clamped {
    var value: Int = 0
        set(v) { field = if (v < 0) 0 else v }
}

fun main() {
    val c = Clamped()
    c.value = 10
    println(c.value)
    c.value = -5
    println(c.value)
}
