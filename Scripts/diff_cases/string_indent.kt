fun main() {
    val text = "Hello\nWorld"
    println(text.prependIndent("  "))
    println(text.prependIndent(">>"))
    println("  Hello\n  World".replaceIndent("    "))
    println("  Hello\n  World".replaceIndent())
}
