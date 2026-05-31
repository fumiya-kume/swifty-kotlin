fun main() {
    // Char.code
    println('A'.code)
    println('0'.code)
    println('\u3042'.code)
    // Char + Int / Char - Int produce Char
    println('A' + 1)
    println(('A' + 1).code)
    println('Z' + 1)
    println('B' - 1)
    // Char - Char produces Int distance
    println('Z' - 'A')
    println('9' - '0')
    // Int.toChar() for in-range code points
    println(65.toChar())
    println(97.toChar())
    println(65.toChar().code)
}
