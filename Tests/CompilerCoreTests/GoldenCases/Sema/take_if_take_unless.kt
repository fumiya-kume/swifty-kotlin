package golden.sema

fun useTakeIf(): Int? = 42.takeIf { it > 0 }
fun useTakeUnless(): Int? = 42.takeUnless { it > 0 }
fun useTakeIfFalse(): Int? = 42.takeIf { it < 0 }
fun useTakeUnlessFalse(): Int? = 42.takeUnless { it < 0 }
