private class CustomCharSequence(private val value: String) : CharSequence {
    override val length: Int
        get() = value.length

    override fun get(index: Int): Char = value[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.substring(startIndex, endIndex)
}

fun charSequenceCommonPrefix(value: CharSequence, other: CharSequence): String =
    value.commonPrefixWith(other)

fun charSequenceCommonPrefixIgnoreCase(value: CharSequence, other: CharSequence): String =
    value.commonPrefixWith(other, true)

fun charSequenceCommonSuffix(value: CharSequence, other: CharSequence): String =
    value.commonSuffixWith(other)

fun charSequenceCommonSuffixIgnoreCase(value: CharSequence, other: CharSequence): String =
    value.commonSuffixWith(other, true)

fun stringBuilderCommonPrefix(): String {
    val value: CharSequence = StringBuilder("prefix-日本語")
    return value.commonPrefixWith(StringBuilder("prefix-日本"))
}

fun customCharSequenceCommonSuffix(): String {
    val value: CharSequence = CustomCharSequence("customValue")
    return value.commonSuffixWith(CustomCharSequence("otherVALUE"), true)
}
