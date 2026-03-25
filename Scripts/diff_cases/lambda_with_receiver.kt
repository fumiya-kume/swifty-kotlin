fun buildGreeting(action: StringBuilder.() -> Unit): String {
    val sb = StringBuilder()
    sb.action()
    return sb.toString()
}
fun main() {
    val greeting = buildGreeting {
        append("Hello")
        append(", ")
        append("World!")
    }
    println(greeting)
    val result = with(StringBuilder()) {
        append("Kotlin ")
        append("is ")
        append("fun")
        toString()
    }
    println(result)
}
// SKIP-DIFF: lambda with receiver parity pending
