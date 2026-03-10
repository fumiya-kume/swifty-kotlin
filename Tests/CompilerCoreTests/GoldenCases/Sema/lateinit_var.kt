class Config {
    lateinit var name: String

    fun isReady(): Boolean = ::name.isInitialized

    fun setup() { name = "test" }
}

fun main() {
    val c = Config()
    println(c.isReady())
    try {
        println(c.name)
    } catch (e: Exception) {
        println("caught")
    }
    c.setup()
    println(c.isReady())
    println(c.name)
}
