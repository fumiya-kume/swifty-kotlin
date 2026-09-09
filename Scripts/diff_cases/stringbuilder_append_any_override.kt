private class BuilderDisplayValue {
    override fun toString(): String = "display"
}

fun main() {
    val value: Any? = BuilderDisplayValue()
    println(StringBuilder().append(value))
    val absent: Any? = null
    println(StringBuilder().append(absent))
}
