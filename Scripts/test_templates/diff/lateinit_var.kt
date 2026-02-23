class Config {
    lateinit var name: String

    fun isReady(): Boolean = ::name.isInitialized

    fun setup() { name = "test" }
}

fun main() {
    val c = Config()
    println(c.isReady())   // false
    c.setup()
    println(c.isReady())   // true
    println(c.name)        // test
}
