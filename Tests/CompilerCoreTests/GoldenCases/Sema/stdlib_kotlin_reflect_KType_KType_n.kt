package golden.sema

import kotlin.reflect.KClassifier
import kotlin.reflect.KType
import kotlin.reflect.KTypeProjection

fun classifier(type: KType): KClassifier? = type.classifier

fun arguments(type: KType): List<KTypeProjection> = type.arguments

fun markedNullable(type: KType): Boolean = type.isMarkedNullable
