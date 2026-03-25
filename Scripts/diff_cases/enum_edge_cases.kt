enum class ComplexEnum(val value: String) {
    A("a"),
    B("b"),
    C("c") {
        override fun toString(): String = "C-special: $value"
    }
    
    companion object {
        fun fromString(s: String): ComplexEnum? = values.find { it.value == s }
    }
}

fun main() {
    // Test enum initialization order
    println("Testing enum initialization order:")
    ComplexEnum.values().forEach { enum ->
        println("  ${enum.name} = ${enum.value}")
    }
    
    // Test valueOf with invalid input
    println("\nTesting valueOf with invalid input:")
    try {
        ComplexEnum.fromString("d")
        println("Found: d") // This shouldn't print
    } catch (e: IllegalArgumentException) {
        println("Correctly caught exception: ${e.message}")
    }
    
    // Test entries order consistency
    println("\nTesting entries order:")
    val entries1 = ComplexEnum.entries.toList()
    val entries2 = ComplexEnum.entries.toList()
    println("First call: $entries1")
    println("Second call: $entries2")
    
    // Test toString override
    val specialC = ComplexEnum.C
    println("\nTesting toString override:")
    println("C.toString(): $specialC")
}
