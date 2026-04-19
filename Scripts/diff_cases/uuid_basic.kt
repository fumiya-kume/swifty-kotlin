@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

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

    // toByteArray() returns 16-byte array
    val bytes = parsed.toByteArray()
    println("byteArray size: ${bytes.size == 16}")

    // fromByteArray() round-trips with toByteArray()
    val fromBytes = Uuid.fromByteArray(bytes)
    println("fromByteArray roundtrip: ${fromBytes.toString() == uuidStr}")

    println("OK")
}
