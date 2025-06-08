/// Support for lightweight scopes to manage asynchronous tasks.
/// 
/// `Future`s and `Stream`s are the building blocks for async programming in dart.
/// However, care must be taken to ensure resources aren't unnecessarily wasted.
/// [AsyncScope]s provide a way to "scope" asynchronous tasks so they can be
/// canceled and cleaned up later.
/// 
/// You can decide if you want to create `AsyncScope` directly...
///
/// ```dart
/// import 'package:scopely/scopely.dart';
///
/// mixin CustomScopingHook on MyTypeWithCleanup {
///   final scope = AsyncScope();
///
///   @override
///   void onCleanup() {
///     super.onCleanup();
///     scope.cancelAll();
///   }
/// }
/// ```
///
/// ...or use one of the package's predefined hooks.
///
/// ```dart
/// import 'package:scopely/hooks/flutter.dart';
///
/// class CustomState extends State<CustomWidget> with StateScoping {
///     // StateScoping exposes `AsyncScope scope` to this widget state
/// }
/// ```
library;

// TODO: fix the above comment -- it's outdated (particularly the scopely/hooks/flutter.dart part)

export 'src/async_scope.dart';
export 'src/stream_as_futures.dart';
export 'src/stream_lifecycle_transformer.dart';
