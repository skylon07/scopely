/// Enhances Dart's `async`/`await` model with structured concurrency utilities.
///
/// This library is centered around [AsyncScope], a utility for running asynchronous tasks
/// as a cancelable group. It enables patterns where task lifecycles can be seamlessly
/// and efficiently tied to external lifecycles (such as Flutter `State`s) to handle
/// cleanup automatically.
///
/// Additional utilities include:
/// - `StreamLifecycleTransformer`: Add custom hooks to a `StreamController`-like interface without all the boilerplate.
/// - `mergeStreams`: Combine multiple streams into a single stream with a collective output.
/// - `Stream.asFutures`: Turn a stream into a list of futures for an improved error handling experience.
///
/// These tools work independently but are designed to compose well with existing
/// Dart code, offering a more robust and maintainable approach to async programming.
library;

export 'src/async_scope.dart';
export 'src/merge_streams.dart';
export 'src/stream_as_futures.dart';
export 'src/stream_lifecycle_transformer.dart';
