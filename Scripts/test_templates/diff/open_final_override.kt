open class Base {
    open fun foo(): Int = 1
    fun bar(): Int = 2
}

class Derived : Base() {
    override fun foo(): Int = 10
}

fun main() {
    val d = Derived()
    println(d.foo())
    println(d.bar())
}
