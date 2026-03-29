fun main() {
    // STDLIB-REGEX-098: Line anchors ^ and $
    val lineStart = Regex("^hello")
    println(lineStart.containsMatchIn("hello world"))   // true
    println(lineStart.containsMatchIn("say hello"))     // false

    val lineEnd = Regex("world$")
    println(lineEnd.containsMatchIn("hello world"))     // true
    println(lineEnd.containsMatchIn("world domination")) // false

    // STDLIB-REGEX-098: Word boundaries \b and \B
    val wordBoundary = Regex("\\bcat\\b")
    println(wordBoundary.containsMatchIn("a cat naps"))  // true
    println(wordBoundary.containsMatchIn("concatenate")) // false
    println(wordBoundary.find("a cat naps")?.value)      // cat

    val nonWordBoundary = Regex("cat\\B")
    println(nonWordBoundary.containsMatchIn("concatenate")) // true
    println(nonWordBoundary.containsMatchIn("a cat naps"))  // false

    // STDLIB-REGEX-098: Input boundaries \A and \z
    val inputStart = Regex("\\Ahello")
    println(inputStart.containsMatchIn("hello world"))  // true
    println(inputStart.containsMatchIn("say hello"))    // false

    val inputEnd = Regex("world\\z")
    println(inputEnd.containsMatchIn("hello world"))    // true
    println(inputEnd.containsMatchIn("world domination")) // false

    // STDLIB-REGEX-098: Lookahead (?=...) and (?!...)
    val positiveLookahead = Regex("foo(?=bar)")
    println(positiveLookahead.find("foobar")?.value)    // foo
    println(positiveLookahead.containsMatchIn("foobaz")) // false

    val negativeLookahead = Regex("foo(?!baz)")
    println(negativeLookahead.containsMatchIn("foobar")) // true
    println(negativeLookahead.containsMatchIn("foobaz")) // false

    // STDLIB-REGEX-098: Lookbehind (?<=...) and (?<!...)
    val positiveLookbehind = Regex("(?<=foo)bar")
    println(positiveLookbehind.find("foobar")?.value)   // bar
    println(positiveLookbehind.containsMatchIn("bazbar")) // false

    val negativeLookbehind = Regex("(?<!foo)bar")
    println(negativeLookbehind.containsMatchIn("bazbar")) // true
    println(negativeLookbehind.containsMatchIn("foobar")) // false
}
