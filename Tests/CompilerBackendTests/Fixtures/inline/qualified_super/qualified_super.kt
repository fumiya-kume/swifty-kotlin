inline fun runBlock(block: () -> String): String = block()

interface Left { fun value(): String = "left" }
interface Right { fun value(): String = "right" }

class Both : Left, Right {
    private inline fun inlineLeft(): String = super<Left>.value()
    override fun value(): String = super<Right>.value()
    fun throughInline(): String = inlineLeft()
    fun throughLambda(): String = runBlock { super<Left>.value() }
}

fun main() {
    val both = Both()
    println(both.throughInline())
    println(both.throughLambda())
    println(both.value())
}
