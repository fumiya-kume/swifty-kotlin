fun throwOrValue(flag: Boolean): String {
    val x: String = if (flag) "ok" else throw IllegalArgumentException("fail")
    return x
}

fun main() {
    println(throwOrValue(true))
}
