fun main() {
    println('A'.isLetter())
    println('1'.isDigit())
    println(' '.isWhitespace())
    println('7'.isLetterOrDigit())
    println('\uD800'.isHighSurrogate())  // true
    println('\uDC00'.isLowSurrogate())   // true
    println('\uD800'.isSurrogate())      // true
    println('A'.isSurrogate())           // false
    println('\u0001'.isISOControl())     // true
    println('A'.isISOControl())          // false
    println('\u01C5'.isTitleCase())      // true
    println('A'.isTitleCase())           // false
}
