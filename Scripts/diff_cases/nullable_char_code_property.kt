private fun code(value: Char?): Int? = value?.code

fun main() {
    val letter: Char? = 'a'
    println(letter?.code)
    println(code('\u0000'))
    println(code('\uD83D'))
    println(code('\uDE00'))
    println(code('\uFFFF'))
    println(code(null))
    val erased: Any? = letter?.code
    println(erased is Int)
    println(erased)
    println(letter?.code == 97)
}
