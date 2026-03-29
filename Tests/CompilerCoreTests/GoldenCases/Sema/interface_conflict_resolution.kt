package golden.sema

// STDLIB-INHERIT-020: Multiple interface inheritance conflict resolution

interface Base {
    fun method(): String = "Base"
}

interface Left : Base {
    override fun method(): String = "Left"
}

interface Right : Base {
    override fun method(): String = "Right"
}

// Class that overrides to resolve the conflict
class WithOverride : Left, Right {
    override fun method(): String = "Override"
}

// Class that uses super<> for explicit calls
class WithSuperCall : Left, Right {
    override fun method(): String = super<Left>.method() + "+" + super<Right>.method()
}

// Diamond inheritance: A common base, B and C override differently
interface A {
    fun greet(): String = "A"
}

interface B : A {
    override fun greet(): String = "B"
    fun bOnly(): String = "BOnly"
}

interface C : A {
    override fun greet(): String = "C"
    fun cOnly(): String = "COnly"
}

// D must override greet() because B and C both provide conflicting implementations
class D : B, C {
    override fun greet(): String = super<B>.greet() + super<C>.greet()
}
