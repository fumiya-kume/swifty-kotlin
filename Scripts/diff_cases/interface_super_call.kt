interface A {
    fun greet(): String = "Hello from A"
}

interface B : A {
    override fun greet(): String = "Hello from B"
}

interface C : A {
    override fun greet(): String = "Hello from C"
}

class D : B, C {
    override fun greet(): String = super<B>.greet() + " and " + super<C>.greet()
}

class E : B, C {
    override fun greet(): String = "D: " + super.greet()
}

class F : B {
    override fun greet(): String = "F: " + super<B>.greet()
}

fun main() {
    val d = D()
    println(d.greet())
    
    val e = E()
    println(e.greet())
    
    val f = F()
    println(f.greet())
}
