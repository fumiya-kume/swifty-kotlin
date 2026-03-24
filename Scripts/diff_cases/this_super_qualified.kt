open class Base { open fun greet() = "Base" }
class Derived : Base() {
    override fun greet() = "Derived(${super.greet()})"
    inner class Inner {
        fun test() = "Inner sees ${this@Derived.greet()}"
    }
}
fun main() {
    println(Derived().greet())
    println(Derived().Inner().test())
}
