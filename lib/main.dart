import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:provider/provider.dart';

import 'mcp/http.dart';
import 'mcp/ipc.dart';
import 'mcp/service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const McpApp());
}

/// The types of transport available for the MCP service.
enum McpTransportType {
  /// Uses a local HTTP server with Server-Sent Events (SSE).
  http,

  /// Uses a Unix Domain Socket (UDS) for standard input/output bridging and pipes for Windows.
  stdio,
}

/// A service that manages a counter and exposes tools to manipulate it via MCP.
abstract class CounterMcpService extends McpService {
  CounterMcpService() : super('CounterApp');

  @override
  /// The list of tools available for this service.
  List<McpTool> get tools => [
    InlineMcpTool(
      name: 'get_value',
      description: 'Get the current value of the counter',
      inputSchema: Schema.object(),
      execute: (args) => _counter,
    ),
    InlineMcpTool(
      name: 'increment',
      description: 'Increment the counter by 1',
      inputSchema: Schema.object(),
      execute: (args) {
        increment();
        return _counter;
      },
    ),
    InlineMcpTool(
      name: 'decrement',
      description: 'Decrement the counter by 1',
      inputSchema: Schema.object(),
      execute: (args) {
        decrement();
        return _counter;
      },
    ),
    InlineMcpTool(
      name: 'reset',
      description: 'Reset the counter to 0',
      inputSchema: Schema.object(),
      execute: (args) {
        reset();
        return _counter;
      },
    ),
    InlineMcpTool(
      name: 'set_value',
      description: 'Set the counter to a specific value',
      inputSchema: Schema.object(properties: {'value': Schema.integer()}),
      execute: (args) {
        if (args['value'] case int value) {
          set(value);
        } else if (args['value'] case num value) {
          set(value.toInt());
        } else {
          throw ArgumentError('Invalid value type');
        }
        return _counter;
      },
    ),
  ];

  int _counter = 0;

  /// The current value of the counter.
  int get counter => _counter;

  // 1. Counter Logic

  /// Increments the counter by 1.
  void increment() {
    _counter++;
    notifyListeners();
  }

  /// Decrements the counter by 1.
  void decrement() {
    _counter--;
    notifyListeners();
  }

  /// Sets the counter to a specific value.
  void set(int val) {
    _counter = val;
    notifyListeners();
  }

  /// Resets the counter to 0.
  void reset() {
    _counter = 0;
    notifyListeners();
  }
}

/// An implementation of [CounterMcpService] that uses HTTP for transport.
class HttpCounterMcpService extends CounterMcpService with HttpMcpService {}

/// An implementation of [CounterMcpService] that uses Stdio (standard input/output) for transport.
class StdioCounterMcpService extends CounterMcpService with IpcMcpService {}

/// Manages the connection state and lifecycle of the active MCP service.
///
/// This class handles:
/// - Switching between transport types (HTTP <-> UDS).
/// - Preserving application state (counter value) during switches.
/// - Toggling the server on and off.
class McpConnectionManager extends ChangeNotifier {
  McpConnectionManager() {
    _init();
  }

  CounterMcpService _service = HttpCounterMcpService();

  /// The currently active MCP service instance.
  CounterMcpService get service => _service;

  McpTransportType _transportType = McpTransportType.http;

  /// The currently selected transport type.
  McpTransportType get transportType => _transportType;

  bool _isRunning = false;

  /// Whether the MCP server is currently running.
  bool get isRunning => _isRunning;

  // Preserve counter value across service switches
  int _lastCounterValue = 0;

  void _init() {
    // Initially not started
    _service.set(_lastCounterValue);
    // toggleServer(true);
  }

  /// Sets the transport type, stopping the current service and starting a new one.
  Future<void> setTransport(McpTransportType type) async {
    if (_transportType == type) return;

    // Save state
    _lastCounterValue = _service.counter;

    // Stop current service if running
    if (_isRunning) {
      await _service.stopServer();
    }

    _transportType = type;

    // Create new service
    switch (type) {
      case McpTransportType.http:
        _service = HttpCounterMcpService();
        break;
      case McpTransportType.stdio:
        _service = StdioCounterMcpService();
        break;
    }

    // Restore state
    _service.set(_lastCounterValue);

    // Restart if was running
    if (_isRunning) {
      try {
        await _service.startServer();
      } catch (e) {
        print("Failed to restart server after switch: $e");
        _isRunning = false;
      }
    }
    notifyListeners();
  }

  /// Toggles the server running state.
  Future<void> toggleServer(bool value) async {
    if (_isRunning == value) return;

    _isRunning = value;
    notifyListeners();

    try {
      if (_isRunning) {
        await _service.startServer();
      } else {
        await _service.stopServer();
      }
    } catch (e) {
      print("Error toggling server: $e");
      _isRunning = false;
      notifyListeners();
    }
  }
}

/// The root widget of the MCP Counter Application.
class McpApp extends StatelessWidget {
  const McpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => McpConnectionManager(),
      child: const MaterialApp(
        home: CounterPage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

/// The main page displaying the counter and MCP controls.
class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  /// Shows a dialog with the current MCP configuration, allowing the user to copy it.
  void _showConfig(BuildContext context, Map<String, dynamic> config) {
    const encoder = JsonEncoder.withIndent('  ');
    final jsonConfig = encoder.convert(config);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('MCP Configuration'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add this to your MCP config:'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey[200],
                child: Text(
                  jsonConfig,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonConfig));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Config copied to clipboard!')),
              );
              Navigator.pop(context);
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Access manager to get the current service
    final manager = context.watch<McpConnectionManager>();

    // Provide the specific McpService to the subtree so Consumers work correctly
    return ChangeNotifierProvider<CounterMcpService>.value(
      value: manager.service,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('MCP Counter'),
          actions: [
            Builder(
              builder: (context) {
                return IconButton(
                  icon: const Icon(Icons.info_outline),
                  onPressed: () async {
                    // Use the current service from the manager
                    final config = await manager.service.getMcpServersConfig();
                    if (context.mounted) {
                      _showConfig(context, config);
                    }
                  },
                  tooltip: 'Show MCP Config',
                );
              },
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Transport Selection
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SegmentedButton<McpTransportType>(
                  segments: const [
                    ButtonSegment(
                      value: McpTransportType.http,
                      label: Text('HTTP'),
                      icon: Icon(Icons.http),
                    ),
                    ButtonSegment(
                      value: McpTransportType.stdio,
                      label: Text('STDIO (UDS)'),
                      icon: Icon(Icons.terminal),
                    ),
                  ],
                  selected: {manager.transportType},
                  onSelectionChanged: (Set<McpTransportType> newSelection) {
                    manager.setTransport(newSelection.first);
                  },
                ),
              ),
              const SizedBox(height: 20),
              // Server Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Server Status: '),
                  Switch(
                    value: manager.isRunning,
                    onChanged: (val) => manager.toggleServer(val),
                  ),
                  Text(manager.isRunning ? 'Running' : 'Stopped'),
                ],
              ),
              const Divider(),
              const SizedBox(height: 20),
              const Text('Current Value:', style: TextStyle(fontSize: 24)),
              Consumer<CounterMcpService>(
                builder: (context, mcp, child) {
                  return Text(
                    '${mcp.counter}',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Consumer<CounterMcpService>(
              builder: (context, mcp, _) => FloatingActionButton(
                onPressed: () => mcp.increment(),
                tooltip: 'Increment',
                child: const Icon(Icons.add),
              ),
            ),
            const SizedBox(height: 10),
            Consumer<CounterMcpService>(
              builder: (context, mcp, _) => FloatingActionButton(
                onPressed: () => mcp.decrement(),
                tooltip: 'Decrement',
                child: const Icon(Icons.remove),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
