package golden.sema

fun useIndexOfIgnoreCase(): Int = "Hello World".indexOf("world", ignoreCase = true)

fun useIndexOfCaseSensitive(): Int = "Hello World".indexOf("world", ignoreCase = false)

fun useIndexOfFromIgnoreCase(): Int = "Hello Hello".indexOf("hello", startIndex = 3, ignoreCase = true)

fun useLastIndexOfIgnoreCase(): Int = "Hello Hello".lastIndexOf("hello", ignoreCase = true)
