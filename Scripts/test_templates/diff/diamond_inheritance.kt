interface A {
    fun greet(): String = "A"
}

interface B : A {
    override fun greet(): String = "B"
}

interface C : A {
    override fun greet(): String = "C"
}

class D : B, C {
    override fun greet(): String = super<B>.greet() + super<C>.greet()
}

fun main() {
    println(D().greet())
}
