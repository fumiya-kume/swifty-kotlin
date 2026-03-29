import kotlin.uuid.Uuid

fun main() {
    // Uuid.random() creates a valid UUID
    val uuid1 = Uuid.random()
    val uuid2 = Uuid.random()
    println("uuid1 created: ${uuid1.toString().length == 36}")
    println("uuid2 created: ${uuid2.toString().length == 36}")
    println("uuids different: ${uuid1.toString() != uuid2.toString()}")

    // Uuid.parse() round-trips with toString()
    val uuidStr = "550e8400-e29b-41d4-a716-446655440000"
    val parsed = Uuid.parse(uuidStr)
    println("parse roundtrip: ${parsed.toString() == uuidStr}")

    // toHexString() returns 32-char hex string
    val hex = parsed.toHexString()
    println("hex length: ${hex.length == 32}")
    println("hex value: ${hex == "550e8400e29b41d4a716446655440000"}")

    // toLongs() returns Pair<Long, Long>
    val longs = parsed.toLongs()
    println("toLongs not null: ${longs != null}")

    // toByteArray() returns 16-byte array
    val bytes = parsed.toByteArray()
    println("byteArray size: ${bytes.size == 16}")

    // version() and variant()
    val version = parsed.version()
    println("version is 4: ${version == 4}")
    val variant = parsed.variant()
    println("variant is 2: ${variant == 2}")

    // mostSignificantBits and leastSignificantBits
    val msb = parsed.mostSignificantBits
    val lsb = parsed.leastSignificantBits
    println("msb not zero: ${msb != 0L}")
    println("lsb not zero: ${lsb != 0L}")

    // nameUUIDFromBytes() generates a deterministic version-3 UUID
    val nameBytes = byteArrayOf(1, 2, 3, 4, 5)
    val named1 = Uuid.nameUUIDFromBytes(nameBytes)
    val named2 = Uuid.nameUUIDFromBytes(nameBytes)
    println("named uuid length: ${named1.toString().length == 36}")
    println("named uuid deterministic: ${named1.toString() == named2.toString()}")
    println("named uuid version 3: ${named1.version() == 3}")
    println("named uuid variant 2: ${named1.variant() == 2}")

    println("OK")
}
