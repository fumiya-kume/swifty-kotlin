fun main() {
    val letUppercase = "hello".let { it.uppercase() }
    println(letUppercase)
    val runLength = "world".run { this.length }
    println(runLength)
    val withLength = with("kotlin") { length }
    println(withLength)
    val applyResult = "applied".apply { println(this.length) }
    println(applyResult)
    val alsoEchoResult = "test".also { println(it) }
    println(alsoEchoResult)
}
