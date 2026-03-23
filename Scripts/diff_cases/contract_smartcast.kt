fun main() {
    // require(x != null) smart cast
    val x: String? = "hello"
    require(x != null)
    println(x.length)

    // check(x != null) smart cast
    val y: String? = "world"
    check(y != null)
    println(y.length)

    // require with is-check smart cast
    val a: Any = "kotlin"
    require(a is String)
    println(a.length)

    // check with is-check smart cast
    val b: Any = "swift"
    check(b is String)
    println(b.length)

    // require with lazy message
    val c: String? = "lazy"
    require(c != null) { "c must not be null" }
    println(c.length)

    // Compound conditions with && in require
    val d: String? = "compound"
    val e: String? = "both"
    require(d != null && e != null)
    println(d.length + e.length)
}
