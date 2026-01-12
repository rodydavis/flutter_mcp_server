import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

abstract class McpTool<R> {
  String get name;
  String get description;
  Schema get inputSchema;
  R call(Map<String, dynamic> args);

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "description": description,
      "inputSchema": inputSchema,
    };
  }
}

class InlineMcpTool extends McpTool<dynamic> {
  @override
  final String name;

  @override
  final String description;

  @override
  final Schema inputSchema;

  final dynamic Function(Map<String, dynamic>) execute;

  InlineMcpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.execute,
  });

  @override
  dynamic call(Map<String, dynamic> args) => execute(args);
}

/// Base class for the Model Context Protocol (MCP) service.
///
/// This abstract class defines the core functionality for an MCP service,
/// including state management (the counter) and message processing (JSON-RPC).
/// It extends [ChangeNotifier] to allow the UI to react to state changes.
abstract class McpService extends ChangeNotifier {
  McpService(this.name);

  final String name;
  List<McpTool> get tools;

  /// Returns the full configuration for this MCP server, including the "mcpServers" key.
  Future<Map<String, dynamic>> getMcpServersConfig() async {
    return {
      "mcpServers": {name: await getConfig()},
    };
  }

  /// Returns the transport-specific configuration for this server.
  ///
  /// For HTTP servers, this includes the 'serverUrl'.
  /// For Stdio/UDS servers, this includes the 'command' and 'args'.
  Future<Map<String, dynamic>> getConfig();

  /// Starts the MCP server.
  Future<void> startServer();

  /// Stops the MCP server and cleans up resources.
  Future<void> stopServer();

  /// Processes an incoming JSON-RPC request string and returns the JSON-RPC response string.
  ///
  /// This method handles:
  /// - JSON parsing
  /// - Method dispatching (initialize, ping, tools/list, tools/call)
  /// - Error handling
  Future<String?> processRequest(String jsonString) async {
    Map<String, dynamic>? request;
    try {
      request = jsonDecode(jsonString);
    } catch (e) {
      return jsonEncode({
        "jsonrpc": "2.0",
        "id": null,
        "error": {"code": -32700, "message": "Parse error"},
      });
    }

    if (request == null) return null;
    final id = request['id'];
    final method = request['method'];
    final params = request['params'] ?? {};

    try {
      switch (method) {
        case 'initialize':
          return _success(id, {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}, "resources": {}, "prompts": {}},
            "serverInfo": {"name": "flutter-counter-app", "version": "1.0.0"},
          });
        case 'notifications/initialized':
          return null; // No response needed
        case 'ping':
          return _success(id, {});
        case 'tools/list':
          return _success(id, {
            "tools": [for (final tool in tools) tool],
          });
        case 'tools/call':
          final name = params['name'];
          final args = params['arguments'] ?? {};
          dynamic toolResult;
          final index = tools.indexWhere((tool) => tool.name == name);
          if (index == -1) {
            throw "Tool not found: $name";
          }
          final tool = tools[index];
          toolResult = await tool(args);
          return _success(id, {
            "content": [
              {"type": "text", "text": toolResult?.toString() ?? ''},
            ],
          });
        default:
          if (id != null) {
            return _error(id, -32601, "Method not found");
          }
          return null;
      }
    } catch (e) {
      if (id != null) {
        return _error(id, -32603, "Internal error: $e");
      }
      return null;
    }
  }

  String _success(dynamic id, dynamic result) {
    return jsonEncode({"jsonrpc": "2.0", "id": id, "result": result});
  }

  String _error(dynamic id, int code, String message) {
    return jsonEncode({
      "jsonrpc": "2.0",
      "id": id,
      "error": {"code": code, "message": message},
    });
  }
}
