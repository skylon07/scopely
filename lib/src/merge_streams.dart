import 'dart:async';

import 'package:scopely/scopely.dart';

Stream<List<dynamic>> mergeStreams(List<Stream<dynamic>> streams) {
  if (streams.isEmpty) throw ArgumentError("Must provide at least one stream");
  
  var manager = _MergeStreamsManager();
  late Stream<List<dynamic>> resultStream;
  for (var (idx, stream) in streams.indexed) {
    // each resulting stream is equivalent in the way it functions,
    // so using any of them is valid
    resultStream = stream
      .cast<dynamic>()
      .transform(_MergeStreamsTransformer<dynamic>(manager, streamIdx: idx, originalStream: stream))
      .cast<List<dynamic>>();
  }
  return resultStream;
}

Stream<(E1, E2)> mergeStreams2<E1, E2>(
  Stream<E1> stream1, 
  Stream<E2> stream2,
) {
  return mergeStreams([stream1, stream2]).map((list) {
    var [event1, event2] = list;
    return (event1, event2);
  });
}

Stream<(E1, E2, E3)> mergeStreams3<E1, E2, E3>(
  Stream<E1> stream1, 
  Stream<E2> stream2,
  Stream<E3> stream3,
) {
  return mergeStreams([stream1, stream2, stream3]).map((list) {
    var [event1, event2, event3] = list;
    return (event1, event2, event3);
  });
}

Stream<(E1, E2, E3, E4)> mergeStreams4<E1, E2, E3, E4>(
  Stream<E1> stream1, 
  Stream<E2> stream2,
  Stream<E3> stream3,
  Stream<E4> stream4,
) {
  return mergeStreams([stream1, stream2, stream3, stream4]).map((list) {
    var [event1, event2, event3, event4] = list;
    return (event1, event2, event3, event4);
  });
}

Stream<(E1, E2, E3, E4, E5)> mergeStreams5<E1, E2, E3, E4, E5>(
  Stream<E1> stream1, 
  Stream<E2> stream2,
  Stream<E3> stream3,
  Stream<E4> stream4,
  Stream<E5> stream5,
) {
  return mergeStreams([stream1, stream2, stream3, stream4, stream5]).map((list) {
    var [event1, event2, event3, event4, event5] = list;
    return (event1, event2, event3, event4, event5);
  });
}

Stream<(E1, E2, E3, E4, E5, E6)> mergeStreams6<E1, E2, E3, E4, E5, E6>(
  Stream<E1> stream1,
  Stream<E2> stream2,
  Stream<E3> stream3,
  Stream<E4> stream4,
  Stream<E5> stream5,
  Stream<E6> stream6,
) {
  return mergeStreams([stream1, stream2, stream3, stream4, stream5, stream6]).map((list) {
    var [event1, event2, event3, event4, event5, event6] = list;
    return (event1, event2, event3, event4, event5, event6);
  });
}

Stream<(E1, E2, E3, E4, E5, E6, E7)> mergeStreams7<E1, E2, E3, E4, E5, E6, E7>(
  Stream<E1> stream1,
  Stream<E2> stream2,
  Stream<E3> stream3,
  Stream<E4> stream4,
  Stream<E5> stream5,
  Stream<E6> stream6,
  Stream<E7> stream7,
) {
  return mergeStreams([stream1, stream2, stream3, stream4, stream5, stream6, stream7]).map((list) {
    var [event1, event2, event3, event4, event5, event6, event7] = list;
    return (event1, event2, event3, event4, event5, event6, event7);
  });
}

Stream<(E1, E2, E3, E4, E5, E6, E7, E8)> mergeStreams8<E1, E2, E3, E4, E5, E6, E7, E8>(
  Stream<E1> stream1,
  Stream<E2> stream2,
  Stream<E3> stream3,
  Stream<E4> stream4,
  Stream<E5> stream5,
  Stream<E6> stream6,
  Stream<E7> stream7,
  Stream<E8> stream8,
) {
  return mergeStreams([stream1, stream2, stream3, stream4, stream5, stream6, stream7, stream8]).map((list) {
    var [event1, event2, event3, event4, event5, event6, event7, event8] = list;
    return (event1, event2, event3, event4, event5, event6, event7, event8);
  });
}

Stream<(E1, E2, E3, E4, E5, E6, E7, E8, E9)> mergeStreams9<E1, E2, E3, E4, E5, E6, E7, E8, E9>(
  Stream<E1> stream1,
  Stream<E2> stream2,
  Stream<E3> stream3,
  Stream<E4> stream4,
  Stream<E5> stream5,
  Stream<E6> stream6,
  Stream<E7> stream7,
  Stream<E8> stream8,
  Stream<E9> stream9,
) {
  return mergeStreams([stream1, stream2, stream3, stream4, stream5, stream6, stream7, stream8, stream9]).map((list) {
    var [event1, event2, event3, event4, event5, event6, event7, event8, event9] = list;
    return (event1, event2, event3, event4, event5, event6, event7, event8, event9);
  });
}

Stream<(E1, E2, E3, E4, E5, E6, E7, E8, E9, E10)> mergeStreams10<E1, E2, E3, E4, E5, E6, E7, E8, E9, E10>(
  Stream<E1> stream1,
  Stream<E2> stream2,
  Stream<E3> stream3,
  Stream<E4> stream4,
  Stream<E5> stream5,
  Stream<E6> stream6,
  Stream<E7> stream7,
  Stream<E8> stream8,
  Stream<E9> stream9,
  Stream<E10> stream10,
) {
  return mergeStreams([
    stream1, stream2, stream3, stream4, stream5,
    stream6, stream7, stream8, stream9, stream10
  ]).map((list) {
    var [event1, event2, event3, event4, event5, event6, event7, event8, event9, event10] = list;
    return (event1, event2, event3, event4, event5, event6, event7, event8, event9, event10);
  });
}


class _MergeStreamsManager {
  late final sharedDestController = StreamController<List<dynamic>>(
    onListen: onListen,
    onCancel: onCancel,
    onPause: onPause,
    onResume: onResume,
  );

  final _sourceStreams = <Stream<dynamic>>[];
  final _listenHandlers = <void Function()>[];
  final _cancelHandlers = <FutureOr<void> Function()>[];
  final _pauseHandlers = <void Function()>[];
  final _resumeHandlers = <void Function()>[];

  final _streamState = <Stream, dynamic>{};

  void onListen() {
    for (var listen in _listenHandlers) {
      listen();
    }
  }

  FutureOr<void> onCancel() async {
    await Future.wait([
      for (var cancel in _cancelHandlers)
        Future.value(cancel())
    ]);
    await sharedDestController.closeIfNeeded();
  }

  void onPause() {
    for (var pause in _pauseHandlers) {
      pause();
    }
  }

  void onResume() {
    for (var resume in _resumeHandlers) {
      resume();
    }
  }

  void addHandlers(Stream sourceStream, StreamControllerHandlers handlers) {
    _sourceStreams.add(sourceStream);

    _listenHandlers.add(handlers.listen);
    _cancelHandlers.add(handlers.cancel);
    _pauseHandlers.add(handlers.pause);
    _resumeHandlers.add(handlers.resume);
  }

  void removeHandlers(StreamControllerHandlers handlers) {
    _listenHandlers.remove(handlers.listen);
    _cancelHandlers.remove(handlers.cancel);
    _pauseHandlers.remove(handlers.pause);
    _resumeHandlers.remove(handlers.resume);

    if (_listenHandlers.isEmpty) {
      sharedDestController.closeIfNeeded();
    }
  }

  void updateLatest<SourceT>(Stream<SourceT> sourceStream, SourceT event) {
    _streamState[sourceStream] = event;

    var allStreamsHaveEmitted = _streamState.length == _sourceStreams.length;
    if (allStreamsHaveEmitted) {
      var mergedEvent = _sourceStreams
        .map((stream) => _streamState[stream]!)
        .toList();
      sharedDestController.add(mergedEvent);
    }
  }
}

final class _MergeStreamsTransformer<SourceT> extends StreamLifecycleTransformer<SourceT, dynamic> {
  final _MergeStreamsManager manager;
  final int streamIdx;
  final Stream<SourceT> originalStream;

  _MergeStreamsTransformer(this.manager, {required this.streamIdx, required this.originalStream});

  late final StreamControllerHandlers handlers;

  @override
  StreamController onBindDestController(Stream<SourceT> sourceStream, StreamControllerHandlers handlers) {
    manager.addHandlers(sourceStream, handlers);
    this.handlers = handlers;
    return manager.sharedDestController;
  }

  @override
  FutureOr<StreamSubscription<SourceT>?> destOnCancel(TransformerContext<SourceT, dynamic> context) async {
    await context.sourceSubscription?.cancel();
    // manager class is responsible for closing the controller
    return null;
  }

  @override
  void sourceOnData(TransformerContext<SourceT, dynamic> context, SourceT event) {
    manager.updateLatest(context.sourceStream, event);
  }

  @override
  void sourceOnError(TransformerContext<SourceT, dynamic> context, Object error, StackTrace stackTrace) {
    var errorPacket = (index: streamIdx, stream: originalStream, error: error);
    context.destController.addError(errorPacket, stackTrace);
  }

  @override
  FutureOr<void> sourceOnDone(TransformerContext<SourceT, dynamic> context) {
    manager.removeHandlers(handlers);
    // manager class is responsible for closing the controller
  }
}