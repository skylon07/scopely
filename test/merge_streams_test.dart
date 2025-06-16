import 'dart:async';
import 'package:scopely/scopely.dart';
import 'package:test/test.dart';

void main() {
  group("The default mergeStreams()", () {
    late StreamController<int> controller1;
    late StreamController<double> controller2;
    late StreamController<String?> controller3;
    late Stream<List<dynamic>> mergedStream;
    StreamSubscription? mergedStreamSubscription;

    setUp(() {
      controller1 = StreamController();
      controller2 = StreamController.broadcast(); // because it can hold "double" (or more) subscriptions! :D
      controller3 = StreamController();
      mergedStream = mergeStreams([
        controller1.stream,
        controller2.stream,
        controller3.stream,
      ]);
    });

    tearDown(() {
      controller1.close();
      controller2.close();
      controller3.close();
      assert (mergedStreamSubscription != null, "Tests should store the resulting subscription for cleanup");
      mergedStreamSubscription!.cancel();
    });

    test("forwards a combined list of values from all streams", () async {
      var dataCompleter = Completer<List<dynamic>>();
      mergedStreamSubscription = mergedStream.listen((data) {
        dataCompleter.complete(data);
      });

      controller1.add(1);
      controller2.add(2);
      controller3.add("3");

      var data = await dataCompleter.future;

      expect(data, [1, 2, "3"]);
    });

    test("doesn't emit any data until all source streams have emitted once", () async {
      var dataSentYet = false;
      mergedStreamSubscription = mergedStream.listen((data) {
        dataSentYet = true;
      });

      controller1.add(1);
      await Future.delayed(Duration.zero);

      expect(dataSentYet, false);

      controller2.add(2);
      await Future.delayed(Duration.zero);

      expect(dataSentYet, false);

      controller3.add("3");
      await Future.delayed(Duration.zero);

      expect(dataSentYet, true);
    });

    test("sends new data when any source streams have emitted new data", () async {
      var dataReceived = [];
      mergedStreamSubscription = mergedStream.listen((data) {
        dataReceived.add(data);
      });

      controller1.add(1);
      await Future.delayed(Duration.zero);
      controller2.add(2);
      await Future.delayed(Duration.zero);
      controller3.add("3");
      await Future.delayed(Duration.zero);
      controller3.add("4");
      await Future.delayed(Duration.zero);
      controller2.add(5);
      await Future.delayed(Duration.zero);

      expect(dataReceived, [
        [1, 2, "3"],
        [1, 2, "4"],
        [1, 5, "4"],
      ]);
    });

    test("errors and stack traces are forwarded", () async {
      var errors = [];
      var stackTraces = [];
      mergedStreamSubscription = mergedStream.listen(null, onError: (error, stackTrace) {
        errors.add(error);
        stackTraces.add(stackTrace);
      });

      var error1 = StateError("first error");
      controller1.addError(error1);
      var error2 = {"amIAnError": "totally"};
      controller2.addError(error2);
      var error3 = ["this", "is", "a", "completely", "normal", "error"];
      controller3.addError(error3);
      await Future.delayed(Duration.zero);

      expect(errors, [
        (index: 0, stream: controller1.stream, error: error1), 
        (index: 1, stream: controller2.stream, error: error2), 
        (index: 2, stream: controller3.stream, error: error3),
      ]);
      for (var stackTrace in stackTraces) {
        expect(stackTrace, isA<StackTrace>());
      }
    });

    test("done events are forwarded (when all complete)", () async {
      var isDone = false;
      mergedStreamSubscription = mergedStream.listen(null, onDone: () => isDone = true);

      await controller1.close();
      await Future.delayed(Duration.zero);

      expect(isDone, false);

      await controller2.close();
      await Future.delayed(Duration.zero);

      expect(isDone, false);

      await controller3.close();
      await Future.delayed(Duration.zero);

      expect(isDone, true);
    });

    test("no streams to merge throws an error", () async {
      expect(() {
        mergeStreams([]);
      }, throwsArgumentError);

      // just because setup requires it...
      mergedStreamSubscription = mergedStream.listen(null);
    });

    test("merging one stream acts as a passthrough", () async {
      mergedStream = mergeStreams([controller1.stream]);

      var dataCompleter = Completer<List<dynamic>>();
      mergedStreamSubscription = mergedStream.listen((data) {
        dataCompleter.complete(data);
      });

      controller1.add(15);

      var data = await dataCompleter.future;

      expect(data, [15]);
    });

    test("throws when merging a single-subscription stream that's already been listened to", () {
      var stream1 = StreamController().stream;
      var stream2 = StreamController().stream;
      mergedStreamSubscription = stream2.listen(null);
      
      expect(() {
        mergeStreams([stream1, stream2]).listen(null);
      }, throwsStateError);
    });
  });

  group("N-airty mergeStreamsN()", () {
    late StreamController<int> controller1;
    late StreamController<int> controller2;
    late StreamController<int> controller3;
    late StreamController<int> controller4;
    late StreamController<int> controller5;
    late StreamController<int> controller6;
    late StreamController<int> controller7;
    late StreamController<int> controller8;
    late StreamController<int> controller9;
    late StreamController<int> controller10;

    setUp(() {
      controller1 = StreamController()
        ..add(11)
        ..add(12)
        ..add(13)
        ..close();
      controller2 = StreamController()
        ..add(21)
        ..add(22)
        ..add(23)
        ..close();
      controller3 = StreamController()
        ..add(31)
        ..add(32)
        ..add(33)
        ..close();
      controller4 = StreamController()
        ..add(41)
        ..add(42)
        ..add(43)
        ..close();
      controller5 = StreamController()
        ..add(51)
        ..add(52)
        ..add(53)
        ..close();
      controller6 = StreamController()
        ..add(61)
        ..add(62)
        ..add(63)
        ..close();
      controller7 = StreamController()
        ..add(71)
        ..add(72)
        ..add(73)
        ..close();
      controller8 = StreamController()
        ..add(81)
        ..add(82)
        ..add(83)
        ..close();
      controller9 = StreamController()
        ..add(91)
        ..add(92)
        ..add(93)
        ..close();
      controller10 = StreamController()
        ..add(101)
        ..add(102)
        ..add(103)
        ..close();
    });

    test("mergeStreams2() returns its record correctly", () async {
      var stream = mergeStreams2(
        controller1.stream,
        controller2.stream,
      );
      var results = await stream.toList();

      expect(results, [
        (11, 21),
        (12, 21),
        (12, 22),
        (13, 22),
        (13, 23),
      ]);
    });

    test("mergeStreams3() returns its record correctly", () async {
      var stream = mergeStreams3(
        controller1.stream,
        controller2.stream,
        controller3.stream,
      );
      var results = await stream.toList();

      expect(results, [
        (11, 21, 31),
        (12, 21, 31),
        (12, 22, 31),
        (12, 22, 32),
        (13, 22, 32),
        (13, 23, 32),
        (13, 23, 33),
      ]);
    });

    test("mergeStreams4() returns its record correctly", () async {
      var stream = mergeStreams4(
        controller1.stream,
        controller2.stream,
        controller3.stream,
        controller4.stream,
      );
      var results = await stream.toList();

      expect(results, [
        (11, 21, 31, 41),
        (12, 21, 31, 41),
        (12, 22, 31, 41),
        (12, 22, 32, 41),
        (12, 22, 32, 42),
        (13, 22, 32, 42),
        (13, 23, 32, 42),
        (13, 23, 33, 42),
        (13, 23, 33, 43),
      ]);
    });

    test("mergeStreams5() returns its record correctly", () async {
      var stream = mergeStreams5(
        controller1.stream,
        controller2.stream,
        controller3.stream,
        controller4.stream,
        controller5.stream,
      );
      var results = await stream.toList();

      expect(results, [
        (11, 21, 31, 41, 51),
        (12, 21, 31, 41, 51),
        (12, 22, 31, 41, 51),
        (12, 22, 32, 41, 51),
        (12, 22, 32, 42, 51),
        (12, 22, 32, 42, 52),
        (13, 22, 32, 42, 52),
        (13, 23, 32, 42, 52),
        (13, 23, 33, 42, 52),
        (13, 23, 33, 43, 52),
        (13, 23, 33, 43, 53),
      ]);
    });

    test("mergeStreams6() returns its record correctly", () async {
      var stream = mergeStreams6(
        controller1.stream,
        controller2.stream,
        controller3.stream,
        controller4.stream,
        controller5.stream,
        controller6.stream,
      );
      var results = await stream.toList();

      expect(results, [
        (11, 21, 31, 41, 51, 61),
        (12, 21, 31, 41, 51, 61),
        (12, 22, 31, 41, 51, 61),
        (12, 22, 32, 41, 51, 61),
        (12, 22, 32, 42, 51, 61),
        (12, 22, 32, 42, 52, 61),
        (12, 22, 32, 42, 52, 62),
        (13, 22, 32, 42, 52, 62),
        (13, 23, 32, 42, 52, 62),
        (13, 23, 33, 42, 52, 62),
        (13, 23, 33, 43, 52, 62),
        (13, 23, 33, 43, 53, 62),
        (13, 23, 33, 43, 53, 63),
      ]);
    });

    test("mergeStreams7() returns its record correctly", () async {
      var stream = mergeStreams7(
        controller1.stream,
        controller2.stream,
        controller3.stream,
        controller4.stream,
        controller5.stream,
        controller6.stream,
        controller7.stream,
      );
      var results = await stream.toList();

      expect(results, [
        (11, 21, 31, 41, 51, 61, 71),
        (12, 21, 31, 41, 51, 61, 71),
        (12, 22, 31, 41, 51, 61, 71),
        (12, 22, 32, 41, 51, 61, 71),
        (12, 22, 32, 42, 51, 61, 71),
        (12, 22, 32, 42, 52, 61, 71),
        (12, 22, 32, 42, 52, 62, 71),
        (12, 22, 32, 42, 52, 62, 72),
        (13, 22, 32, 42, 52, 62, 72),
        (13, 23, 32, 42, 52, 62, 72),
        (13, 23, 33, 42, 52, 62, 72),
        (13, 23, 33, 43, 52, 62, 72),
        (13, 23, 33, 43, 53, 62, 72),
        (13, 23, 33, 43, 53, 63, 72),
        (13, 23, 33, 43, 53, 63, 73),
      ]);
    });

    test("mergeStreams8() returns its record correctly", () async {
      var stream = mergeStreams8(
        controller1.stream,
        controller2.stream,
        controller3.stream,
        controller4.stream,
        controller5.stream,
        controller6.stream,
        controller7.stream,
        controller8.stream,
      );
      var results = await stream.toList();

      expect(results, [
        (11, 21, 31, 41, 51, 61, 71, 81),
        (12, 21, 31, 41, 51, 61, 71, 81),
        (12, 22, 31, 41, 51, 61, 71, 81),
        (12, 22, 32, 41, 51, 61, 71, 81),
        (12, 22, 32, 42, 51, 61, 71, 81),
        (12, 22, 32, 42, 52, 61, 71, 81),
        (12, 22, 32, 42, 52, 62, 71, 81),
        (12, 22, 32, 42, 52, 62, 72, 81),
        (12, 22, 32, 42, 52, 62, 72, 82),
        (13, 22, 32, 42, 52, 62, 72, 82),
        (13, 23, 32, 42, 52, 62, 72, 82),
        (13, 23, 33, 42, 52, 62, 72, 82),
        (13, 23, 33, 43, 52, 62, 72, 82),
        (13, 23, 33, 43, 53, 62, 72, 82),
        (13, 23, 33, 43, 53, 63, 72, 82),
        (13, 23, 33, 43, 53, 63, 73, 82),
        (13, 23, 33, 43, 53, 63, 73, 83),
      ]);
    });

    test("mergeStreams9() returns its record correctly", () async {
      var stream = mergeStreams9(
        controller1.stream,
        controller2.stream,
        controller3.stream,
        controller4.stream,
        controller5.stream,
        controller6.stream,
        controller7.stream,
        controller8.stream,
        controller9.stream,
      );
      var results = await stream.toList();

      expect(results, [
        (11, 21, 31, 41, 51, 61, 71, 81, 91),
        (12, 21, 31, 41, 51, 61, 71, 81, 91),
        (12, 22, 31, 41, 51, 61, 71, 81, 91),
        (12, 22, 32, 41, 51, 61, 71, 81, 91),
        (12, 22, 32, 42, 51, 61, 71, 81, 91),
        (12, 22, 32, 42, 52, 61, 71, 81, 91),
        (12, 22, 32, 42, 52, 62, 71, 81, 91),
        (12, 22, 32, 42, 52, 62, 72, 81, 91),
        (12, 22, 32, 42, 52, 62, 72, 82, 91),
        (12, 22, 32, 42, 52, 62, 72, 82, 92),
        (13, 22, 32, 42, 52, 62, 72, 82, 92),
        (13, 23, 32, 42, 52, 62, 72, 82, 92),
        (13, 23, 33, 42, 52, 62, 72, 82, 92),
        (13, 23, 33, 43, 52, 62, 72, 82, 92),
        (13, 23, 33, 43, 53, 62, 72, 82, 92),
        (13, 23, 33, 43, 53, 63, 72, 82, 92),
        (13, 23, 33, 43, 53, 63, 73, 82, 92),
        (13, 23, 33, 43, 53, 63, 73, 83, 92),
        (13, 23, 33, 43, 53, 63, 73, 83, 93),
      ]);
    });

    test("mergeStreams10() returns its record correctly", () async {
      var stream = mergeStreams10(
        controller1.stream,
        controller2.stream,
        controller3.stream,
        controller4.stream,
        controller5.stream,
        controller6.stream,
        controller7.stream,
        controller8.stream,
        controller9.stream,
        controller10.stream,
      );
      var results = await stream.toList();

      expect(results, [
        (11, 21, 31, 41, 51, 61, 71, 81, 91, 101),
        (12, 21, 31, 41, 51, 61, 71, 81, 91, 101),
        (12, 22, 31, 41, 51, 61, 71, 81, 91, 101),
        (12, 22, 32, 41, 51, 61, 71, 81, 91, 101),
        (12, 22, 32, 42, 51, 61, 71, 81, 91, 101),
        (12, 22, 32, 42, 52, 61, 71, 81, 91, 101),
        (12, 22, 32, 42, 52, 62, 71, 81, 91, 101),
        (12, 22, 32, 42, 52, 62, 72, 81, 91, 101),
        (12, 22, 32, 42, 52, 62, 72, 82, 91, 101),
        (12, 22, 32, 42, 52, 62, 72, 82, 92, 101),
        (12, 22, 32, 42, 52, 62, 72, 82, 92, 102),
        (13, 22, 32, 42, 52, 62, 72, 82, 92, 102),
        (13, 23, 32, 42, 52, 62, 72, 82, 92, 102),
        (13, 23, 33, 42, 52, 62, 72, 82, 92, 102),
        (13, 23, 33, 43, 52, 62, 72, 82, 92, 102),
        (13, 23, 33, 43, 53, 62, 72, 82, 92, 102),
        (13, 23, 33, 43, 53, 63, 72, 82, 92, 102),
        (13, 23, 33, 43, 53, 63, 73, 82, 92, 102),
        (13, 23, 33, 43, 53, 63, 73, 83, 92, 102),
        (13, 23, 33, 43, 53, 63, 73, 83, 93, 102),
        (13, 23, 33, 43, 53, 63, 73, 83, 93, 103),
      ]);
    });
  });
}
