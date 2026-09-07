package golden.sema

import kotlin.text.CharCategory

fun charCategoryCode(): String = CharCategory.UPPERCASE_LETTER.code

fun charCategoryContains(): Boolean = CharCategory.UPPERCASE_LETTER.contains('A')

fun charCategoryEntries(): kotlin.enums.EnumEntries<CharCategory> = CharCategory.entries

fun charCategoryValueOf(): CharCategory = CharCategory.valueOf("LOWERCASE_LETTER")

fun charCategoryValues(): Array<CharCategory> = CharCategory.values()
