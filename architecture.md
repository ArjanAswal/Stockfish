# Stockfish Flutter Package - Deep Dive

This package wraps the **Stockfish chess engine** (C++) for use in Flutter applications on Android and iOS. It uses **Dart FFI (Foreign Function Interface)** to communicate between Dart and native C++ code.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Dart Layer                               │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Stockfish class (lib/src/stockfish.dart)                   │ │
│  │  - stdin (setter) → sends UCI commands                      │ │
│  │  - stdout (stream) → receives engine output                 │ │
│  │  - state (ValueListenable) → tracks engine state            │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│                       FFI Bindings                               │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  ffi.dart - Loads native library & defines function bindings│ │
│  │  - nativeInit()       - nativeMain()                        │ │
│  │  - nativeStdinWrite() - nativeStdoutRead()                  │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                               │
                      DynamicLibrary.open()
                               │
┌─────────────────────────────────────────────────────────────────┐
│                      Native C++ Layer                            │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  ffi.cpp - Bridge between Dart and Stockfish                │ │
│  │  - Creates pipes for stdin/stdout redirection               │ │
│  │  - Exposes C functions callable from Dart                   │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Stockfish Engine (ios/Stockfish/src/*)                     │ │
│  │  - UCI protocol implementation                              │ │
│  │  - NNUE neural network evaluation                           │ │
│  │  - Search, movegen, etc.                                    │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## How the Dart Layer Works

### 1. Stockfish Class (`lib/src/stockfish.dart`)

```43:50:lib/src/stockfish.dart
    },
    );
  }

  static Stockfish? _instance;

  /// Creates a C++ engine.
  ///
```

The `Stockfish` class is a **singleton** - only one instance can exist at a time. When created:

1. **Two Dart Isolates are spawned** (in separate compute contexts):
   - **Main Isolate**: Runs `nativeMain()` which starts the Stockfish engine loop
   - **Stdout Isolate**: Continuously polls `nativeStdoutRead()` to get engine output

2. **State management** via `ValueListenable<StockfishState>`:
   - `starting` → Engine is initializing
   - `ready` → Engine is running and accepting commands
   - `disposed` → Engine has been shut down
   - `error` → Engine failed to start

### 2. FFI Bindings (`lib/src/ffi.dart`)

```6:25:lib/src/ffi.dart
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
```

**Key difference between platforms:**
- **Android**: Loads `libstockfish.so` as a separate shared library
- **iOS**: Uses `DynamicLibrary.process()` - symbols are linked into the main process

Four FFI functions are exposed:
| Function                       | Purpose                                    |
| ------------------------------ | ------------------------------------------ |
| `stockfish_init()`             | Creates pipes for stdin/stdout redirection |
| `stockfish_main()`             | Starts the Stockfish main loop             |
| `stockfish_stdin_write(char*)` | Sends UCI commands to the engine           |
| `stockfish_stdout_read()`      | Reads output from the engine               |

---

## iOS Implementation

### Plugin Structure

```
ios/
├── Classes/
│   ├── StockfishPlugin.h          # Flutter plugin header
│   └── StockfishPlugin.mm         # Plugin registration (prevents dead code stripping)
├── FlutterStockfish/
│   ├── ffi.cpp                    # FFI bridge implementation
│   └── ffi.h                      # C function declarations
├── Stockfish/src/                 # Full Stockfish source code
└── stockfish.podspec              # CocoaPods configuration
```

### FFI Bridge (`ffi.cpp`)

```31:73:ios/FlutterStockfish/ffi.cpp
int stockfish_init()
{
  pipe(pipes[PARENT_READ_PIPE]);
  pipe(pipes[PARENT_WRITE_PIPE]);

  return 0;
}

int stockfish_main()
{
  dup2(CHILD_READ_FD, STDIN_FILENO);
  dup2(CHILD_WRITE_FD, STDOUT_FILENO);

  int argc = 1;
  char *argv[] = {""};
  int exitCode = main(argc, argv);

  std::cout << QUITOK << std::flush;

  return exitCode;
}

ssize_t stockfish_stdin_write(char *data)
{
  return write(PARENT_WRITE_FD, data, strlen(data));
}

char *stockfish_stdout_read()
{
  ssize_t count = read(PARENT_READ_FD, buffer, sizeof(buffer) - 1);
  if (count < 0)
  {
    return NULL;
  }

  buffer[count] = 0;
  if (strcmp(buffer, QUITOK) == 0)
  {
    return NULL;
  }

  return buffer;
}
```

**How it works:**

1. **`stockfish_init()`**: Creates two Unix pipes to redirect stdin/stdout
2. **`stockfish_main()`**:
   - Redirects stdin/stdout file descriptors to the pipes
   - Calls Stockfish's `main()` function, entering the UCI loop
   - Outputs `quitok\n` when engine exits
3. **`stockfish_stdin_write()`**: Writes data to the pipe that Stockfish reads as stdin
4. **`stockfish_stdout_read()`**: Reads from the pipe that Stockfish writes to (blocking read)

### Plugin Registration (Prevents Dead Code Stripping)

```4:13:ios/Classes/StockfishPlugin.mm
@implementation StockfishPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  if (registrar == NULL) {
    // avoid dead code stripping
    stockfish_init();
    stockfish_main();
    stockfish_stdin_write(NULL);
    stockfish_stdout_read();
  }
}

@end
```

This code is **never actually executed** (registrar is never NULL), but its presence ensures the linker doesn't strip out the FFI symbols.

### Build Configuration (`stockfish.podspec`)

```28:49:ios/stockfish.podspec

  # Additional compiler configuration required for Stockfish
  s.library = 'c++'
  s.script_phase = [
    {
      :execution_position => :before_compile,
      :name => 'Download nnue',
      :script => "[ -e 'nn-1111cefa1111.nnue' ] || curl --location --remote-name 'https://tests.stockfishchess.org/api/nn/nn-1111cefa1111.nnue'"
    },
    {
      :execution_position => :before_compile,
      :name => 'Download small nnue',
      :script => "[ -e 'nn-37f18f62d772.nnue' ] || curl --location --remote-name 'https://tests.stockfishchess.org/api/nn/nn-37f18f62d772.nnue'"
    },
  ]
  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS[config=Debug]' => '$(inherited) -std=c++17 -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT',
    'OTHER_LDFLAGS[config=Debug]' => '$(inherited) -std=c++17 -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT',
    'OTHER_CPLUSPLUSFLAGS[config=Release]' => '$(inherited) -fno-exceptions -std=c++17 -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8 -flto=full',
    'OTHER_LDFLAGS[config=Release]' => '$(inherited) -fno-exceptions -std=c++17 -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8 -flto=full'
  }
end
```

Key points:
- **Downloads NNUE files** (neural network weights) before compilation
- **C++17** standard required
- **NEON SIMD** enabled for ARM64 devices in Release mode
- Minimum iOS deployment target: **12.0**

---

## Android Implementation

### Plugin Structure

```
android/
├── src/main/java/com/stockfish/
│   └── StockfishPlugin.java       # Empty Flutter plugin (no-op)
├── build.gradle                    # Gradle build configuration
└── CMakeLists.txt                  # CMake configuration for NDK
```

### CMake Configuration

```1:27:android/CMakeLists.txt
cmake_minimum_required(VERSION 3.4.1)

file(GLOB_RECURSE cppPaths "../ios/Stockfish/src/*.cpp")
add_library(
  stockfish
  SHARED
  ../ios/FlutterStockfish/ffi.cpp
  ${cppPaths}
)

if(ANDROID_ABI STREQUAL arm64-v8a)
  if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(stockfish PRIVATE -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8)
  else()
    target_compile_options(stockfish PRIVATE -fno-exceptions -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8)
  endif()
else()
  if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(stockfish PRIVATE -DUSE_PTHREADS)
  else()
    target_compile_options(stockfish PRIVATE -fno-exceptions -DUSE_PTHREADS -DNDEBUG -O3)
  endif()
endif()

file(DOWNLOAD https://tests.stockfishchess.org/api/nn/nn-1111cefa1111.nnue ${CMAKE_BINARY_DIR}/nn-1111cefa1111.nnue)
file(DOWNLOAD https://tests.stockfishchess.org/api/nn/nn-37f18f62d772.nnue ${CMAKE_BINARY_DIR}/nn-37f18f62d772.nnue)
```

**Key points:**

1. **Reuses the same source code** as iOS (`../ios/FlutterStockfish/ffi.cpp` and `../ios/Stockfish/src/*.cpp`)
2. **Builds `libstockfish.so`** - a shared library
3. **Architecture-specific optimizations**:
   - `arm64-v8a`: NEON SIMD, POPCNT, 64-bit optimizations
   - Other ABIs (armeabi-v7a, x86_64): Basic threading support only
4. **Downloads NNUE files** during build

### Gradle Configuration

```31:52:android/build.gradle
    compileSdkVersion 35

    defaultConfig {
        minSdkVersion 21
        ndk {
            abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64'
        }
        externalNativeBuild {
            cmake {
                cppFlags "-std=c++17"
            }
        }
    }
    lintOptions {
        disable 'InvalidPackage'
    }
    externalNativeBuild {
        cmake {
            path "CMakeLists.txt"
        }
    }
}
```

- **Minimum SDK**: 21 (Android 5.0)
- **Supported ABIs**: arm64-v8a, armeabi-v7a, x86_64
- **C++17** standard

---

## Communication Flow

```
┌──────────────────┐     UCI Commands      ┌──────────────────────────────┐
│                  │  ─────────────────►   │                              │
│   Dart App       │      (via pipe)       │      Stockfish Engine        │
│                  │  ◄─────────────────   │         (C++)                │
│                  │     UCI Output        │                              │
└──────────────────┘      (via pipe)       └──────────────────────────────┘

                    Dart Side                       Native Side
┌────────────────────────────────┐    ┌────────────────────────────────────┐
│ stockfish.stdin = 'go movetime │    │ stockfish_stdin_write() writes to  │
│ 3000'                          │───►│ pipe → Stockfish reads via stdin   │
├────────────────────────────────┤    ├────────────────────────────────────┤
│ stockfish.stdout.listen()      │◄───│ Stockfish writes to stdout → pipe  │
│ receives "bestmove e2e4"       │    │ → stockfish_stdout_read() returns  │
└────────────────────────────────┘    └────────────────────────────────────┘
```

---

## NNUE Neural Networks

Stockfish uses **NNUE (Efficiently Updatable Neural Network)** for position evaluation. Two network files are downloaded:

| File                   | Purpose                                  |
| ---------------------- | ---------------------------------------- |
| `nn-1111cefa1111.nnue` | Main evaluation network                  |
| `nn-37f18f62d772.nnue` | Smaller network (for specific positions) |

These are embedded into the binary at compile time.

---

## Usage Example

```dart
import 'package:stockfish/stockfish.dart';

// Create engine instance
final stockfish = Stockfish();

// Wait for engine to be ready
stockfish.state.addListener(() {
  if (stockfish.state.value == StockfishState.ready) {
    // Send UCI commands
    stockfish.stdin = 'uci';
    stockfish.stdin = 'position startpos moves e2e4';
    stockfish.stdin = 'go movetime 3000';
  }
});

// Listen to engine output
stockfish.stdout.listen((line) {
  print(line);  // "bestmove d7d5 ponder e4e5"
});

// Dispose when done
stockfish.dispose();  // or stockfish.stdin = 'quit'
```

---

## Key Differences: iOS vs Android

| Aspect               | iOS                                                  | Android                                  |
| -------------------- | ---------------------------------------------------- | ---------------------------------------- |
| Library Loading      | `DynamicLibrary.process()` (linked into main binary) | `DynamicLibrary.open('libstockfish.so')` |
| Build System         | CocoaPods (podspec)                                  | CMake via NDK                            |
| Dead Code Prevention | Fake function calls in plugin                        | Not needed (shared library)              |
| Minimum Version      | iOS 12.0                                             | Android SDK 21                           |
| SIMD Optimization    | NEON (ARM64)                                         | NEON (arm64-v8a only)                    |

```plaintext
┌─────────────────────────────────────────────────────────────────┐
│                         Dart Layer                               │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Stockfish class (lib/src/stockfish.dart)                   │ │
│  │  - stdin (setter) → sends UCI commands                      │ │
│  │  - stdout (stream) → receives engine output                 │ │
│  │  - state (ValueListenable) → tracks engine state            │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│                       FFI Bindings                               │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  ffi.dart - Loads native library & defines function bindings│ │
│  │  - nativeInit()       - nativeMain()                        │ │
│  │  - nativeStdinWrite() - nativeStdoutRead()                  │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                               │
                      DynamicLibrary.open()
                               │
┌─────────────────────────────────────────────────────────────────┐
│                      Native C++ Layer                            │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  ffi.cpp - Bridge between Dart and Stockfish                │ │
│  │  - Creates pipes for stdin/stdout redirection               │ │
│  │  - Exposes C functions callable from Dart                   │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Stockfish Engine (ios/Stockfish/src/*)                     │ │
│  │  - UCI protocol implementation                              │ │
│  │  - NNUE neural network evaluation                           │ │
│  │  - Search, movegen, etc.                                    │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

```dart
    },
    );
  }

  static Stockfish? _instance;

  /// Creates a C++ engine.
  ///
```

```dart
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
```

```plaintext
ios/
├── Classes/
│   ├── StockfishPlugin.h          # Flutter plugin header
│   └── StockfishPlugin.mm         # Plugin registration (prevents dead code stripping)
├── FlutterStockfish/
│   ├── ffi.cpp                    # FFI bridge implementation
│   └── ffi.h                      # C function declarations
├── Stockfish/src/                 # Full Stockfish source code
└── stockfish.podspec              # CocoaPods configuration
```

```cpp
int stockfish_init()
{
  pipe(pipes[PARENT_READ_PIPE]);
  pipe(pipes[PARENT_WRITE_PIPE]);

  return 0;
}

int stockfish_main()
{
  dup2(CHILD_READ_FD, STDIN_FILENO);
  dup2(CHILD_WRITE_FD, STDOUT_FILENO);

  int argc = 1;
  char *argv[] = {""};
  int exitCode = main(argc, argv);

  std::cout << QUITOK << std::flush;

  return exitCode;
}

ssize_t stockfish_stdin_write(char *data)
{
  return write(PARENT_WRITE_FD, data, strlen(data));
}

char *stockfish_stdout_read()
{
  ssize_t count = read(PARENT_READ_FD, buffer, sizeof(buffer) - 1);
  if (count < 0)
  {
    return NULL;
  }

  buffer[count] = 0;
  if (strcmp(buffer, QUITOK) == 0)
  {
    return NULL;
  }

  return buffer;
}
```

```plaintext
@implementation StockfishPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  if (registrar == NULL) {
    // avoid dead code stripping
    stockfish_init();
    stockfish_main();
    stockfish_stdin_write(NULL);
    stockfish_stdout_read();
  }
}

@end
```

```plaintext

  # Additional compiler configuration required for Stockfish
  s.library = 'c++'
  s.script_phase = [
    {
      :execution_position => :before_compile,
      :name => 'Download nnue',
      :script => "[ -e 'nn-1111cefa1111.nnue' ] || curl --location --remote-name 'https://tests.stockfishchess.org/api/nn/nn-1111cefa1111.nnue'"
    },
    {
      :execution_position => :before_compile,
      :name => 'Download small nnue',
      :script => "[ -e 'nn-37f18f62d772.nnue' ] || curl --location --remote-name 'https://tests.stockfishchess.org/api/nn/nn-37f18f62d772.nnue'"
    },
  ]
  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS[config=Debug]' => '$(inherited) -std=c++17 -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT',
    'OTHER_LDFLAGS[config=Debug]' => '$(inherited) -std=c++17 -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT',
    'OTHER_CPLUSPLUSFLAGS[config=Release]' => '$(inherited) -fno-exceptions -std=c++17 -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8 -flto=full',
    'OTHER_LDFLAGS[config=Release]' => '$(inherited) -fno-exceptions -std=c++17 -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8 -flto=full'
  }
end
```

```plaintext
android/
├── src/main/java/com/stockfish/
│   └── StockfishPlugin.java       # Empty Flutter plugin (no-op)
├── build.gradle                    # Gradle build configuration
└── CMakeLists.txt                  # CMake configuration for NDK
```

```plaintext
cmake_minimum_required(VERSION 3.4.1)

file(GLOB_RECURSE cppPaths "../ios/Stockfish/src/*.cpp")
add_library(
  stockfish
  SHARED
  ../ios/FlutterStockfish/ffi.cpp
  ${cppPaths}
)

if(ANDROID_ABI STREQUAL arm64-v8a)
  if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(stockfish PRIVATE -DUSE_PTHREADS -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8)
  else()
    target_compile_options(stockfish PRIVATE -fno-exceptions -DUSE_PTHREADS -DNDEBUG -O3 -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8)
  endif()
else()
  if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(stockfish PRIVATE -DUSE_PTHREADS)
  else()
    target_compile_options(stockfish PRIVATE -fno-exceptions -DUSE_PTHREADS -DNDEBUG -O3)
  endif()
endif()

file(DOWNLOAD https://tests.stockfishchess.org/api/nn/nn-1111cefa1111.nnue ${CMAKE_BINARY_DIR}/nn-1111cefa1111.nnue)
file(DOWNLOAD https://tests.stockfishchess.org/api/nn/nn-37f18f62d772.nnue ${CMAKE_BINARY_DIR}/nn-37f18f62d772.nnue)
```

```plaintext
    compileSdkVersion 35

    defaultConfig {
        minSdkVersion 21
        ndk {
            abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64'
        }
        externalNativeBuild {
            cmake {
                cppFlags "-std=c++17"
            }
        }
    }
    lintOptions {
        disable 'InvalidPackage'
    }
    externalNativeBuild {
        cmake {
            path "CMakeLists.txt"
        }
    }
}
```

```plaintext
┌──────────────────┐     UCI Commands      ┌──────────────────────────────┐
│                  │  ─────────────────►   │                              │
│   Dart App       │      (via pipe)       │      Stockfish Engine        │
│                  │  ◄─────────────────   │         (C++)                │
│                  │     UCI Output        │                              │
└──────────────────┘      (via pipe)       └──────────────────────────────┘

                    Dart Side                       Native Side
┌────────────────────────────────┐    ┌────────────────────────────────────┐
│ stockfish.stdin = 'go movetime │    │ stockfish_stdin_write() writes to  │
│ 3000'                          │───►│ pipe → Stockfish reads via stdin   │
├────────────────────────────────┤    ├────────────────────────────────────┤
│ stockfish.stdout.listen()      │◄───│ Stockfish writes to stdout → pipe  │
│ receives "bestmove e2e4"       │    │ → stockfish_stdout_read() returns  │
└────────────────────────────────┘    └────────────────────────────────────┘
```

```dart
import 'package:stockfish/stockfish.dart';

// Create engine instance
final stockfish = Stockfish();

// Wait for engine to be ready
stockfish.state.addListener(() {
  if (stockfish.state.value == StockfishState.ready) {
    // Send UCI commands
    stockfish.stdin = 'uci';
    stockfish.stdin = 'position startpos moves e2e4';
    stockfish.stdin = 'go movetime 3000';
  }
});

// Listen to engine output
stockfish.stdout.listen((line) {
  print(line);  // "bestmove d7d5 ponder e4e5"
});

// Dispose when done
stockfish.dispose();  // or stockfish.stdin = 'quit'
```

