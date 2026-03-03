fun main() {
    val len = "hello".let { it.length }
    println(len)

    val upper = "hello".run { uppercase() }
    println(upper)

    val sb = StringBuilder().apply {
        append("hello ")
        append("world")
    }
    println(sb)
}
