// BUG-229: An `open` primary-constructor property must be overridable by a
// subclass property, just like an equivalent class-body property.
open class Base(open val p: String)

class Derived(p: String) : Base(p) {
    override val p: String = p + "!"
}

fun main() {
    val value: Base = Derived("base")
    println(value.p)
}
