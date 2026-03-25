package golden.sema

interface WithAbstractProperties {
    val abstractVal: String
    var abstractVar: Int
}

interface WithConcreteProperties {
    val concreteVal: String = "default"
    var concreteVar: Int = 42
    
    val computedVal: String
        get() = "computed"
    
    var computedVar: String
        get() = "get"
        set(value) { }
}

interface WithMixedProperties {
    val abstractVal: String
    val concreteVal: String = "default"
    var abstractVar: Int
    var concreteVar: Int = 42
}

class Implementation : WithMixedProperties {
    override val abstractVal: String = "implemented"
    override var abstractVar: Int = 100
}

class InheritConcreteOnly : WithConcreteProperties

fun main() {
    val impl = Implementation()
    println(impl.abstractVal)
    println(impl.abstractVar)
    println(impl.concreteVal)
    println(impl.concreteVar)
    
    val concrete = InheritConcreteOnly()
    println(concrete.concreteVal)
    println(concrete.concreteVar)
    println(concrete.computedVal)
}
