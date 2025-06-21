# scopely

Enhances Dart's `async`/`await` model with structured concurrency utilities.

- [scopely](#scopely)
  - [Motivation](#motivation)
  - [Features](#features)
  - [Getting started](#getting-started)
  - [Usage](#usage)
    - [AsyncScope](#asyncscope)
    - [StreamLifecycleTransformer](#streamlifecycletransformer)
    - [mergeStreams()](#mergestreams)
    - [Stream.asFutures() extension](#streamasfutures-extension)
  - [Additional information](#additional-information)


## Motivation

This package is loosely inspired by Android's coroutine scopes. Dart's concurrency model is intentionally less structured, allowing libraries to design their own architectures for managing asynchronous tasks. This package provides an easy way to group async tasks together and tie them into arbitrary lifecycles, enabling automatic and reliable cleanup.


## Features

This library is centered around `AsyncScope`, a utility for running asynchronous tasks as a cancelable group. It enables patterns where task lifecycles can be seamlessly and efficiently tied to external lifecycles (such as Flutter `State`s) to handle cleanup automatically.

Additional utilities include:
- `StreamLifecycleTransformer`: Add custom hooks to a `StreamController`-like interface without all the boilerplate.
- `mergeStreams`: Combine multiple streams into a single stream with a collective output.
- `Stream.asFutures`: Turn a stream into a list of futures for an improved error handling experience.

These tools work independently but are designed to compose well with existing Dart code, offering a more robust and maintainable approach to async programming.


## Getting started

Installing this package is as easy as

```
dart pub add scopely
```

No further configuration needed!


## Usage

### AsyncScope

This is the biggest feature `scopely` has to offer. `AsyncScope`s allow you to take full control over your async task management, saving you time and effort when making sure streams (and even futures!) are cleaned up correctly.

What `AsyncScope` **can** do:
- ✅ easily convert any existing `Future`, `Stream`, or callback/listener into a scope-bound, cancelable version
- ✅ effortlessly introduce automatic task cleanup into any existing architecture, piecewise or from the ground up

Here's a working example of a mixin that can be applied to your Flutter `State`s:

```dart
import 'package:flutter/widgets.dart';

mixin StateScoping on State {
  final scope = AsyncScope();

  @override
  void dispose() {
    scope.cancelAll();
    super.dispose();
  }
}
```

Using it is very straightforward, even if you're refactoring existing code!

```dart
class _MyState extends State<MyWidget> with StateScoping {
  String data = "";

  @override
  void initState() {
    super.initState();

    // `scope` provided by the mixin
    scope.bindStream(someStream).listen((data) {
      // can use `data` with confidence this `State` is still active!
    });

    void scrollListener() { /* ... */ }
    widget.scrollController.addListener(scrollListener);

    // arbitrary cancellation tasks can be added
    var cancelListener = scope.addCancelListener(() {
      widget.scrollController.removeListener(scrollListener);
    });
    // ...and called early if you want!
    cancelListener.cancelEarly();
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () async {
        // existing code can simply add `.inScope(scope)`
        // to become cancelable!
        var data = await someFetch().inScope(scope);

        // you don't even have to check `mounted`; the scope's futures/streams
        // guarantee `mounted == true` if it is canceled in `dispose()`
        setState(() => this.data = data);
      },
      child: Text(data),
    );
  }
}
```

What `AsyncScope` **can't** do:
- ❌ make *all* `Future`s cancelable (only *bound* ones are)
- ❌ manage or automatically clean up unbound source streams

These distinctions are subtle but *very important*. Let's try an example:

```dart
var scope = AsyncScope();

Future<int>     generateIntAsync()    { /* ... */ }
Future<double>  generateDoubleAsync() { /* ... */ }

Future<num> addNumbersAsync() async {
    var intPart = await generateIntAsync().inScope(scope);
    var doublePart = await generateDoubleAsync().inScope(scope);
    return intPart + doublePart;
}

// (somewhere else...)

void doCleanup() {
    scope.cancelAll();
}
```

If `doCleanup()` was called before `generateIntAsync()` had completed, processing will halt and no further execution will happen inside `addNumbersAsync()` (ie `generateDoubleAsync()` will never be invoked). However, this *does not* mean execution stops for `generateIntAsync()`. Because `Future`s are not inherently cancelable, once `generateIntAsync()` is called, an integer will unavoidably be eventually returned. What `scope` *really* does in this scenario is ensure the value is ignored and no further processing can happen with it. 

In other words, if a `Future` or `Stream` didn't come from a `bind...()` or `inScope()` call, it won't be tracked, and therefore can't be canceled.

You might notice some uncaught `TaskCancellationException`s while your program is running. If you do, rest assured, your program does not have errors and `scopely` is not broken. These are signals sent from bound futures/streams that trick Dart into stopping their execution immediately. If you find them unsavory or annoying, you can use `AsyncScope.catchAllCancellations()` to filter them out and keep your stack clean.


### StreamLifecycleTransformer

If you've ever tried to implement your own `Stream` before, chances are you've heard of a `StreamController`. If you've ever tried to use a `StreamController` before, you know they can very quickly turn into a pile of boilerplate when all you wanted to do was make some small change to your stream. If you've had that problem before, then `StreamLifecycleTransformer` will transform your life with streams.

Imagine converting `stream1` into `stream2` via some `controller`. If you were to do *absolutely nothing* to the stream (but leave room for modifications), you'd still end up writing all of this:

```dart
Stream<T> forwardStream<T>(Stream<T> source) {
  StreamSubscription? subscription;
  late final controller = StreamController<T>(
    onListen: () {
      subscription = source.listen(
        (event) {
          controller.add(event);
        },
        onError: (error, stackTrace) {
          controller.addError(error, stackTrace);
        },
        onDone: () {
          controller.close();
        },
      );
    },
    onCancel: () {
      subscription?.cancel();
      if (!source.isBroadcast) {
        await controller.close();
      }
    },
    onPause: () {
      subscription?.pause();
    },
    onResume: () {
      subscription?.resume();
    }
  );
  return controller.stream;
}
```

That's a lot of "something" for not really doing anything. (There's also a subtle error handling problem with listening to `source` in this way -- if `source.listen()` throws an error, it gets silently swallowed up!) Doesn't it seem like there must be a better way to automate all of this, and focus solely on changing what happens when subscriptions are canceled, or replacing how `onError` handles errors? Well, now there is! By using a `StreamLifecycleTransformer`, you can virtually eliminate all the boilerplate from the previous example:

```dart
Stream<T> forwardStream<T>(Stream<T> source) {
  return source.transform(_ForwardStreamTransformer());
}

class _ForwardStreamTransformer<T> extends StreamLifecycleTransformer<T> {
  @override
  void sourceOnData(TransformerContext<T, T> context, T event) {
    context.destController.add(event);
  }
}
```

The best part? You aren't sacrificing *any* flexibility by using this transformer. You want to log when a subscription cancellation happens?

```dart
class _ForwardStreamTransformer<T> extends StreamLifecycleTransformer<T> {
  @override
  FutureOr<StreamSubscription<EventT>?> destOnCancel(TransformerContext<T, T> context) {
    print("subscription canceled");
    return super.destOnCancel(context);
  }

  @override
  void sourceOnData(TransformerContext<T, T> context, T event) {
    context.destController.add(event);
  }
}
```

Easy. Want to *completely replace* how error handling works?

```dart
class _ForwardStreamTransformer<T> extends StreamLifecycleTransformer<T> {
  @override
  void sourceOnData(TransformerContext<T, T> context, T event) {
    context.destController.add(event);
  }

  @override
  void sourceOnError(TransformerContext<T, T> context, Object error, StackTrace stackTrace) {
    // you don't have to call `super`, only when you want to!
    /* super.sourceOnError(context, error, stackTrace); */

    print("An error happened! $error");
  }
}
```

It's got you covered. Every hook is overridable, most are replaceable. You can read the docs for each to learn when if you need to override it, when you should defer to the default behavior, etc.


### mergeStreams()

Created to make `StreamLifecycleTransformer` more theoretically complete, but in a much safer way.

`mergeStreams()` simply takes a list of streams and returns a new stream that emits lists of values, each list containing the latest values of each given stream in order. This can be useful in situations where you want to process data from multiple streams at once, like combining them to be used in a single `StreamBuilder` in Flutter. There are also more type-safe variations that use records (for merging up to ten streams at once). For example:

```dart
Stream<String> names;
Stream<String> emails;
await for (var (name, email) in mergeStreams2(names, emails)) {
  // runs if either `names` or `emails` emits a new event
}
```

And that's pretty much it!


### Stream.asFutures() extension

One limitation of `await for` loops is every stream subscription is treated as if `cancelOnError: true`. In other words, by default, there's no way to catch stream errors in the inner `try catch` block:

```dart
try {
  await for (var event in stream) {
    try {
      // process `event`...
    } catch (errorInsideLoop) {
      // uh oh! this only catches errors from processing `event` *after*
      // it was emitted, not errors emitted from the stream itself!
    }
  }
} catch (errorOutsideLoop) {
  // this catches errors from the stream, but it's outside the loop!
}
```

With the `.asFutures()` extension method though, everything becomes possible! You have full control over when the event is handled, when/where exceptions should go, etc:

```dart
try {
  await for (var eventFuture in stream.asFutures()) {
    try {
      var event = await eventFuture;
      // process `event`...
    } on Exception catch (errorInsideLoop) {
      // nice! this catches errors emitted from the stream now!
    }
  }
} on Error catch (errorOutsideLoop) {
  // this can catch its own set of errors that should still break the loop
}
```

Ultimately, it just gives you more fine-grained flow control for a stream's events.


## Additional information

File bugs or feature requests on the [issues page](https://github.com/skylon07/scopely/issues). Hope these tools are helpful to you!
