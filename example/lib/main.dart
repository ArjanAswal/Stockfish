import 'package:flutter/material.dart';
import 'package:stockfish/stockfish.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final stockfish = Stockfish.instance;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Stockfish example app'),
        ),
        body: Center(
          child: AnimatedBuilder(
            animation: stockfish.state,
            builder: (_, __) => Text(
              'stockfish.state=${stockfish.state.value}',
              key: ValueKey('stockfish.state'),
            ),
          ),
        ),
      ),
    );
  }
}
