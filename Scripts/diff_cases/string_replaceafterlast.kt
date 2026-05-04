fun main() {
    println("a:b:c".replaceAfterLast(":", "X", "MISS"))
    println("abc".replaceAfterLast(":", "X", "MISS"))
    println("abc".replaceAfterLast(":", "X"))
    println("abc".replaceAfterLast("", "X", "MISS"))
    println("".replaceAfterLast("", "X", "MISS"))
    println("abc".replaceAfterLast("abc", "X", "MISS"))
    println("abc".replaceAfterLast("c", "X", "MISS"))
    println("a:b:c".replaceAfterLast(':', "X", "MISS"))
    println("abc".replaceAfterLast(':', "X", "MISS"))
    println("abc".replaceAfterLast(':', "X"))
    println("abc".replaceAfterLast('a', "X", "MISS"))
}
