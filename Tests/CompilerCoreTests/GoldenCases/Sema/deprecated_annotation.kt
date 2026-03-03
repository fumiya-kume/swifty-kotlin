package golden.sema

@Deprecated("Use newFun instead", level = DeprecationLevel.ERROR)
fun oldFunError(): Int = 1

@Deprecated("Use newFun instead")
fun oldFunWarning(): Int = 2

fun newFun(): Int = 3

fun caller(): Int = oldFunError() + oldFunWarning() + newFun()
