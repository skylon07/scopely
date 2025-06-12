import 'dart:async';
import 'package:scopely/scopely.dart';
import 'package:test/test.dart';

void main() {
  group("IntToStringTransformer (the basic/default implementation)", () {
    late IntToStringTransformer transformer;
    late StreamController<int> controller;
    late Stream<String> transformed;
    
    setUp(() {
      transformer = IntToStringTransformer();
      controller = StreamController();
      transformed = controller.stream.transform(transformer);
    });

    tearDown(() {
      controller.close();
    });

    test("forwards transformed data", () async {
      controller.add(1);
      controller.add(2);
      controller.add(3);
      controller.close();

      var result = await transformed.toList();

      expect(result, ["1", "2", "3"]);
    });

    test("forwards errors (unmodified) with their stack traces", () async {
      var errors = [];
      var stackTraces = [];
      transformed.listen(null, onError: (error, stackTrace) {
        errors.add(error);
        stackTraces.add(stackTrace);
      });

      var error1 = StateError("first error");
      controller.addError(error1);
      var error2 = {"amIAnError": "totally"};
      controller.addError(error2);
      await Future.delayed(Duration.zero);

      expect(errors, [error1, error2]);
      for (var stackTrace in stackTraces) {
        expect(stackTrace, isA<StackTrace>());
      }
    });

    test("signals 'done' after closing", () async {
      bool isDone = false;
      transformed.listen(null, onDone: () => isDone = true);

      await controller.close();
      await Future.delayed(Duration.zero);

      expect(isDone, true);
    });

    test("cancels on error when told to", () async {
      // onError set to prevent test failure by catching the fake errors
      transformed.listen(null, onError: (_) {}, cancelOnError: true);

      expect(controller.hasListener, true);

      controller.addError("something really bad happened");
      await Future.delayed(Duration.zero);

      expect(controller.hasListener, false);
    });

    group("for single-subscription streams", () {
      test("pauses and resumes the source stream", () async {
        expect(controller.isPaused, true);
        expect(controller.hasListener, false);

        var subscription = transformed.listen(null);

        expect(controller.isPaused, false);
        expect(controller.hasListener, true);
        
        subscription.pause();

        expect(controller.isPaused, true);
        expect(controller.hasListener, true);

        subscription.resume();
        await Future.delayed(Duration.zero);

        expect(controller.isPaused, false);
        expect(controller.hasListener, true);

        await controller.close();
      });

      test("cancels the source subscription permanently", () async {
        var subscription = transformed.listen(null);
        await subscription.cancel();

        expect(controller.hasListener, false);

        expect(() {
          transformed.listen(null);
        }, throwsStateError);
      });

      test("still throws on multiple listens, even if they are different transformations", () async {
        expect(() {
          transformed.listen(null);
        }, returnsNormally);

        expect(() {
          transformed.listen(null);
        }, throwsStateError);

        expect(() {
          controller.stream.transform(transformer).listen(null);
        }, throwsStateError);
      });

      test("treats generic (not 'stream already listened to') errors in onListen() as uncaught errors)", () async {
        transformer.onListenCallback = () => throw "some error";

        var listensCompleted = false;
        var handledCaughtError = false;
        var handledUncaughtError = false;
        runZonedGuarded(
          () {
            try {
              transformed.listen(null);
              listensCompleted = true;
            } catch (error) {
              handledCaughtError = true;
            }
          },
          (error, stackTrace) {
            handledUncaughtError = true;
          },
        );
        await Future.delayed(Duration(seconds: 1));

        expect(listensCompleted, true);
        expect(handledCaughtError, false);
        expect(handledUncaughtError, true);
      });
    });

    group("for broadcast streams", () {
      late StreamController<int> controller;
      late Stream<String> transformed;
      
      setUp(() {
        controller = StreamController.broadcast();
        transformed = controller.stream.transform(transformer);
      });
      
      tearDown(() {
        controller.close();
      });

      test("cancels the source subscription temporarily", () async {
        var subscription = transformed.listen(null);
        await subscription.cancel();

        expect(controller.hasListener, false);

        expect(() {
          transformed.listen(null);
        }, returnsNormally);
      });

      test("treats generic (not 'stream already listened to') errors in onListen() as uncaught errors)", () async {
        transformer.onListenCallback = () => throw "some error";

        var listensCompleted = false;
        var handledCaughtError = false;
        var handledUncaughtError = false;
        runZonedGuarded(
          () {
            try {
              transformed.listen(null);
              listensCompleted = true;
            } catch (error) {
              handledCaughtError = true;
            }
          },
          (error, stackTrace) {
            handledUncaughtError = true;
          },
        );
        await Future.delayed(Duration(seconds: 1));

        expect(listensCompleted, true);
        expect(handledCaughtError, false);
        expect(handledUncaughtError, true);
      });
    });
  });

  group("SpyTransformer", () {
    late SpyTransformer transformer;
    late StreamController controller;
    late Stream transformed;
    
    setUp(() {
      transformer = SpyTransformer();
      controller = StreamController();
      transformed = controller.stream.transform(transformer);
    });

    tearDown(() {
      controller.close();
    });

    test("calls onBind() once per transformation", () async {
      Stream<dynamic>.fromIterable([1, 2, 3]).transform(transformer);
      Stream<dynamic>.empty(broadcast: true).transform(transformer);

      expect(transformer.onBindDestControllerCalls, 3); // include transform on setup!
    });

    test("calls sourceOnData() once per event", () async {
      transformed.listen(null);

      controller.add(1);
      controller.add(2);
      controller.add(3);
      controller.add(4);
      await Future.delayed(Duration.zero);

      expect(transformer.sourceOnDataCalls, 4);
    });

    test("calls sourceOnError() once per error event", () async {
      // onError set to prevent test failure by catching the fake errors
      transformed.listen(null, onError: (_) {});

      controller.add(1);
      controller.addError("error 1");
      controller.add(2);
      controller.addError("error 2");
      await Future.delayed(Duration.zero);

      expect(transformer.sourceOnErrorCalls, 2);
    });

    test("calls sourceOnDone() once per done event", () async {
      transformed.listen(null);

      await controller.close();
      await Future.delayed(Duration.zero);

      expect(transformer.sourceOnDoneCalls, 1);
    });

    group("for single-subscription streams", () {
      test("calls destOnListen() on listen", () async {
        expect(transformer.destOnListenCalls, 0);
        
        transformed.listen(null);

        expect(transformer.destOnListenCalls, 1);
      });

      test("calls destOnCancel() on cancel", () async {
        var subscription = transformed.listen(null);

        expect(transformer.destOnCancelCalls, 0);
        
        await subscription.cancel();

        expect(transformer.destOnListenCalls, 1);
      });

      test("calls destOnPause() once per pause", () async {
        var subscription = transformed.listen(null);

        expect(transformer.destOnPauseCalls, 0);

        subscription.pause();

        expect(transformer.destOnPauseCalls, 1);

        subscription.pause();

        expect(transformer.destOnPauseCalls, 1);

        subscription.resume();
        subscription.resume();
        subscription.pause();

        expect(transformer.destOnPauseCalls, 2);
      });

      test("calls destOnResume() once per resume", () async {
        var subscription = transformed.listen(null);

        expect(transformer.destOnResumeCalls, 0);

        subscription.resume();

        expect(transformer.destOnResumeCalls, 0);

        subscription.pause();
        subscription.resume();

        expect(transformer.destOnResumeCalls, 1);

        subscription.pause();
        subscription.pause();
        subscription.resume();
        subscription.resume();

        expect(transformer.destOnResumeCalls, 2);
      });
    });

    group("for broadcast streams", () {
      late StreamController controller;
      late Stream transformed;
      
      setUp(() {
        controller = StreamController.broadcast();
        transformed = controller.stream.transform(transformer);
      });
      
      tearDown(() {
        controller.close();
      });

      test("calls destOnListen() once ONLY on first listen", () async {
        expect(transformer.destOnListenCalls, 0);
        
        var subscription1 = transformed.listen(null);

        expect(transformer.destOnListenCalls, 1);

        var subscription2 = transformed.listen(null);
        var subscription3 = transformed.listen(null);

        expect(transformer.destOnListenCalls, 1);

        await subscription1.cancel();
        await subscription2.cancel();
        await subscription3.cancel();
        transformed.listen(null);

        expect(transformer.destOnListenCalls, 2);
      });

      test("calls destOnCancel() once ONLY on last cancelation", () async {
        var subscription1 = transformed.listen(null);
        
        expect(transformer.destOnCancelCalls, 0);

        await subscription1.cancel();

        expect(transformer.destOnCancelCalls, 1);

        var subscription2 = transformed.listen(null);
        var subscription3 = transformed.listen(null);
        await subscription2.cancel();

        expect(transformer.destOnCancelCalls, 1);

        await subscription3.cancel();

        expect(transformer.destOnCancelCalls, 2);
      });

      test("never calls destOnPause()", () async {
        var subscription1 = transformed.listen(null);
        var subscription2 = transformed.listen(null);

        expect(transformer.destOnPauseCalls, 0);

        subscription1.pause();

        expect(transformer.destOnPauseCalls, 0);

        subscription2.pause();

        expect(transformer.destOnPauseCalls, 0);

        subscription1.pause();
        subscription1.pause();
        subscription1.pause();
        subscription2.pause();
        subscription2.pause();
        subscription2.pause();

        // expect(transformer.destOnPauseCalls, 1);
        // (just kidding!)
        expect(transformer.destOnPauseCalls, 0);
      });

      test("never calls destOnResume()", () async {
        var subscription1 = transformed.listen(null);
        var subscription2 = transformed.listen(null);

        expect(transformer.destOnResumeCalls, 0);

        subscription1.pause();
        subscription1.resume();

        expect(transformer.destOnResumeCalls, 0);

        subscription2.pause();
        subscription1.resume();
        subscription2.resume();

        expect(transformer.destOnResumeCalls, 0);
      });
    });
  });
}

final class IntToStringTransformer extends StreamLifecycleTransformer<int, String> {
  void Function()? onListenCallback;

  @override
  StreamSubscription<int>? destOnListen(TransformerContext<int, String> context) {
    onListenCallback?.call();
    return super.destOnListen(context);
  }

  @override
  void sourceOnData(TransformerContext<int, String> context, int event) {
    context.destController.add(event.toString());
  }
}

final class SpyTransformer extends StreamLifecycleTransformer {
  int onBindDestControllerCalls = 0;
  @override
  StreamController onBindDestController(Stream sourceStream, StreamControllerHandlers handlers) {
    onBindDestControllerCalls++;
    return super.onBindDestController(sourceStream, handlers);
  }
  
  int destOnListenCalls = 0;
  @override
  StreamSubscription? destOnListen(TransformerContext context) {
    destOnListenCalls++;
    return super.destOnListen(context);
  }
  
  int destOnCancelCalls = 0;
  @override
  FutureOr<StreamSubscription?> destOnCancel(TransformerContext context) {
    destOnCancelCalls++;
    return super.destOnCancel(context);
  }
  
  int destOnPauseCalls = 0;
  @override
  void destOnPause(TransformerContext context) {
    destOnPauseCalls++;
    super.destOnPause(context);
  }
  
  int destOnResumeCalls = 0;
  @override
  void destOnResume(TransformerContext context) {
    destOnResumeCalls++;
    super.destOnResume(context);
  }
  
  int sourceOnDataCalls = 0;
  @override
  void sourceOnData(TransformerContext context, event) {
    sourceOnDataCalls++;
  }
  
  int sourceOnErrorCalls = 0;
  @override
  void sourceOnError(TransformerContext context, Object error, StackTrace stackTrace) {
    sourceOnErrorCalls++;
    super.sourceOnError(context, error, stackTrace);
  }
  
  int sourceOnDoneCalls = 0;
  @override
  FutureOr<void> sourceOnDone(TransformerContext context) {
    sourceOnDoneCalls++;
    return super.sourceOnDone(context);
  }
}