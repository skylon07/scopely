import 'package:scopely/scopely.dart';

import 'fake_state.dart';

/// An example of how to tie an [AsyncScope] to a Flutter `State`.
/// This class holds all the magic of automating task cleanup.
/// As you can see, it's pretty minimal!
mixin StateScoping on State {
  final scope = AsyncScope();

  @override
  void dispose() {
    print("-- scope canceling all tasks");
    scope.cancelAll();
    print("-- scope tasks canceled");
    super.dispose();
  }
}
