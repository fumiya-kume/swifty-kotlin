enum class ComplexEnum {
    A,
    B,
    C {
        override fun toString(): String = "C-special"
    };

    companion object {
        fun fromString(s: String): ComplexEnum? = when (s) {
            "A" -> ComplexEnum.A
            "B" -> ComplexEnum.B
            "C" -> ComplexEnum.C
            else -> null
        }
    }
}

fun main() {
    println("Testing enum initialization order:")
    println(ComplexEnum.A.name)
    println(ComplexEnum.B.name)
    println(ComplexEnum.C.name)

    println("\nTesting fromString with invalid input:")
    println(ComplexEnum.fromString("D"))

    println("\nTesting entries order:")
    val entries = enumEntries<ComplexEnum>()
    println(entries.size)
    println(entries[0])
    println(entries[1])
    println(entries[2])

    println("\nTesting toString override:")
    println(ComplexEnum.C.toString())
}
