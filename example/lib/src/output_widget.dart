import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stockfish/stockfish.dart';

class OutputWidget extends StatefulWidget {
  const OutputWidget({Key key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _OutputState();
}

class _OutputState extends State<OutputWidget> {
  final stockfish = Stockfish.instance;
  final items = <_OutputItem>[];

  StreamSubscription subscription;

  @override
  void initState() {
    super.initState();

    subscription = stockfish.stdout.listen((line) {
      if (line.startsWith('info')) {
        if (items.isNotEmpty && items.first.infoCount != null) {
          items.first.infoCount.value++;
        } else {
          items.insert(0, _OutputItem.info());
        }
      } else {
        items.insert(0, _OutputItem.line(line));
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemBuilder: _buildItem,
      itemCount: items.length,
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = items[index];
    if (item.infoCount != null) {
      return AnimatedBuilder(
        animation: item.infoCount,
        builder: (_, __) => _text(item, 'info (${item.infoCount.value})'),
      );
    }

    return _text(item, item.line);
  }

  Widget _text(_OutputItem item, String data) => Padding(
        key: ObjectKey(item),
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 8,
        ),
        child: Text(
          data,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
}

class _OutputItem {
  final ValueNotifier<int> infoCount;
  final String line;

  _OutputItem.info()
      : infoCount = ValueNotifier(1),
        line = null;

  _OutputItem.line(this.line) : infoCount = null;
}
