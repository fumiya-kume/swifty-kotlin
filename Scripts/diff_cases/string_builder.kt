fun main() {
    // insert(index, value)
    println(StringBuilder("hello").insert(5, " world").toString())

    // delete(start, end)
    println(StringBuilder("hello world").delete(5, 11).toString())

    // reverse()
    println(StringBuilder("abc").reverse().toString())

    // setCharAt(index, char)
    val sb = StringBuilder("hello")
    sb.setCharAt(0, 'H')
    println(sb.toString())

    // charAt(index)
    val sb2 = StringBuilder("Kotlin")
    println(sb2.charAt(0))

    // replace(start, end, str)
    println(StringBuilder("hello world").replace(6, 11, "Kotlin").toString())

    // capacity() returns a value >= length
    val sb3 = StringBuilder("hi")
    println(sb3.capacity() >= sb3.length)

    // ensureCapacity() is a no-op but must not crash
    sb3.ensureCapacity(100)
    println(sb3.toString())

    // trimToSize() is a no-op but must not crash
    sb3.trimToSize()
    println(sb3.toString())
}
