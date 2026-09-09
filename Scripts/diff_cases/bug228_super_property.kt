// BUG-228: a super-qualified property read must bind to the direct
// superclass implementation, rather than the most-derived override.
open class Base {
    open val p = "bp"
}

class Derived : Base() {
    override val p = "dp"

    fun viaSuper() = super.p
}

fun main() {
    println(Derived().viaSuper())
}
