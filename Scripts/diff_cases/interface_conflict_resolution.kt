interface Base {
    fun method(): String = "Base"
}

interface Left : Base {
    override fun method(): String = "Left"
}

interface Right : Base {
    override fun method(): String = "Right"
}

class SimpleConflict : Left, Right {
    // Should require override
}

class WithOverride : Left, Right {
    override fun method(): String = "Override"
}

class WithSuperCall : Left, Right {
    override fun method(): String = super<Left>.method() + " + " + super<Right>.method()
}

open class ConcreteBase {
    open fun method(): String = "Base"
}

class SuperPriority : ConcreteBase(), Left, Right {
    // Should prefer ConcreteBase.method() without requiring an override
}

interface LeftInt {
    fun overload(value: Int): String = "LeftInt:$value"
}

interface RightString {
    fun overload(value: String): String = "RightString:$value"
}

class SignatureAwareInheritance : LeftInt, RightString {
    // Different signatures should not conflict
}

interface A {
    fun default1(): String = "A1"
    fun default2(): String = "A2"
    abstract fun abstract1(): String
}

interface B : A {
    override fun default1(): String = "B1"
    fun default3(): String = "B3"
}

interface C : A {
    override fun default2(): String = "C2"
    fun default4(): String = "C4"
}

class ComplexInheritance : B, C {
    override fun abstract1(): String = "Implemented"
    // Should inherit: default1 from B, default2 from C, default3 from B, default4 from C
}

fun main() {
    val withOverride = WithOverride()
    println(withOverride.method())
    
    val withSuper = WithSuperCall()
    println(withSuper.method())
    
    val complex = ComplexInheritance()
    println(complex.default1())
    println(complex.default2())
    println(complex.default3())
    println(complex.default4())
    println(complex.abstract1())

    val superPriority = SuperPriority()
    println(superPriority.method())

    val signatureAware = SignatureAwareInheritance()
    println(signatureAware.overload(1))
    println(signatureAware.overload("x"))
}
