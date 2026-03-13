import kotlin.properties.Delegates

var name: String by Delegates.notNull()

fun main() {
    name = "hello"
    println(name)
}
