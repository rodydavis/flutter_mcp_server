# 🚀 Flutter MCP Server

A cutting-edge Flutter application that demonstrates how to expose internal application logic as tools to AI agents using the **Model Context Protocol (MCP)**. This project serves as a bridge between high-level user interfaces and agentic intelligence, allowing LLMs to interact directly with your app's state.

---

## ✨ Key Features

- **🔌 Dual-Transport Support**: seamless switching between **HTTP (Server-Sent Events)** and **Stdio (Unix Domain Sockets/Named Pipes)**.
- **🧱 Modular MCP Service**: easily extendable base class for exposing your own application tools.
- **⚙️ Dynamic Configuration**: automatically generates the required JSON configuration for MCP clients.
- **📱 Real-time UI Updates**: application state (like the counter) updates instantly when manipulated by an AI agent.
- **🧪 Built-in Playground**: a simple counter interface to test tool execution and state synchronization.

---

## 🛠️ MCP Tools Exposed

The application currently exposes the following tools to any connected MCP client:

| Tool Name | Description | Parameters |
| :--- | :--- | :--- |
| `get_value` | Retrieves the current value of the application counter. | None |
| `increment` | Increases the counter by 1. | None |
| `decrement` | Decreases the counter by 1. | None |
| `reset` | Sets the counter back to 0. | None |
| `set_value` | Sets the counter to a specific integer value. | `value` (integer) |

---

## 🚀 Getting Started

### 1. Run the Flutter App
Ensure you have the Flutter SDK installed. Clone the repository and run:

```bash
flutter pub get
flutter run
```

### 2. Configure MCP Client
To let an MCP client interact with your app, you need to add it to your `config.json`.

1. Click the **ℹ️ Info** icon in the app's top bar.
2. Select your preferred transport (HTTP or STDIO).
3. Copy the generated configuration.
4. Paste it into your config file and reload servers if needed.

### 3. Start Chatting
Open your MCP client, and you should see the `CounterApp` tools available. Ask it to:
- *"Check what the current counter value is"*
- *"Set the counter to 42"*
- *"Increment the counter for me"*

---

## 🏗️ Architecture

The following classes are used to implement the MCP server:

- **`McpService`**: The base class for defining tool schemas and execution logic.
- **`HttpMcpService`**: Mixin providing SSE-based transport.
- **`IpcMcpService`**: Mixin providing Stdio-based transport via UDS/Pipes.
- **`McpConnectionManager`**: Orchestrates state preservation during transport switches.
