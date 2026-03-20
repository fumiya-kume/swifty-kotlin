fun main() {
    // STDLIB-597: RegexOption.MULTILINE basic behavior
    // MULTILINE makes ^ and $ match start/end of each line, not just the whole string
    val multilineText = "first\nsecond\nthird"

    // Without MULTILINE: ^ only matches start of string
    val noMultiline = Regex("^[a-z]+")
    val matchesNoML = noMultiline.findAll(multilineText).toList()
    println("Without MULTILINE count: ${matchesNoML.size}")
    println("Without MULTILINE: ${matchesNoML.map { it.value }}")

    // With MULTILINE: ^ matches start of each line
    val withMultiline = Regex("^[a-z]+", RegexOption.MULTILINE)
    val matchesML = withMultiline.findAll(multilineText).toList()
    println("With MULTILINE count: ${matchesML.size}")
    println("With MULTILINE: ${matchesML.map { it.value }}")

    // MULTILINE with $ anchor
    val endPattern = Regex("[a-z]+$", RegexOption.MULTILINE)
    val endMatches = endPattern.findAll(multilineText).toList()
    println("MULTILINE end count: ${endMatches.size}")
    println("MULTILINE end: ${endMatches.map { it.value }}")

    // containsMatchIn with MULTILINE
    val caretRegex = Regex("^second", RegexOption.MULTILINE)
    println("containsMatchIn MULTILINE: ${caretRegex.containsMatchIn(multilineText)}")
    val caretNoML = Regex("^second")
    println("containsMatchIn no MULTILINE: ${caretNoML.containsMatchIn(multilineText)}")

    // matchEntire with MULTILINE (should still require full string match)
    val entireML = Regex("^first$", RegexOption.MULTILINE)
    println("matchEntire MULTILINE full: ${entireML.matchEntire(multilineText)}")
    println("matchEntire MULTILINE first line: ${entireML.matchEntire("first")?.value}")

    // find with MULTILINE
    val findML = Regex("^second", RegexOption.MULTILINE)
    println("find MULTILINE: ${findML.find(multilineText)?.value}")
    val findNoML = Regex("^second")
    println("find no MULTILINE: ${findNoML.find(multilineText)?.value}")

    // replace with MULTILINE
    val replaceML = Regex("^[a-z]", RegexOption.MULTILINE)
    println("replace MULTILINE: ${replaceML.replace(multilineText, "X")}")

    // split with MULTILINE
    val input = "aaa\nbbb\nccc"
    val splitML = Regex("^b+", RegexOption.MULTILINE)
    println("split MULTILINE: ${splitML.split(input)}")

    // pattern property preserved
    println("pattern: ${withMultiline.pattern}")
}
