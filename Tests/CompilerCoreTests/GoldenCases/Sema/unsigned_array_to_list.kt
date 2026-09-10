// RF-FIXTURE-005: unsigned array toList() returns a List copy and size stays Int.
package golden.sema

fun unsignedArrayCopies(
    ubytes: UByteArray,
    ushorts: UShortArray,
    uints: UIntArray,
    ulongs: ULongArray
) {
    val ubyteCopy = ubytes.toList()
    val checkedUByte: List<UByte> = ubyteCopy
    val ushortCopy = ushorts.toList()
    val checkedUShort: List<UShort> = ushortCopy
    val uintCopy = uints.toList()
    val checkedUInt: List<UInt> = uintCopy
    val ulongCopy = ulongs.toList()
    val checkedULong: List<ULong> = ulongCopy

    val ubyteSize = ubytes.size
    val checkedUByteSize: Int = ubyteSize
    val ushortSize = ushorts.size
    val checkedUShortSize: Int = ushortSize
    val uintSize = uints.size
    val checkedUIntSize: Int = uintSize
    val ulongSize = ulongs.size
    val checkedULongSize: Int = ulongSize
}
