fun main() {
    val sized = CharArray(3)
    println(sized.size)
    println(sized[0].code)

    val initialized = CharArray(3) { Char(it + 65) }
    println(initialized.size)
    println(initialized[0])
    println(initialized[2])
    println(CharArray(0) { 'x' }.size)
}
