package golden.sema

public fun publicFun(): Int = 1
internal fun internalFun(): Int = 2
private fun privateFun(): Int = 3

fun useAll(): Int = publicFun() + internalFun() + privateFun()
