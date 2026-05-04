fun main() {
    println("a:b:c".replaceAfter(":", "X", "MISS"))
    println("abc".replaceAfter(":", "X", "MISS"))
    println("abc".replaceAfter(":", "X"))
    println("abc".replaceAfter("", "X", "MISS"))
    println("abc".replaceAfter("abc", "X", "MISS"))
    println("abc".replaceAfter("c", "X", "MISS"))
    println("a:b:c".replaceAfter(':', "X", "MISS"))
    println("abc".replaceAfter(':', "X", "MISS"))
    println("abc".replaceAfter(':', "X"))
    println("abc".replaceAfter('a', "X", "MISS"))
}
