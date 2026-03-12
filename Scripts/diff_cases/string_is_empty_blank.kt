fun main() {
    println(if ("".isEmpty()) "true" else "false")
    println(if ("x".isEmpty()) "true" else "false")
    println(if ("  ".isBlank()) "true" else "false")
    println(if ("x".isBlank()) "true" else "false")
    println(if ("".isNotEmpty()) "true" else "false")
    println(if ("x".isNotBlank()) "true" else "false")
}
