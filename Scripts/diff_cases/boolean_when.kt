fun choose(flag: Boolean) = when (flag) {
    true -> 10
    false -> 20
}

fun main() {
    println(choose(true))
    println(choose(false))
}
