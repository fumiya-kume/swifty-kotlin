private class CustomCharSequence(private val value: String) : CharSequence {
    override val length: Int
        get() = value.length

    override fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

private fun commonPrefix(value: CharSequence, other: CharSequence, ignoreCase: Boolean = false): String =
    value.commonPrefixWith(other, ignoreCase)

private fun commonSuffix(value: CharSequence, other: CharSequence, ignoreCase: Boolean = false): String =
    value.commonSuffixWith(other, ignoreCase)

fun main() {
    // A String passed through a CharSequence-typed boundary uses the new overload.
    val stringValue: CharSequence = "HelloWorld"
    val stringOther: CharSequence = "helloKotlin"
    println(commonPrefix(stringValue, stringOther, true))
    println(commonSuffix(stringValue, "MYWORLD", true))

    // StringBuilder and a user-defined CharSequence both dispatch through CharSequence.
    val builderValue: CharSequence = StringBuilder("prefix-日本語")
    val builderOther: CharSequence = StringBuilder("prefix-日本")
    println(commonPrefix(builderValue, builderOther))

    val customValue: CharSequence = CustomCharSequence("CustomValue")
    val customOther: CharSequence = CustomCharSequence("customSuffix")
    println(commonPrefix(customValue, customOther, true))
    println(commonSuffix(customValue, CustomCharSequence("otherVALUE"), true))

    // Empty, full, and partial matches keep the Kotlin String result contract.
    println(commonPrefix("", "anything"))
    println(commonSuffix("anything", ""))
    println(commonPrefix("same", "same"))
    println(commonSuffix("same", "same"))
    println(commonPrefix("abcdef", "abcxyz"))
    println(commonSuffix("abcdef", "xyzdef"))

    // Common-family boundaries must not return half of a surrogate pair.
    val smile = "\uD83D\uDE00"
    val grin = "\uD83D\uDE01"
    println(commonPrefix("left-$smile", "left-$grin"))
    println(commonSuffix("left-$smile", "right-$smile"))
    println(commonSuffix(StringBuilder("left-$smile"), StringBuilder("right-$smile")))
    println(commonSuffix(CustomCharSequence("left-$smile"), CustomCharSequence("right-$smile")))
}
