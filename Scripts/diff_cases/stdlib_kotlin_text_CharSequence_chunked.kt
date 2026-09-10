fun main() {
    println("abcdef".chunked(2) { it.length })
    println("abcde".chunked(3) { it.toString() })

    val chars: CharSequence = "abcdefg"
    println(chars.chunked(4) { it.toString().uppercase() })
    println("".chunked(2) { it.length })
    println("hi".chunked(100) { it.length })

    try {
        "abc".chunked(0) { it.length }
        println("no exception")
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
