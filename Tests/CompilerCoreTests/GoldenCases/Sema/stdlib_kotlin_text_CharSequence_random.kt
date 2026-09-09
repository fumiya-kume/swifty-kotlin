package golden.sema

import kotlin.random.Random

fun randomOnCharSequence(value: CharSequence): Char = value.random()

fun randomOnCharSequenceSeeded(value: CharSequence, random: Random): Char = value.random(random)

fun randomOrNullOnCharSequence(value: CharSequence): Char? = value.randomOrNull()

fun randomOrNullOnCharSequenceSeeded(value: CharSequence, random: Random): Char? = value.randomOrNull(random)

fun randomOnString(): Char = "abc".random()

fun randomOnStringSeeded(random: Random): Char = "abc".random(random)

fun randomOrNullOnString(): Char? = "abc".randomOrNull()

fun randomOrNullOnStringSeeded(random: Random): Char? = "abc".randomOrNull(random)
