import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

class Stockfish {
  final state = StockfishStateChangeNotifier();

  final _stdoutController = StreamController<String>.broadcast();
  final _mainPort = ReceivePort();
  final _stdoutPort = ReceivePort();

  StreamSubscription _mainSubscription;
  StreamSubscription _stdoutSubscription;

  Stockfish._() {
    _mainSubscription = _mainPort.listen((message) {
      if (message is int) {
        _dispose(message);
      } else {
        debugPrint('[stockfish] The main isolate sent $message');
      }
    });
    _stdoutSubscription = _stdoutPort.listen((message) {
      if (message is String) {
        _stdoutController.sink.add(message);
      } else {
        debugPrint('[stockfish] The stdout isolate sent $message');
      }
    });
    compute(_isolateInit, [_mainPort.sendPort, _stdoutPort.sendPort]).then(
      (success) =>
          state._value = success ? StockfishState.ready : StockfishState.error,
      onError: (error) {
        debugPrint('[stockfish] The init isolate encountered an error $error');
        _dispose(1, newState: StockfishState.error);
      },
    );
  }

  Stream<String> get stdout => _stdoutController.stream;

  set stdin(String line) {
    final pointer = Utf8.toUtf8('$line\n');
    _nativeStdinWrite(pointer);
    free(pointer);
  }

  void _dispose(
    int exitCode, {
    StockfishState newState = StockfishState.disposed,
  }) {
    _stdoutController.close();

    _mainSubscription?.cancel();
    _stdoutSubscription?.cancel();

    state._value = newState;

    debugPrint('[stockfish] exitCode=$exitCode');
  }

  static Future<bool> _isolateInit(List<SendPort> mainAndStdout) async {
    final nativeInit = _nativeInit();
    if (nativeInit != 0) {
      debugPrint('[stockfish] nativeInit=$nativeInit');
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

  static void _isolateMain(SendPort mainPort) {
    final exitCode = _nativeMain();
    mainPort.send(exitCode);
  }

  static void _isolateStdout(SendPort stdoutPort) {
    String previous = '';

    while (true) {
      final pointer = _nativeStdoutRead();

      if (pointer != null) {
        final data = previous + Utf8.fromUtf8(pointer);
        final lines = data.split('\n');
        previous = lines.removeLast();
        for (final line in lines) {
          stdoutPort.send(line);
        }
      } else {
        break;
      }
    }
  }

  static Stockfish _instance;
  static Stockfish get instance => _instance ??= Stockfish._();
}

enum StockfishState {
  disposed,
  error,
  ready,
  starting,
}

class StockfishStateChangeNotifier extends ChangeNotifier {
  StockfishState __value = StockfishState.starting;
  StockfishState get value => __value;
  set _value(StockfishState v) {
    if (v == __value) return;
    __value = v;
    notifyListeners();
  }
}

final _nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libstockfish.so')
    : DynamicLibrary.process();

final int Function() _nativeInit = _nativeLib
    .lookup<NativeFunction<Int32 Function()>>('stockfish_init')
    .asFunction();

final int Function() _nativeMain = _nativeLib
    .lookup<NativeFunction<Int32 Function()>>('stockfish_main')
    .asFunction();

final int Function(Pointer<Utf8>) _nativeStdinWrite = _nativeLib
    .lookup<NativeFunction<IntPtr Function(Pointer<Utf8>)>>(
        'stockfish_stdin_write')
    .asFunction();

final Pointer<Utf8> Function() _nativeStdoutRead = _nativeLib
    .lookup<NativeFunction<Pointer<Utf8> Function()>>('stockfish_stdout_read')
    .asFunction();
