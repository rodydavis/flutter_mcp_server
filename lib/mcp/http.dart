// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'service.dart';

/// An MCP service implementation that uses HTTP (SSE) for transport.
///
/// It binds to a local port (starting at 8080) and handles POST/OPTIONS/GET requests.
mixin HttpMcpService on McpService {
  int? _port;
  HttpServer? _server;

  /// Returns the base URI of the running server.
  /// Throws [StateError] if server is not started.
  Future<String> get serverUri async {
    if (_port == null) throw StateError("Server not started");
    return "http://localhost:$_port";
  }

  @override
  Future<Map<String, dynamic>> getConfig() async {
    if (_port == null) {
      return {"error": "Server not running"};
    }
    return {"serverUrl": await serverUri};
  }

  Future<void> _handleIncomingHttpRequest(HttpRequest request) async {
    if (request.method == 'POST') {
      try {
        final content = await utf8.decoder.bind(request).join();
        final response = await processRequest(content);

        request.response.headers.contentType = ContentType.json;

        // Add CORS headers
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add(
          'Access-Control-Allow-Methods',
          'POST, OPTIONS',
        );
        request.response.headers.add(
          'Access-Control-Allow-Headers',
          'Content-Type',
        );

        if (response != null) {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(response);
        } else {
          request.response.statusCode = HttpStatus.accepted;
        }
      } catch (e) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(jsonEncode({"error": e.toString()}));
      }
    } else if (request.method == 'OPTIONS') {
      // Handle pre-flight CORS requests
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add(
        'Access-Control-Allow-Methods',
        'POST, OPTIONS',
      );
      request.response.headers.add(
        'Access-Control-Allow-Headers',
        'Content-Type',
      );
      request.response.statusCode = HttpStatus.ok;
    } else if (request.method == 'GET' && request.uri.path == '/') {
      request.response.headers.contentType = ContentType.text;
      request.response.write('MCP Server Running');
    } else {
      request.response.statusCode = HttpStatus.methodNotAllowed;
    }
    await request.response.close();
  }

  @override
  Future<void> startServer() async {
    int port = 8080;

    // Try to find an available port starting from 8080
    while (_server == null) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        _port = port;
      } catch (e) {
        if (e is SocketException) {
          port++;
          if (port > 65535) {
            throw Exception('Error: No available ports found.');
          }
        } else {
          rethrow;
        }
      }
    }

    print('MCP Server listening on http://localhost:$_port');
    _server!.listen(_handleIncomingHttpRequest);
  }

  @override
  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
  }
}
