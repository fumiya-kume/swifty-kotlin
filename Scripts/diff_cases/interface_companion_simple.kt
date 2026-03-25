interface WithCompanion {
    companion object {
        val CONSTANT = "interface constant"
        fun helper(str: String): String = "Helper: $str"
    }
    
    fun doSomething(): String
}

class DefaultImpl : WithCompanion {
    override fun doSomething(): String = "Default implementation"
}

fun main() {
    println(WithCompanion.CONSTANT)
    println(WithCompanion.helper("test"))
    
    val obj = DefaultImpl()
    println(obj.doSomething())
}
