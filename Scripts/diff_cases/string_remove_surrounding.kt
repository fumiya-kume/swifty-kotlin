fun main() {
    // 1-arg overload: removeSurrounding(delimiter)
    // Removes delimiter from both start and end if present
    println("**hello**".removeSurrounding("**"))
    println("*hello*".removeSurrounding("*"))
    println("\"quoted\"".removeSurrounding("\""))

    // 1-arg: delimiter not present on both sides -> unchanged
    println("**hello".removeSurrounding("**"))
    println("hello**".removeSurrounding("**"))
    println("hello".removeSurrounding("**"))

    // 1-arg: empty delimiter -> unchanged
    println("hello".removeSurrounding(""))

    // 1-arg: empty string with empty delimiter
    println("".removeSurrounding(""))

    // 1-arg: string equals delimiter twice (prefix+suffix)
    println("****".removeSurrounding("**"))

    // 1-arg: string equals single delimiter (too short)
    println("**".removeSurrounding("**"))

    // 1-arg: delimiter longer than string
    println("hi".removeSurrounding("hello"))

    // 2-arg overload: removeSurrounding(prefix, suffix)
    println("[hello]".removeSurrounding("[", "]"))
    println("<tag>".removeSurrounding("<", ">"))
    println("(wrapped)".removeSurrounding("(", ")"))

    // 2-arg: prefix present but suffix missing -> unchanged
    println("[hello".removeSurrounding("[", "]"))

    // 2-arg: suffix present but prefix missing -> unchanged
    println("hello]".removeSurrounding("[", "]"))

    // 2-arg: neither present -> unchanged
    println("hello".removeSurrounding("[", "]"))

    // 2-arg: empty prefix and suffix
    println("hello".removeSurrounding("", ""))

    // 2-arg: multi-char prefix and suffix
    println("<<hello>>".removeSurrounding("<<", ">>"))
    println("ABChelloXYZ".removeSurrounding("ABC", "XYZ"))

    // 2-arg: prefix/suffix overlap region (string just = prefix + suffix)
    println("[]".removeSurrounding("[", "]"))
    println("<<>>".removeSurrounding("<<", ">>"))

    // 2-arg: prefix longer than string
    println("hi".removeSurrounding("hello", "]"))

    // 2-arg: suffix longer than string
    println("hi".removeSurrounding("[", "hello"))

    // Chain calls
    println("[[hello]]".removeSurrounding("[", "]").removeSurrounding("[", "]"))

    // With string templates
    val delim = "*"
    println("*test*".removeSurrounding(delim))

    // Unicode content
    println("*\u3053\u3093\u306B\u3061\u306F*".removeSurrounding("*"))

    // Return type is String
    val result: String = "xhellox".removeSurrounding("x")
    println(result)
}
