package golden.sema

fun useLet(): Int = "hello".let { it.length }
fun useRun(): Int = "hello".run { length }
fun useRunWithThis(): Int = "hello".run { this.length }
fun useApply(): String = "hello".apply { println(this.length) }
fun useAlso(): String = "hello".also { println(it) }
fun useWith(): Int = with("hello") { length }
fun useWithThis(): Int = with("hello") { this.length }
