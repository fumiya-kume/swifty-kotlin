fun classify(v: Int) = when (v) {
    0 -> 10
    else -> 20
}

fun main() {
    println(classify(0))
    println(classify(2))
}
