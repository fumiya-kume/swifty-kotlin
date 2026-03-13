import kotlin.properties.Delegates

fun main() {
    var name: String by Delegates.notNull()
    name = "hello"
    println(name)
}
