fun main() {
    val result1 = "hello".let { it.uppercase() }
    println(result1)
    val result2 = "world".run { this.length }
    println(result2)
    val result3 = with("kotlin") { length }
    println(result3)
    val sb = StringBuilder().apply { append("a"); append("b") }
    println(sb.toString())
    val result4 = "test".also { println(it) }
    println(result4)
}
