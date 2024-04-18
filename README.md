# stockfish

![Pipeline](https://github.com/ArjanAswal/Stockfish/actions/workflows/pipeline.yml/badge.svg)

The Stockfish Chess Engine for Flutter.

## Example

[@PScottZero](https://github.com/PScottZero) was kind enough to create a [working chess game](https://github.com/PScottZero/EnPassant/tree/stockfish) using this package.

## Usages

iOS project must have `IPHONEOS_DEPLOYMENT_TARGET` >=12.0.

### Add dependency

Update `dependencies` section inside `pubspec.yaml`:

```yaml
  stockfish: ^1.6.0
```

### Init engine

```dart
import 'package:stockfish/stockfish.dart';

// create a new instance
final stockfish = Stockfish();

// state is a ValueListenable<StockfishState>
print(stockfish.state.value); # StockfishState.starting

// the engine takes a few moment to start
await Future.delayed(...)
print(stockfish.state.value); # StockfishState.ready
```

### UCI command

Waits until the state is ready before sending commands.

```dart
stockfish.stdin = 'isready';
stockfish.stdin = 'go movetime 3000';
stockfish.stdin = 'go infinite';
stockfish.stdin = 'stop';
```

Engine output is directed to a `Stream<String>`, add a listener to process results.

```dart
stockfish.stdout.listen((line) {
  // do something useful
  print(line);
});
```

### Dispose / Hot reload

There are two active isolates when Stockfish engine is running. That interferes with Flutter's hot reload feature so you need to dispose it before attempting to reload.

```dart
// sends the UCI quit command
stockfish.stdin = 'quit';

// or even easier...
stockfish.dispose();
```

Note: only one instance can be created at a time. The factory method `Stockfish()` will return `null` if it was called when an existing instance is active.
