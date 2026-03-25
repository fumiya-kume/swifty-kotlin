interface WithCompanion {
    companion object {
        const val CONSTANT = "interface constant"
        fun factory(): WithCompanion = DefaultImpl()
        fun helper(str: String): String = "Helper: $str"
    }
    
    fun doSomething(): String
}

class DefaultImpl : WithCompanion {
    override fun doSomething(): String = "Default implementation"
}

interface WithNamedCompanion {
    companion object Factory {
        fun create(): WithNamedCompanion = NamedImpl()
        val version: String = "1.0"
    }
    
    fun getName(): String
}

class NamedImpl : WithNamedCompanion {
    override fun getName(): String = "Named implementation"
}

fun main() {
    // Access interface companion members
    println(WithCompanion.CONSTANT)
    println(WithCompanion.helper("test"))
    
    val obj1 = WithCompanion.factory()
    println(obj1.doSomething())
    
    // Access named companion
    println(WithNamedCompanion.Factory.version)
    val obj2 = WithNamedCompanion.Factory.create()
    println(obj2.getName())
}
