import 'package:scopely/src/async_scope.dart';

/// Represents a custom Flutter `ChangeNotifier` or something of the like.
/// This just demonstrates how [AsyncScope] is compatible with the "listener pattern".
class MyChangeNotifier {
  void addListener(void Function() callback) {}
  void removeListener(void Function() callback) {}
}