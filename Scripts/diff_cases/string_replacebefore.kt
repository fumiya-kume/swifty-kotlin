fun main() {
    println("a:b:c".replaceBefore(":", "X", "MISS"))
    println("abc".replaceBefore(":", "X", "MISS"))
    println("abc".replaceBefore(":", "X"))
    println("abc".replaceBefore("", "X", "MISS"))
    println("".replaceBefore("", "X", "MISS"))
    println("abc".replaceBefore("abc", "X", "MISS"))
    println("abc".replaceBefore("a", "X", "MISS"))
    println("a:b:c".replaceBefore(':', "X", "MISS"))
    println("abc".replaceBefore(':', "X", "MISS"))
    println("abc".replaceBefore(':', "X"))
    println("abc".replaceBefore('c', "X", "MISS"))
}
