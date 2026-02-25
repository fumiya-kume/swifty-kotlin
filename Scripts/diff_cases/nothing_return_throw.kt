fun returnOrValue(flag: Boolean): String {
    val x: String = if (flag) "hello" else return "fallback"
    return x
}

fun main() {
    println(returnOrValue(true))
    println(returnOrValue(false))
}
