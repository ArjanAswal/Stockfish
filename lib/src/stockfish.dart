import 'dart:async';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'ffi.dart';
import 'stockfish_state.dart';

/// A wrapper for C++ engine.
class Stockfish {
  final Completer<Stockfish> completer;

  final _state = _StockfishState();
  final _stdoutController = StreamController<String>.broadcast();
  final _mainPort = ReceivePort();
  final _stdoutPort = ReceivePort();

  StreamSubscription _mainSubscription;
  StreamSubscription _stdoutSubscription;

  Stockfish._({this.completer}) {
    _mainSubscription =
        _mainPort.listen((message) => _cleanUp(message is int ? message : 1));
    _stdoutSubscription = _stdoutPort.listen((message) {
      if (message is String) {
        _stdoutController.sink.add(message);
      } else {
        debugPrint('[stockfish] The stdout isolate sent $message');
      }
    });
    compute(_spawnIsolates, [_mainPort.sendPort, _stdoutPort.sendPort]).then(
      (success) {
        final state = success ? StockfishState.ready : StockfishState.error;
        _state._setValue(state);
        if (state == StockfishState.ready) {
          completer?.complete(this);
        }
      },
      onError: (error) {
        debugPrint('[stockfish] The init isolate encountered an error $error');
        _cleanUp(1);
      },
    );
  }

  static Stockfish _instance;

  /// Creates a C++ engine.
  ///
  /// This may returns `null` if an active instance is being used.
  /// Owner must issue `quit` command to dispose it before
  /// a new instance can be created.
  factory Stockfish() {
    if (_instance != null) {
      return null;
    }

    _instance = Stockfish._();
    return _instance;
  }

  /// The current state of the underlying C++ engine.
  ValueListenable<StockfishState> get state => _state;

  /// The standard output stream.
  Stream<String> get stdout => _stdoutController.stream;

  /// The standard input sink.
  set stdin(String line) {
    final stateValue = _state.value;
    if (stateValue != StockfishState.ready) {
      throw StateError('Stockfish is not ready ($stateValue)');
    }

    final pointer = Utf8.toUtf8('$line\n');
    nativeStdinWrite(pointer);
    free(pointer);
  }

  /// Stops the C++ engine.
  void dispose() {
    stdin = 'quit';
  }

  void _cleanUp(int exitCode) {
    _stdoutController.close();

    _mainSubscription?.cancel();
    _stdoutSubscription?.cancel();

    _state._setValue(
        exitCode == 0 ? StockfishState.disposed : StockfishState.error);

    _instance = null;
  }
}

/// Creates a C++ engine asynchronously.
///
/// This method is different from the factory method [new Stockfish] that
/// it will wait for the engine to be ready before returning the instance.
Future<Stockfish> stockfishAsync() {
  if (Stockfish._instance != null) {
    return Future.error(StateError('Only one instance can be used at a time'));
  }

  final completer = Completer<Stockfish>();
  Stockfish._instance = Stockfish._(completer: completer);
  return completer.future;
}

class _StockfishState extends ChangeNotifier
    implements ValueListenable<StockfishState> {
  StockfishState _value = StockfishState.starting;

  @override
  StockfishState get value => _value;

  _setValue(StockfishState v) {
    if (v == _value) return;
    _value = v;
    notifyListeners();
  }
}

void _isolateMain(SendPort mainPort) {
  final exitCode = nativeMain();
  mainPort.send(exitCode);

  debugPrint('[stockfish] nativeMain returns $exitCode');
}

void _isolateStdout(SendPort stdoutPort) {
  String previous = '';

  while (true) {
    final pointer = nativeStdoutRead();

    if (pointer.address == 0) {
      debugPrint('[stockfish] nativeStdoutRead returns NULL');
      return;
    }

    final data = previous + Utf8.fromUtf8(pointer);
    final lines = data.split('\n');
    previous = lines.removeLast();
    for (final line in lines) {
      stdoutPort.send(line);
    }
  }
}

Future<bool> _spawnIsolates(List<SendPort> mainAndStdout) async {
  final initResult = nativeInit();
  if (initResult != 0) {
    debugPrint('[stockfish] initResult=$initResult');
    return false;
  }

  final stdoutIsolate = await Isolate.spawn(_isolateStdout, mainAndStdout[1])
      .catchError((error) => debugPrint('stdout error=$error'));
  if (stdoutIsolate == null) {
    debugPrint('[stockfish] Failed to spawn stdout isolate');
    return false;
  }

  final mainIsolate = await Isolate.spawn(_isolateMain, mainAndStdout[0])
      .catchError((error) => debugPrint('main error=$error'));
  if (mainIsolate == null) {
    debugPrint('[stockfish] Failed to spawn main isolate');
    return false;
  }

  return true;
}
