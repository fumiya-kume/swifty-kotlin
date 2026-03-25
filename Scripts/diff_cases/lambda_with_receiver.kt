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
    
    // Test implicit it parameter with receiver
    val numbers = listOf(1, 2, 3, 4, 5)
    val doubled = numbers.map { it * 2 }
    println("Doubled: $doubled")
    
    // Test non-capturing lambda optimization
    val sum = numbers.reduce { acc, n -> acc + n }
    println("Sum: $sum")
}
