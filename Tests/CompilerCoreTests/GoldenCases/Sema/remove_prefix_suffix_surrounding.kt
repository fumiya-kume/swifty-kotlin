fun main() {
    // removePrefix
    println("HelloWorld".removePrefix("Hello"))
    println("HelloWorld".removePrefix("Goodbye"))
    println("".removePrefix("prefix"))
    println("prefix".removePrefix("prefix"))

    // removeSuffix
    println("HelloWorld".removeSuffix("World"))
    println("HelloWorld".removeSuffix("Earth"))
    println("".removeSuffix("suffix"))
    println("suffix".removeSuffix("suffix"))

    // removeSurrounding(delimiter) - single arg
    println("[bracketed]".removeSurrounding("["))
    println("***star***".removeSurrounding("***"))
    println("ab".removeSurrounding("ab"))
    println("abc".removeSurrounding("ab"))

    // removeSurrounding(prefix, suffix) - two args
    println("<div>content</div>".removeSurrounding("<div>", "</div>"))
    println("[item]".removeSurrounding("[", "]"))
    println("no-match".removeSurrounding("<", ">"))
}
