import 'package:constraint_layout/constraint_layout.dart';
import 'package:flutter/material.dart';

/// A small example showing the `ConstraintLayout` API.
///
/// Positions are resolved by the pure-Dart dependency-graph engine in
/// `package:constraint_engine`.
void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConstraintLayout Example',
      home: Scaffold(
        appBar: AppBar(title: const Text('ConstraintLayout')),
        body: ConstraintLayout(
          children: [
            // Title pinned to the top and stretched across the parent.
            Constrained(
              id: #title,
              top: .topOf(parent, margin: 32),
              start: .startOf(parent),
              end: .endOf(parent),
              child: const Text(
                'Hello, ConstraintLayout!',
                textAlign: .center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),

            // A fixed 120x120 box centered horizontally, below the title.
            Constrained(
              id: #box,
              top: .bottomOf(#title, margin: 24),
              start: .startOf(parent),
              end: .endOf(parent),
              width: .fixed(120),
              height: .fixed(120),
              child: const ColoredBox(color: Colors.indigo),
            ),

            // A caption centered under the box.
            Constrained(
              id: #caption,
              top: .bottomOf(#box, margin: 16),
              start: .startOf(parent),
              end: .endOf(parent),
              child: const Text('Centered below the box'),
            ),

            // A button anchored to the bottom-end corner.
            Constrained(
              id: #fab,
              end: .endOf(parent, margin: 16),
              bottom: .bottomOf(parent, margin: 16),
              child: FloatingActionButton(
                onPressed: () {},
                child: const Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
