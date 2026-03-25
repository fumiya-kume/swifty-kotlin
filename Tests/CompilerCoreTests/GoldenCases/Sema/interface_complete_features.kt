package golden.sema

// Test interface properties - abstract and concrete
interface InterfaceProperties {
    val abstractVal: String
    var abstractVar: Int
    
    val concreteVal: String = "default"
    var concreteVar: Int = 42
    
    val computedVal: String
        get() = "computed"
    
    var computedVar: String
        get() = "get"
        set(value) { }
}

interface InterfaceSuperCalls {
    fun greet(): String = "Hello"
}

interface LeftSuper : InterfaceSuperCalls {
    override fun greet(): String = "Left"
}

interface RightSuper : InterfaceSuperCalls {
    override fun greet(): String = "Right"
}

class WithSuperCall : LeftSuper, RightSuper {
    override fun greet(): String = super<LeftSuper>.greet() + " and " + super<RightSuper>.greet()
}

// Test interface companion object
interface WithCompanion {
    companion object {
        val CONSTANT = "test"
        fun helper(): String = "helper"
    }
    
    fun doSomething(): String
}

class CompanionImpl : WithCompanion {
    override fun doSomething(): String = "done"
}
