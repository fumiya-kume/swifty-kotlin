package golden.sema

import kotlin.reflect.KType
import kotlin.reflect.KTypeProjection
import kotlin.reflect.KVariance

fun projectionVariance(projection: KTypeProjection): KVariance? = projection.variance

fun projectionType(projection: KTypeProjection): KType? = projection.type

fun projectionComponent1(projection: KTypeProjection): KVariance? = projection.component1()

fun projectionComponent2(projection: KTypeProjection): KType? = projection.component2()

fun projectionCopy(projection: KTypeProjection): KTypeProjection = projection.copy()

fun projectionEquals(projection: KTypeProjection, other: Any?): Boolean = projection.equals(other)

fun projectionHashCode(projection: KTypeProjection): Int = projection.hashCode()

fun projectionToString(projection: KTypeProjection): String = projection.toString()
