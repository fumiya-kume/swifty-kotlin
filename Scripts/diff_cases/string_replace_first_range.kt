fun main() {
    // replaceFirst
    println("abcabc".replaceFirst("abc", "X"))
    println("hello".replaceFirst("l", "L"))

    // replaceRange
    println("hello".replaceRange(0..2, "HE"))
    println("kotlin".replaceRange(1..4, "ava"))
}
