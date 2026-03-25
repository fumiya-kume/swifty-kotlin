fun main() {
    val d = 3.14
    println(d.toInt())
    println(d.toLong())
    println(d.toFloat())

    val f = 2.5f
    println(f.toInt())
    println(f.toLong())
    println(f.toDouble())

    val l = 42L
    println(l.toFloat())
    println(l.toDouble())
    println(l.toInt())
    println(l.toByte())
    println(l.toShort())

    val i = 100
    println(i.toDouble())
    
    // Test unsigned conversions (STDLIB-PRIM-002)
    println("--- Unsigned Conversions ---")
    
    // Test toUByte, toUShort, toUInt, toULong
    println(i.toUByte())
    println(i.toUShort())
    println(i.toUInt())
    println(i.toULong())
    
    // Test float to unsigned
    println(f.toUInt())
    println(f.toULong())
    
    // Test double to unsigned  
    println(d.toUInt())
    println(d.toULong())
    
    // Test char conversions
    println("--- Char Conversions ---")
    val c = 'A'
    println(c.toByte())
    println(c.toShort())
    println(c.toInt())
    println(c.toLong())
    println(c.toUInt())
    println(c.toULong())
    
    // Test toChar from various types
    println(i.toChar())
    println(l.toChar())
    println(f.toChar())
    println(d.toChar())
    
    // Test edge cases
    println("--- Edge Cases ---")
    val maxInt = Int.MAX_VALUE
    val minInt = Int.MIN_VALUE
    
    println(maxInt.toByte())
    println(minInt.toByte())
    println(maxInt.toShort())
    println(minInt.toShort())
    println(maxInt.toUByte())
    println(minInt.toUByte())
    
    // Test float edge cases
    val nan = Float.NaN
    val posInf = Float.POSITIVE_INFINITY
    val negInf = Float.NEGATIVE_INFINITY
    
    println(nan.toInt())
    println(posInf.toInt())
    println(negInf.toInt())
    println(nan.toUInt())
    println(posInf.toUInt())
    println(negInf.toUInt())
}
