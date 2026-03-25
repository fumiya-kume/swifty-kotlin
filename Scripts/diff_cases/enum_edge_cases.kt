enum class ComplexEnum(val value: String) {
    A("a"),
    B("b"),
    C("c") {
        override fun toString(): String = "C-special: $value"
    }
    
    companion object {
        fun fromString(s: String): ComplexEnum? = entries.find { it.value == s }
    }
}

fun dumpEntries(label: String, values: List<ComplexEnum>) {
    println(label)
    println("size=${values.size}")
    values.forEach { value ->
        println("[${value.name}:${value.value}]")
    }
}

fun main() {
    // Test enum initialization order
    println("Testing enum initialization order:")
    ComplexEnum.values().forEach { enum ->
        println("  ${enum.name} = ${enum.value}")
    }
    
    // Test nullable lookup with invalid input
    println("\nTesting fromString with invalid input:")
    println(ComplexEnum.fromString("d"))
    
    // Test entries order consistency
    println("\nTesting entries order:")
    val entries1 = ComplexEnum.entries.toList()
    val entries2 = ComplexEnum.entries.toList()
    dumpEntries("First call:", entries1)
    dumpEntries("Second call:", entries2)
    
    // Test toString override
    val specialC = ComplexEnum.C
    println("\nTesting toString override:")
    println("C.toString(): $specialC")
}
