import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final _nativeLib = Platform.isAndroid
    ? DynamicLibrary.open('libstockfish.so')
    : DynamicLibrary.process();

final int Function() nativeInit = _nativeLib
    .lookup<NativeFunction<Int32 Function()>>('stockfish_init')
    .asFunction();

final int Function() nativeMain = _nativeLib
    .lookup<NativeFunction<Int32 Function()>>('stockfish_main')
    .asFunction();

final int Function(Pointer<Utf8>) nativeStdinWrite = _nativeLib
    .lookup<NativeFunction<IntPtr Function(Pointer<Utf8>)>>(
        'stockfish_stdin_write')
    .asFunction();

final Pointer<Utf8> Function() nativeStdoutRead = _nativeLib
    .lookup<NativeFunction<Pointer<Utf8> Function()>>('stockfish_stdout_read')
    .asFunction();
