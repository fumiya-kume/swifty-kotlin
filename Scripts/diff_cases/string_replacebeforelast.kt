fun main() {
    println("a:b:c".replaceBeforeLast(":", "X", "MISS"))
    println("abc".replaceBeforeLast(":", "X", "MISS"))
    println("abc".replaceBeforeLast(":", "X"))
    println("abc".replaceBeforeLast("", "X", "MISS"))
    println("".replaceBeforeLast("", "X", "MISS"))
    println("abc".replaceBeforeLast("abc", "X", "MISS"))
    println("abc".replaceBeforeLast("a", "X", "MISS"))
    println("a:b:c".replaceBeforeLast(':', "X", "MISS"))
    println("abc".replaceBeforeLast(':', "X", "MISS"))
    println("abc".replaceBeforeLast(':', "X"))
    println("abc".replaceBeforeLast('c', "X", "MISS"))
    println("abc".replaceBeforeLast('a', "X", "MISS"))
}
