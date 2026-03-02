open class Base {
    open fun foo(): Int = 1
}

class Derived : Base() {
    override fun foo(): Int = 10
}

fun main() {
    println(Base().foo())
    println(Derived().foo())
}
