# async_scope

A lightweight concurrency toolset to manage asynchronous tasks in dart.

- [async\_scope](#async_scope)
  - [Motivation](#motivation)
  - [Features](#features)
    - [Example](#example)
  - [Getting started](#getting-started)
  - [Usage](#usage)
  - [Additional information](#additional-information)


## Motivation

This package is loosely inspired by Android coroutine scopes. Dart's concurrency model is (by design) less structured, allowing you to be the architect of your asynchronous behavior. This package provides an easy way to group async tasks and hook them into arbitrary "lifecycles" to facilitate automatic cleanup.


## Features

Using `async_scope` allows you to:
- ✅ create arbitrary (optionally nested) scopes
- ✅ bind asynchronous tasks (`Future`s or `Stream`s)
- ✅ cancel a scope and its bound tasks

What `async_scope` CAN'T do:
- ❌ make *all* `Future`s "cancelable" (only *bound* ones are)
- ❌ automatically clean up unbound source streams

The distinction is subtle but *very important*. Let's try an example.

### Example

Using scopes can help save time and resources by ensuring chains of asynchronous processing stop when they are no longer needed.

```dart
var scope = AsyncScope();

Future<int>     generateIntAsync()    { /* ... */ }
Future<double>  generateDoubleAsync() { /* ... */ }

Future<num> addNumbersAsync() async {
    var intPart = await scope.bindFuture(generateIntAsync());
    var doublePart = await scope.bindFuture(generateDoubleAsync());
    return intPart + doublePart;
}

// (somewhere else...)

void doCleanup() {
    scope.cancelAll();
}
```

If `doCleanup()` was called before `generateIntAsync()` had completed, processing will halt and no further execution will happen inside `addNumbersAsync()` (ie `generateDoubleAsync()` will never be invoked). However, this *does not* mean execution stops for `generateIntAsync()`. Because `Future`s are not cancelable by default, once `generateIntAsync()` is called, an integer will unavoidably be returned eventually. What `scope` *really* does is make sure this value is ignored and no further processing happens with it. 

In other words, if a `Future` or `Stream` didn't come from a `bind...()`, it won't be canceled (because it can't be).


## Getting started

Installing this package is as easy as

```
dart pub add async_scope
```

No further configuration needed!


## Usage

Creating a scope could not be easier.

```dart
var scope = AsyncScope();
```

Optionally, you can nest scopes by providing a parent on creation. When a parent scope is canceled, all its children are canceled along with it.

```dart
var parentScope = AsyncScope();
var childScope = AsyncScope(parentScope);
```

Binding an asynchronous call can be done from an `AsyncScope` or from a `Future`, both are equivalent and return the managed futures.

```dart
var scope = AsyncScope();
Future newFuture1 = scope.bindFuture(someFuture);
Future newFuture2 = someFuture.bindToScope(scope);
```

Likewise, binding streams can be done from either direction as well, both returning managed streams.

```dart
var scope = AsyncScope();
Stream newStream1 = scope.bindStream(someStream);
Stream newStream2 = someStream.bindToScope(scope);
```

You can decide if you want to create `AsyncScope` directly...

```dart
import 'package:async_scope/async_scope.dart';

mixin CustomScopingHook on MyTypeWithCleanup {
  final scope = AsyncScope();

  @override
  void onCleanup() {
    super.onCleanup();
    scope.cancelAll();
  }
}
```

...or use one of the package's predefined hooks.

```dart
import 'package:async_scope/hooks/flutter.dart';

class CustomState extends State<CustomWidget> with StateScoping {
    // StateScoping exposes `AsyncScope scope` to this widget state
}
```


## Additional information

File bugs or feature requests on the [issues page](https://github.com/skylon07/async_scope/issues). Hope this little tool is helpful to you!
