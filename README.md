# Zettel

A simple scripting language.

```js
class Fib {
  constructor init(self) {
    self.a = 0
    self.b = 1
  }
  fn next(self) {
    self.a, self.b = self.b, self.a + self.b
    return self.a
  }
}

fib := Fib.init()
while n := fib.next(); n < 1000 {
  print(n)
}
```

Classes as namespaces.

```js
//! Vector.zettel
constructor init(self, x, y) {
  self.x = x
  self.y = y
}
fn add(a, b) {
  return init(a.x + b.x, a.y + b.y)
}
fn dot(a, b) {
  return a.x * b.x + a.y * b.y
}
UNIT_X := init(1, 0)

//! main.zettel
import "Vector.zettel"
a := Vector.init(1, 2)
b := Vector.init(2, 3)
a = a.add(b) // Vector(3, 5)
x := a.dot(Vector.UNIT_X) // 3
```

The above is identical to the following:

```js
class Vector {
  constructor init(self, x, y) {
    // ...
  }
  // ...
}

a := Vector.init(1, 2)
// ...
```

```js
import "zettel:http"
import "zettel:fs"
words := http.fetch("https://api.linku.la/words").json()
for word in words {
  file := fs.File.init(word.id + ".md")
  file.write("# " + word.id + "\n")
}
```

`.thing` is syntax sugar for `"thing"`. This is useful for small status or state things, like `.ok` and `.err` instead of `"ok"` and `"err"`. Strings are all interned so they also compare quickly (/^▽^)/.

```js
fn divide(a, b) {
  if b == 0 {
    return nil, .err
  } else {
    return a / b, .ok
  }
}
```

This is also nice for declaring dictionaries. The following are equivalent:

```js
[ "name" = "John", "grade" = 100 ]
[ .name = "John", .grade = 100 ]
```
