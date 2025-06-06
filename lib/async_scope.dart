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
/// import 'package:async_scope/async_scope.dart';
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
/// import 'package:async_scope/hooks/flutter.dart';
///
/// class CustomState extends State<CustomWidget> with StateScoping {
///     // StateScoping exposes `AsyncScope scope` to this widget state
/// }
/// ```
library;

export 'src/async_scope.dart';
