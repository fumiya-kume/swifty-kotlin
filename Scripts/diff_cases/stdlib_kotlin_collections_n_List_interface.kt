fun main() {
    var calls = 0
    val values = List(4) { index ->
        calls += 1
        index * 3
    }

    println(values.size)
    println(calls)
    println(values[1])
    println(values.getOrNull(8))
    println(values.getOrElse(8) { -1 })
    println(values.elementAt(2))

    try {
        List(-1) { 0 }
    } catch (error: IllegalArgumentException) {
        println(error.message)
    }
}
