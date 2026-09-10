private inline fun visit(action: () -> Unit) = action()

private fun choose(first: Boolean): String {
    var value = ""
    if (first) visit { value += "a" } else visit { value += "b" }
    return value
}

private fun select(mode: Int): Int {
    var value = 10
    when (mode) {
        0 -> visit { value += 1 }
        1 -> visit { value += 2 }
        else -> visit { value += 3 }
    }
    return value
}

fun main() {
    println(choose(true))
    println(choose(false))
    println(choose(false))
    println(choose(true))
    println(select(0))
    println(select(1))
    println(select(2))
    println(select(1))
}
