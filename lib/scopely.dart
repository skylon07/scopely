/// Enhances Dart's `async`/`await` model with structured concurrency utilities.
///
/// This library is centered around [AsyncScope], a utility for running asynchronous tasks
/// as a cancelable group. It enables patterns where task lifecycles can be seamlessly
/// and efficiently tied to external lifecycles (such as Flutter `State`s) to handle
/// cleanup automatically.
///
/// Additional utilities include:
/// - `StreamLifecycleTransformer`: A [StreamTransformer] that provides several hooks
///   to augment a stream's lifecycle without the boilerplate of using a [StreamController].
/// - `mergeStreams`: Combines multiple streams into a single stream of synchronized lists.
/// - `Stream.asFutures`: Converts a stream into a list of futures, one for each event.
///   Useful for event-level error handling in `await for` loops.
///
/// These tools work independently but are designed to compose well with existing
/// Dart code, offering a more robust and maintainable approach to async programming.
library;

export 'src/async_scope.dart';
export 'src/merge_streams.dart';
export 'src/stream_as_futures.dart';
export 'src/stream_lifecycle_transformer.dart';
