// RF-FIXTURE-005: unsigned array asList() returns a List view of the unsigned
// element type.
package golden.sema

fun unsignedArrayViews(
    ubytes: UByteArray,
    ushorts: UShortArray,
    uints: UIntArray,
    ulongs: ULongArray
) {
    val ubyteList = ubytes.asList()
    val checkedUByte: List<UByte> = ubyteList
    val ushortList = ushorts.asList()
    val checkedUShort: List<UShort> = ushortList
    val uintList = uints.asList()
    val checkedUInt: List<UInt> = uintList
    val ulongList = ulongs.asList()
    val checkedULong: List<ULong> = ulongList
}
