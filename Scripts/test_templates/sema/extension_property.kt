package golden.sema

val String.firstChar: Char
    get() = this[0]

val String.lastChar: Char
    get() = this[this.length - 1]

fun useExtProp(): Char = "hello".firstChar
