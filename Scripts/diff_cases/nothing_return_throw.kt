class E : RuntimeException()

fun throwOrValue(flag: Boolean): String {
    val x: String = if (flag) "ok" else throw E()
    return x
}

fun returnOrValue(flag: Boolean): Int {
    val x: Int = if (flag) 42 else return -1
    return x
}

fun main() {
    println(throwOrValue(true))
    println(returnOrValue(true))
    println(returnOrValue(false))
}
