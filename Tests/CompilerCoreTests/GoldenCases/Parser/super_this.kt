package golden.parser

open class Base {
    open fun greet(): String = "hello"
}

class Child : Base() {
    override fun greet(): String = super.greet()
    fun self(): Child = this
}
