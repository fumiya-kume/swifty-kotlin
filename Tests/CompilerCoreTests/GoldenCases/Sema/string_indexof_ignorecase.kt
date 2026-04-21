package golden.sema

fun useIndexOfIgnoreCase(): Int = "Hello World".indexOf("world", 0, ignoreCase = true)

fun useLastIndexOfIgnoreCase(): Int = "Hello World Hello".lastIndexOf("hello", 20, ignoreCase = true)

fun useIndexOfIgnoreCaseFalse(): Int = "Hello World".indexOf("world", 0, ignoreCase = false)

fun useLastIndexOfIgnoreCaseFalse(): Int = "Hello World Hello".lastIndexOf("Hello", 20, ignoreCase = false)
