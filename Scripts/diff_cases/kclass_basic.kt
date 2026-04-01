fun main() {
    // STDLIB-REFLECT-060: KClass basic reflection features

    // Class name: simpleName
    println("simpleName: ${String::class.simpleName}")

    // Visibility: isAbstract, isOpen (these work correctly for built-in types)
    println("String isAbstract: ${String::class.isAbstract}")
    println("String isOpen: ${String::class.isOpen}")
}
