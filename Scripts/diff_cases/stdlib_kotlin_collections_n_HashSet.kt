// KSP-936: source-backed kotlin.collections.HashSet keeps its nominal class
// identity while reusing the shared mutable-set storage and operation bridges.

fun main() {
    val source: HashSet<Int> = HashSet<Int>()
    source.add(1)
    source.add(1)
    source.add(2)

    val sized = HashSet<Int>(8)
    sized.add(6)
    println(sized.size)

    val copied = HashSet(source)
    source.add(3)
    copied.add(4)

    println(source.size)
    println(copied.size)
    println(copied is HashSet<*>)
    println(copied is MutableSet<*>)

    val mutable: MutableSet<Int> = copied
    mutable.add(5)
    println(copied.size)
    println(copied.contains(3))
    println(source.contains(4))

    val expected = HashSet(listOf(1, 2, 4, 5))
    println(copied == expected)
    println(copied.hashCode() == expected.hashCode())

    var iterated = ""
    for (value in copied) {
        iterated += "$value,"
    }
    println(iterated)
}
