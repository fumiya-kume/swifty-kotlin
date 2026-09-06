class Config {
    lateinit var name: String
}

fun main() {
    val c = Config()
    try {
        println(c.name)
    } catch (e: Throwable) {
        println(e)
        println(e.toString())
        println(e.message)
    }

    val ise = IllegalStateException("boom")
    println(ise)
    println("tag: " + ise)
}
