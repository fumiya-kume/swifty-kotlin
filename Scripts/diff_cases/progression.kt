fun main() {
    // Test IntProgression.fromClosedRange
    println("=== IntProgression.fromClosedRange ===")
    val intProg = IntProgression.fromClosedRange(1, 10, 2)
    println(intProg.first)
    println(intProg.last)
    println(intProg.step)
    println(intProg.toList())
    
    // Test LongProgression.fromClosedRange
    println("\n=== LongProgression.fromClosedRange ===")
    val longProg = LongProgression.fromClosedRange(1L, 10L, 3)
    println(longProg.first)
    println(longProg.last)
    println(longProg.step)
    println(longProg.toList())
    
    // Test UIntProgression.fromClosedRange
    println("\n=== UIntProgression.fromClosedRange ===")
    val uintProg = UIntProgression.fromClosedRange(1u, 10u, 2)
    println(uintProg.first)
    println(uintProg.last)
    println(uintProg.step)
    println(uintProg.toList())
    
    // Test ULongProgression.fromClosedRange
    println("\n=== ULongProgression.fromClosedRange ===")
    val ulongProg = ULongProgression.fromClosedRange(1UL, 10UL, 3)
    println(ulongProg.first)
    println(ulongProg.last)
    println(ulongProg.step)
    println(ulongProg.toList())
    
    // Test step validation
    println("\n=== Step validation ===")
    try {
        val invalidProg = IntProgression.fromClosedRange(1, 10, 0)
    } catch (e: IllegalArgumentException) {
        println("Caught expected exception: ${e.message}")
    }
    
    // Test reversed progression
    println("\n=== Reversed progression ===")
    val revInt = intProg.reversed()
    println(revInt.first)
    println(revInt.last)
    println(revInt.step)
    println(revInt.toList())
    
    val revUInt = uintProg.reversed()
    println(revUInt.first)
    println(revUInt.last)
    println(revUInt.step)
    println(revUInt.toList())
    
    // Test UInt range operations
    println("\n=== UInt range operations ===")
    val uintRange = 1u..10u
    println(uintRange.first)
    println(uintRange.last)
    println(uintRange.toList())
    
    val uintStep = uintRange step 3
    println(uintStep.first)
    println(uintStep.last)
    println(uintStep.toList())
    
    val uintDown = 10u downTo 1u
    println(uintDown.first)
    println(uintDown.last)
    println(uintDown.toList())
    
    // Test ULong range operations
    println("\n=== ULong range operations ===")
    val ulongRange = 1UL..10UL
    println(ulongRange.first)
    println(ulongRange.last)
    println(ulongRange.toList())
    
    val ulongStep = ulongRange step 3
    println(ulongStep.first)
    println(ulongStep.last)
    println(ulongStep.toList())
    
    val ulongDown = 10UL downTo 1UL
    println(ulongDown.first)
    println(ulongDown.last)
    println(ulongDown.toList())
    
    // Test empty progressions
    println("\n=== Empty progressions ===")
    val emptyInt = IntProgression.fromClosedRange(10, 1, 1)
    println(emptyInt.isEmpty())
    println(emptyInt.toList())
    
    val emptyUInt = UIntProgression.fromClosedRange(10u, 1u, 1)
    println(emptyUInt.isEmpty())
    println(emptyUInt.toList())
}
