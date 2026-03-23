// STDLIB-591: contract { returns() implies condition } smart cast support
import kotlin.contracts.*

// User-defined function with contract { returns() implies (value) }
fun myRequire(value: Boolean) {
    contract {
        returns() implies (value)
    }
    if (!value) throw IllegalArgumentException()
}

fun main() {
    // require(x != null) narrows x to non-null
    val x: String? = "hello"
    require(x != null)
    println(x.length)

    // check(y != null) narrows y to non-null
    val y: String? = "world"
    check(y != null)
    println(y.length)

    // require(a is String) narrows a to String
    val a: Any = "kotlin"
    require(a is String)
    println(a.length)

    // check(b is String) narrows b to String
    val b: Any = "swift"
    check(b is String)
    println(b.length)

    // require with lazy message also narrows
    val c: String? = "lazy"
    require(c != null) { "c must not be null" }
    println(c.length)

    // User-defined function with contract also narrows
    val d: String? = "user"
    myRequire(d != null)
    println(d.length)
}
