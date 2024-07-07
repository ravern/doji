# Dōji

Practical scripting language for Rust.

## Guide

Here is the "Hello, world!" program for Dōji.

```doji
let { Debug } = import("std");

Debug.info("Hello, world!");
// => Hello, world!
```

Dōji supports all common primitive data types and achieves data composition through (dynamic) arrays and (hash)maps.

```doji
let my_int = 123;
let my_float = 3.14159;
let my_bool = true;
let my_string = "I love Dōji!";

let my_array = [1, 2, 3];
let my_map = { foo: 1, bar: 2, baz: 3 };
```

Functions in Dōji are created using the `fn` keyword. Dōji supports higher-order functions and all functions are closures that capture the entire environment.

```doji
let { Debug } = import("std");

let bar = 3;

let my_function = fn (foo) {
  Debug.info(foo + bar);
  foo
};
```

Most importantly, Dōji's runtime supports concurrency via fibers, which are provided through the standard library.

```doji
let {
  Debug,
  Fiber,
} = import("std");

let my_first_fiber = Fiber.new(fn () {
  Debug.print("Hello from my first fiber!");
});

let my_second_fiber = Fiber.new(fn () {
  Debug.print("Hello from my second fiber!");
});

my_first_fiber.resume();
my_second_fiber.resume();

Debug.info(my_first_fiber.is_done());
// => true
```

Both channels and shared memory can be used for communication between fibers, since Dōji is single-threaded.

```doji
let {
  Debug,
  Fiber,
  Channel,
} = import("std");

let mut my_bar = { bar: null };

let mut my_channel = Channel.new(10);

let my_fiber = Fiber.new(fn () {
  let foo = my_channel.receive();
  foo + " " + my_bar.bar
});

my_bar.bar = "Bar!";
my_channel.send("Foo!");

let foobar = my_fiber.resume();
Debug.info(foobar);
// => Foo! Bar!
```
