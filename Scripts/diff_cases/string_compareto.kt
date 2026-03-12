fun main() {
    println("abc".compareTo("abc"))
    println("abc".compareTo("def"))
    println("def".compareTo("abc"))
    println("abc".compareTo("ABC", true))
    println("abc".compareTo("ABC", false))
}
