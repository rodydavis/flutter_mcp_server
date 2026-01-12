// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:posix/posix.dart' as posix;
import 'package:path_provider/path_provider.dart';
import 'package:dart_ipc/dart_ipc.dart';

import 'service.dart';

/// An MCP service implementation that uses Stdio over a Unix Domain Socket (UDS) and Pipes on Windows.
///
/// It bridges standard input/output behavior for MCP clients by providing a
/// socket that clients can connect to via `nc -U` or native UDS support.
mixin IpcMcpService on McpService {
  String? _socketPath;
  ServerSocket? _server;

  @override
  Future<Map<String, dynamic>> getConfig() async {
    return {
      "command": "nc",
      "args": ["-U", _socketPath ?? ""],
    };
  }

  @override
  Future<void> startServer() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _socketPath = p.join(dir.path, 'mcp.sock');

      // Ensure directory exists
      await dir.create(recursive: true);

      // Clean up socket file using reliable type checking
      final type = FileSystemEntity.typeSync(_socketPath!);
      if (type != FileSystemEntityType.notFound) {
        try {
          File(_socketPath!).deleteSync();
        } catch (e) {
          print("Warning: Failed to delete existing socket file: $e");
        }
      }

      _server = await bind(_socketPath!);

      // Set permissions to 600 (owner read/write only)
      try {
        if (!Platform.isWindows) {
          posix.chmod(_socketPath!, '0600');
        }
      } catch (e) {
        print('Error setting socket permissions: $e');
      }

      print('MCP Server listening on unix socket: $_socketPath');

      _server!.listen((Socket client) {
        print('Client connected: ${client.remoteAddress}');

        client
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (String line) async {
                if (line.trim().isEmpty) return;
                try {
                  final response = await processRequest(line);
                  if (response != null) {
                    client.write('$response\n');
                  }
                } catch (e) {
                  print('Error processing UDS request: $e');
                  // Optionally send JSON-RPC error back
                }
              },
              onDone: () {
                print('Client disconnected');
                client.destroy();
              },
              onError: (e) {
                print('Client connection error: $e');
                client.destroy();
              },
            );
      });
    } catch (e) {
      print('Failed to start StdioMcpService: $e');
      rethrow;
    }
  }

  @override
  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
    if (_socketPath != null) {
      final type = FileSystemEntity.typeSync(_socketPath!);
      if (type != FileSystemEntityType.notFound) {
        try {
          File(_socketPath!).deleteSync();
        } catch (_) {}
      }
    }
  }
}
