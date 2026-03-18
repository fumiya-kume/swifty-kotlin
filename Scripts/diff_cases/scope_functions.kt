fun main() {
    val letUppercase = "hello".let { it.uppercase() }
    println(letUppercase)
    val runLength = "world".run { this.length }
    println(runLength)
    val withLength = with("kotlin") { length }
    println(withLength)
    val sb = StringBuilder().apply {
        append("a")
        append("b")
    }
    println(sb.toString())
    val alsoEchoResult = "test".also { println(it) }
    println(alsoEchoResult)
}
