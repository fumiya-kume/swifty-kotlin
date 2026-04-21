package golden.sema

fun main() {
    val ubytes = ubyteArrayOf(1.toUByte(), 2.toUByte(), 3.toUByte())
    val ushorts = ushortArrayOf(4.toUShort(), 5.toUShort(), 6.toUShort())
    val uints = uintArrayOf(7u, 8u, 9u)
    val ulongs = (10uL..12uL).toULongArray()

    val ubyteList = ubytes.asList()
    val ushortList = ushorts.asList()
    val uintList = uints.asList()
    val ulongList = ulongs.asList()

    println(ubyteList)
    println(ushortList)
    println(uintList)
    println(ulongList)
}
