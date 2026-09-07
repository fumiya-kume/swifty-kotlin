import kotlin.text.CharCategory

fun main() {
    println(CharCategory.UPPERCASE_LETTER.code)
    println(CharCategory.UPPERCASE_LETTER.contains('A'))
    println(CharCategory.UPPERCASE_LETTER.contains('a'))
    println(CharCategory.entries.size)
    println(CharCategory.valueOf("LOWERCASE_LETTER").code)
    println(CharCategory.values().size)
}
