fun main() {
    // removePrefix basic cases
    println("hello".removePrefix("he"))
    println("hello".removePrefix("world"))
    println("hello".removePrefix("hello"))
    println("hello".removePrefix(""))
    println("".removePrefix("he"))
    println("".removePrefix(""))

    // removePrefix edge cases
    println("aaa".removePrefix("a"))
    println("abcabc".removePrefix("abc"))
    println("hello".removePrefix("hello world"))

    // removeSuffix basic cases
    println("hello".removeSuffix("lo"))
    println("hello".removeSuffix("world"))
    println("hello".removeSuffix("hello"))
    println("hello".removeSuffix(""))
    println("".removeSuffix("lo"))
    println("".removeSuffix(""))

    // removeSuffix edge cases
    println("aaa".removeSuffix("a"))
    println("abcabc".removeSuffix("abc"))
    println("hello".removeSuffix("say hello"))

    // removeSurrounding with prefix and suffix
    println("[hello]".removeSurrounding("[", "]"))
    println("[hello]".removeSurrounding("(", ")"))
    println("<<hello>>".removeSurrounding("<<", ">>"))
    println("hello".removeSurrounding("", ""))
    println("".removeSurrounding("[", "]"))
    println("[]".removeSurrounding("[", "]"))

    // removeSurrounding with single delimiter
    println("**foo**".removeSurrounding("*"))
    println("\"hello\"".removeSurrounding("\""))
    println("hello".removeSurrounding("*"))
    println("*hello".removeSurrounding("*"))
    println("hello*".removeSurrounding("*"))
    println("".removeSurrounding("*"))
    println("**".removeSurrounding("*"))

    // chaining
    println("<<hello>>".removePrefix("<<").removeSuffix(">>"))
    println("prefix_hello_suffix".removePrefix("prefix_").removeSuffix("_suffix"))

    // removePrefix/removeSuffix with special characters
    println("hello\nworld".removePrefix("hello\n"))
    println("hello\tworld".removeSuffix("\tworld"))
}
