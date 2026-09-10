// BUG-221 minimal reproducer: inherited and Any-erased class toString paths.

open class Bug221Base {
    override fun toString(): String = "Base!"
}

class Bug221Derived : Bug221Base()

class Bug221Foo(val x: Int) {
    override fun toString(): String = "Foo($x)"
}

fun main() {
    val derived: Bug221Derived = Bug221Derived()
    println("derived=" + derived)

    val erased: Any = Bug221Foo(1)
    println("any=" + erased)
    println("method=" + erased.toString())
}
