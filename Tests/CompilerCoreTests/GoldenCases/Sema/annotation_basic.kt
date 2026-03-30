package golden.sema

annotation class MyLabel(val name: String = "default")

@MyLabel("hello")
class Foo

@MyLabel
class Bar

annotation class Marker

@Marker
class Baz
