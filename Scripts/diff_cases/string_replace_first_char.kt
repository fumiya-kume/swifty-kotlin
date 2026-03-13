fun main() {
    println("hello".replaceFirstChar { it.uppercaseChar() })
    println("Hello".replaceFirstChar { it.lowercaseChar() })
    println("".replaceFirstChar { it.uppercaseChar() })
}
