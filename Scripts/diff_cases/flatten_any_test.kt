fun main() {
    // Test Any type printing
    println("=== Any type printing ===")
    val anyList: List<Any> = listOf(1, "a", 2.5, true)
    println(anyList)
    
    // Test flatten with simple types first
    println("\n=== Simple flatten ===")
    println(listOf(listOf(1, 2), listOf(3, 4)).flatten())
    println(listOf(listOf<String>(), listOf("x")).flatten())
}
