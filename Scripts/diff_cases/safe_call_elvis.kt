fun main() {
    val s: String? = "Hello"
    val n: String? = null
    println(s?.length)
    println(n?.length)
    println(s?.uppercase())
    println(n?.uppercase() ?: "default")
    println(s?.length ?: -1)
    println(n?.length ?: -1)
    val chain: String? = s?.reversed()?.uppercase()
    println(chain)
    println(n?.reversed()?.uppercase())
}
