import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:stockfish/stockfish.dart';

import 'src/output_widget.dart';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<StatefulWidget> createState() => _AppState();
}

class _AppState extends State<MyApp> {
  late Stockfish stockfish;

  @override
  void initState() {
    super.initState();
    stockfish = Stockfish();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Stockfish example app'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: AnimatedBuilder(
                animation: stockfish.state,
                builder: (_, __) => Text(
                  'stockfish.state=${stockfish.state.value}',
                  key: const ValueKey('stockfish.state'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: AnimatedBuilder(
                animation: stockfish.state,
                builder: (_, __) => ElevatedButton(
                  onPressed: stockfish.state.value == StockfishState.disposed
                      ? () {
                          final newInstance = Stockfish();
                          setState(() => stockfish = newInstance);
                        }
                      : null,
                  child: const Text('Reset Stockfish instance'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Custom UCI command',
                  hintText: 'go infinite',
                ),
                onSubmitted: (value) => stockfish.stdin = value,
                textInputAction: TextInputAction.send,
              ),
            ),
            Wrap(
              children: [
                'd',
                'isready',
                'go infinite',
                'go movetime 3000',
                'stop',
                'quit',
              ]
                  .map(
                    (command) => Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton(
                        onPressed: () => stockfish.stdin = command,
                        child: Text(command),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            Expanded(
              child: OutputWidget(stockfish.stdout),
            ),
          ],
        ),
      ),
    );
  }
}
