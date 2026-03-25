inline fun <reified T> isType(value: Any): Boolean = value is T
inline fun repeat3(action: () -> Unit) { action(); action(); action() }
fun main() {
    println(isType<String>("hello"))
    println(isType<Int>("hello"))
    println(isType<Int>(42))
    var count = 0
    repeat3 { count++ }
    println(count)
}
// SKIP-DIFF: inline reified parity pending
