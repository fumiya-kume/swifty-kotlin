fun main() {
    val values = mutableListOf(1, 2, 3)
    val iterator = values.listIterator()

    // Forward traversal
    while (iterator.hasNext()) {
        print("${iterator.next()} ")
    }
    println()

    // Backward traversal
    while (iterator.hasPrevious()) {
        print("${iterator.previous()} ")
    }
    println()

    // Mutation: set/add/remove each replace/insert/delete relative to the
    // element last returned by next(). `set`/`add` need a preceding next()
    // (or previous()) call — calling them right after listIterator() throws
    // IllegalStateException in real Kotlin, so this deliberately traverses
    // first.
    val mutable = mutableListOf(1, 2, 3)
    val mutIterator = mutable.listIterator()
    mutIterator.next()
    mutIterator.set(99)
    println(mutable)
    mutIterator.next()
    mutIterator.add(50)
    println(mutable)
    mutIterator.next()
    mutIterator.remove()
    println(mutable)

    // Same mutations against Char/String elements, to catch a primitive
    // (Char) stored unboxed as a bare code point instead of a boxed Char.
    val chars = mutableListOf('a', 'b', 'c')
    val charIterator = chars.listIterator()
    charIterator.next()
    charIterator.set('Z')
    charIterator.next()
    charIterator.add('Q')
    println(chars)

    val strings = mutableListOf("x", "y", "z")
    val stringIterator = strings.listIterator()
    stringIterator.next()
    stringIterator.set("W")
    stringIterator.next()
    stringIterator.add("V")
    println(strings)

    // set()/remove() after previous() (not next()) target the element
    // previous() just returned, not the one before it.
    val values2 = mutableListOf(1, 2, 3, 4)
    val it2 = values2.listIterator(2)
    it2.previous()
    it2.set(20)
    println(values2)
    it2.previous()
    it2.remove()
    println(values2)
}
