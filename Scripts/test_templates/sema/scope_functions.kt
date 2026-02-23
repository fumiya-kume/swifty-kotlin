package golden.sema

fun useLet(): Int = "hello".let { it.length }

fun useRun(): Int = "hello".run { length }

fun useApply(): StringBuilder = StringBuilder().apply { append("hello") }

fun useAlso(): String = "hello".also { println(it) }
