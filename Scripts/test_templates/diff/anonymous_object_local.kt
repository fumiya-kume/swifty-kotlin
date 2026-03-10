fun main() {
    val local = object {
        val value = 7
        val doubled = value * 2
    }
    println(local.value)
    println(local.doubled)
}
