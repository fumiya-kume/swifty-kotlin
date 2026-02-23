class Config {
    lateinit var name: String

    fun setup() { name = "test" }
}

fun main() {
    val c = Config()
    c.setup()
    println(c.name)
}
