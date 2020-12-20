import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

class Stockfish {
  final state = ValueNotifier(StockfishState.starting);

  Stockfish._() {
    compute(_initCallback, null).then(
      (_) => state.value = StockfishState.ready,
      onError: (_) => state.value = StockfishState.error,
    );
  }

  static Stockfish _instance;
  static Stockfish get instance => _instance ??= Stockfish._();
}

enum StockfishState {
  error,
  ready,
  starting,
}

final _lib = Platform.isAndroid
    ? DynamicLibrary.open('libstockfish.so')
    : DynamicLibrary.process();

Future<void> _initCallback(Null _) async => _initNative();

final void Function() _initNative =
    _lib.lookup<NativeFunction<Void Function()>>('stockfish_init').asFunction();
