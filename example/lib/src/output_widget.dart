import 'dart:async';

import 'package:flutter/material.dart';

class OutputWidget extends StatefulWidget {
  final Stream<String> stdout;

  const OutputWidget(this.stdout, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _OutputState();
}

class _OutputState extends State<OutputWidget> {
  final items = <_OutputItem>[];

  late StreamSubscription subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(OutputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stdout != oldWidget.stdout) {
      subscription.cancel();
      _subscribe();
    }
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

  void _subscribe() {
    subscription = widget.stdout.listen((line) {
      if (line.startsWith('info')) {
        if (items.isNotEmpty && items.first.infoCount != null) {
          items.first.infoCount?.value++;
        } else {
          items.insert(0, _OutputItem.info());
        }
      } else {
        items.insert(0, _OutputItem.line(line));
      }
      setState(() {});
    });
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = items[index];
    final infoCount = item.infoCount;
    if (infoCount != null) {
      return AnimatedBuilder(
        animation: infoCount,
        builder: (_, __) => _text(item, 'info (${infoCount.value})'),
      );
    }

    final line = item.line;
    if (line != null) {
      return _text(item, line);
    }

    return const SizedBox.shrink();
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
  final ValueNotifier<int>? infoCount;
  final String? line;

  _OutputItem.info()
      : infoCount = ValueNotifier(1),
        line = null;

  _OutputItem.line(this.line) : infoCount = null;
}
