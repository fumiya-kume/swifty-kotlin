fun main() {
    println("hello".removePrefix("he"))
    println("hello".removeSuffix("lo"))
    println("[hello]".removeSurrounding("[", "]"))
    println("**foo**".removeSurrounding("*"))
}
