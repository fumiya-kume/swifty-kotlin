// KSP-1290: UIntRange members retain priority over user extensions, while
// an exact cross-type user extension wins over the bundled source wrapper.
operator fun UIntRange.contains(value: UInt): Boolean {
    println("extension-uint")
    return false
}

operator fun UIntRange.contains(value: ULong): Boolean {
    println("extension-ulong")
    return false
}

fun main() {
    val range: UIntRange = 1u..3u
    println(range.contains(2u))
    println(2u in range)
    println(range.contains(2uL))
    println(2uL in range)
}
