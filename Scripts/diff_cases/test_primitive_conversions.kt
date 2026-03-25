fun main() {
    println("Testing primitive conversions (STDLIB-PRIM-002)")
    
    // Test existing conversions
    val d = 3.14
    println("Double to Int: ${d.toInt()}")
    println("Double to Long: ${d.toLong()}")
    println("Double to Float: ${d.toFloat()}")
    
    val f = 2.5f
    println("Float to Int: ${f.toInt()}")
    println("Float to Long: ${f.toLong()}")
    println("Float to Double: ${f.toDouble()}")
    
    val l = 42L
    println("Long to Float: ${l.toFloat()}")
    println("Long to Double: ${l.toDouble()}")
    println("Long to Int: ${l.toInt()}")
    println("Long to Byte: ${l.toByte()}")
    println("Long to Short: ${l.toShort()}")
    
    val i = 100
    println("Int to Double: ${i.toDouble()}")
    
    // Test new UByte conversions
    println("\n--- UByte Conversions ---")
    println("Int to UByte: ${i.toUByte()}")
    println("Int (-5) to UByte: ${(-5).toUByte()}")
    println("Int (300) to UByte: ${300.toUByte()}")
    
    println("UByte to Int: ${i.toUByte().toInt()}")
    println("UByte to Long: ${i.toUByte().toLong()}")
    println("UByte to UInt: ${i.toUByte().toUInt()}")
    println("UByte to ULong: ${i.toUByte().toULong()}")
    
    // Test new UShort conversions
    println("\n--- UShort Conversions ---")
    println("Int to UShort: ${i.toUShort()}")
    println("Int (-5) to UShort: ${(-5).toUShort()}")
    println("Int (70000) to UShort: ${70000.toUShort()}")
    
    println("UShort to Int: ${i.toUShort().toInt()}")
    println("UShort to Long: ${i.toUShort().toLong()}")
    println("UShort to UInt: ${i.toUShort().toUInt()}")
    println("UShort to ULong: ${i.toUShort().toULong()}")
    
    // Test new Char conversions
    println("\n--- Char Conversions ---")
    println("Int to Char: ${65.toChar()}")
    println("Int (0x1F600) to Char: ${0x1F600.toChar()}")
    println("Int (-5) to Char: ${(-5).toChar()}")
    println("Int (0x110000) to Char: ${0x110000.toChar()}")
    
    println("Char to Int: ${'A'.toInt()}")
    println("Char to Long: ${'A'.toLong()}")
    println("Char to UInt: ${'A'.toUInt()}")
    println("Char to ULong: ${'A'.toULong()}")
    
    // Test UInt/ULong to UByte/UShort
    println("\n--- UInt/ULong to UByte/UShort ---")
    val u = 1000u
    println("UInt to UByte: ${u.toUByte()}")
    println("UInt to UShort: ${u.toUShort()}")
    
    val ul = 1000000uL
    println("ULong to UByte: ${ul.toUByte()}")
    println("ULong to UShort: ${ul.toUShort()}")
    
    // Test cross-type conversions
    println("\n--- Cross-Type Conversions ---")
    val ub = 200.toUByte()
    println("UByte to Char: ${ub.toChar()}")
    println("UByte to Float: ${ub.toFloat()}")
    println("UByte to Double: ${ub.toDouble()}")
    
    val us = 50000.toUShort()
    println("UShort to Char: ${us.toChar()}")
    println("UShort to Float: ${us.toFloat()}")
    println("UShort to Double: ${us.toDouble()}")
    
    println("\nAll primitive conversions completed!")
}
