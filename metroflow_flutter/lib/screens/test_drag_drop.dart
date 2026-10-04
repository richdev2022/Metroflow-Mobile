import 'package:flutter/material.dart';

class TestDragDropScreen extends StatefulWidget {
  const TestDragDropScreen({super.key});

  @override
  State<TestDragDropScreen> createState() => _TestDragDropScreenState();
}

class _TestDragDropScreenState extends State<TestDragDropScreen> {
  final List<String> statuses = ['pending', 'in_progress', 'completed'];
  String currentStatus = 'pending';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Drag & Drop')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: statuses.map((status) {
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.all(8),
                color: status == currentStatus ? Colors.green[100] : Colors.grey[100],
                child: DragTarget<String>(
                  onWillAcceptWithDetails: (details) {
                    debugPrint('DragTarget $status: onWillAcceptWithDetails');
                    return true;
                  },
                  onAcceptWithDetails: (details) {
                    debugPrint('DragTarget $status accepted data: ${details.data}');
                    setState(() {
                      currentStatus = status;
                    });
                  },
                  builder: (context, candidateData, rejectedData) {
                    return Column(
                      children: [
                        Text(status),
                        if (status == currentStatus)
                          Draggable<String>(
                            data: status,
                            feedback: Container(
                              color: Colors.blue,
                              width: 100,
                              height: 50,
                              child: const Center(child: Text('Dragging!')),
                            ),
                            onDragStarted: () => debugPrint('Drag started!'),
                            child: Container(
                              color: Colors.blue,
                              width: 100,
                              height: 50,
                              child: const Center(child: Text('Drag Me!')),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
