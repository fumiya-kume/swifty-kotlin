// Demonstrates Kotlin generic type erasure behaviour.
//
// At runtime, generic type arguments are erased.  The JVM (and this compiler)
// therefore cannot distinguish List<String> from List<Int> at runtime.
// Using 'is List<String>' triggers an "unchecked" warning; use 'is List<*>'
// (star-projection) to check only the raw type.

fun checkRawList(v: Any): Boolean = v is List<*>

fun printListSize(v: Any) {
    if (v is List<*>) {
        println(v.size)
    } else {
        println(-1)
    }
}

fun main() {
    val strings: List<String> = listOf("a", "b", "c")
    val ints: List<Int> = listOf(1, 2, 3)

    // Raw-type checks with star-projection work fine at runtime.
    println(checkRawList(strings))   // true
    println(checkRawList(ints))      // true
    println(checkRawList("hello"))   // false
    println(checkRawList(42))        // false

    printListSize(strings)  // 3
    printListSize(ints)     // 3
    printListSize("not a list") // -1
}
