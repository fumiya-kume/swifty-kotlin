package golden.sema

const val MAX = 100
const val NAME = "hello"
const val FLAG = true
const val RATE = 3.14
const val NEG = -42

fun useConst(): Boolean = MAX > 50

fun useNegConst(): Int = NEG
