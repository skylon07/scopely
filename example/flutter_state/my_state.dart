import 'package:scopely/scopely.dart';

import 'fake_state.dart';
import 'my_notifier.dart';
import 'state_scoping.dart';

/// An example implementation of a custom state *with* the [AsyncScope] mixed in.
/// At this point, everything is handled behind the scenes. All you'd need to do
/// is bind your async tasks to the [scope]!
class MyState extends State with StateScoping {
  final notifier = MyChangeNotifier();

  @override
  void initState() {
    // notice this is fire-and-forget...
    // (not bound to the scope, although it could be)
    fakeFetchAndStore();

    // scopes also work with other patterns that might need manual cleanup
    void fakeListener() {};
    print("  adding notifier listeners...");
    notifier.addListener(fakeListener);
    scope.addCancelListener(() {
      print("-- cancelling listener");
      notifier.removeListener(fakeListener);
    });

    super.initState();
  }

  Future<void> fakeFetchAndStore() async {
    // `inScope()` makes it very easy to take existing async code
    // and bind it to this state's scope
    print("before fakeFetch()");
    var data = await fakeFetch().inScope(scope);
    print("after fakeFetch()");
    
    // this won't ever run; the state was already disposed in `main()`!
    print("before fakeStore()");
    await fakeStore(data).inScope(scope);
    print("after fakeStore()");
  }

  Future<String> fakeFetch() async {
    print("  fakeFetch(): starting...   (scope canceled? ${scope.isCanceled})");  // this WILL be printed
    await Future.delayed(Duration(seconds: 2));
    // runs even though the scope was canceled;
    // this would NOT happen if the above delay was also bound to the scope
    print("  fakeFetch(): returning     (scope canceled? ${scope.isCanceled})");  // this WILL be printed
    return "very important data!";
  }

  Future<void> fakeStore(String data) async {
    print("  fakeStore(): starting...");  // this will NOT be printed
    await Future.delayed(Duration(seconds: 2));
    print("  fakeStore(): returning");    // this will NOT be printed
  }
}