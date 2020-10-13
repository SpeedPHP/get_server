import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:get_instance/get_instance.dart';

abstract class WebSocketBase {
  void send(String msg);

  void emit(String event, Object data);

  void close([int status, String reason]);

  void join(String room);

  void leave(String room);
}

class Close {
  final WebSocket socket;
  final String message;
  final int reason;

  Close(this.socket, this.message, this.reason);
}

typedef OpenSocket = void Function(WebSocket);

typedef CloseSocket = void Function(Close);

typedef MessageSocket = void Function(dynamic val);

class SocketNotifier {
  var _onMessages = HashSet<MessageSocket>();
  var _onEvents = <String, MessageSocket>{};
  var _onCloses = HashSet<CloseSocket>();
  var _onErrors = HashSet<CloseSocket>();

  void addMessages(MessageSocket socket) {
    _onMessages.add((socket));
  }

  void addEvents(String event, MessageSocket socket) {
    _onEvents[event] = socket;
  }

  void addCloses(CloseSocket socket) {
    _onCloses.add(socket);
  }

  void addErrors(CloseSocket socket) {
    _onErrors.add((socket));
  }

  void notifyData(dynamic data) {
    for (var item in _onMessages) {
      item(data);
    }
    _tryOn(data);
  }

  void notifyClose(Close err, WebSocket _ws) {
    Get.log('Socket ${_ws.hashCode} is been disposed');

    for (var item in _onCloses) {
      item(err);
    }
  }

  void notifyError(Close err) {
    // rooms.removeWhere((key, value) => value.contains(_ws));
    for (var item in _onErrors) {
      item(err);
    }
  }

  void _tryOn(dynamic message) {
    try {
      Map msg = jsonDecode(message);
      final event = msg['type'];
      final data = msg['data'];
      if (_onEvents.containsKey(event)) {
        _onEvents[event](data);
      }
    } catch (err) {
      return;
    }
  }

  void dispose() {
    _onMessages = null;
    _onEvents = null;
    _onCloses = null;
    _onErrors = null;
  }
}

extension Idd on WebSocket {
  int get id => hashCode;

  void emit(String event, Object data) {
    add({'type': event, 'data': data});
  }
}

class GetSocket implements WebSocketBase {
  final WebSocket _ws;
  final Map<String, HashSet<WebSocket>> rooms;
  final HashSet<GetSocket> sockets;
  SocketNotifier socketNotifier = SocketNotifier();
  bool isDisposed = false;

  GetSocket(this._ws, this.rooms, this.sockets) {
    sockets.add(this);
    _ws.listen((data) {
      socketNotifier.notifyData(data);
    }, onError: (err) {
      //sockets.remove(_ws);
      socketNotifier.notifyError(Close(_ws, err.toString(), 0));
      close();
    }, onDone: () {
      sockets.remove(this);
      rooms.removeWhere((key, value) => value.contains(_ws));
      socketNotifier.notifyClose(Close(_ws, 'Connection closed', 1), _ws);
      socketNotifier.dispose();
      socketNotifier = null;
      isDisposed = true;
    });
  }

  @override
  void send(Object message) {
    _checkAvailable();
    _ws.add(message);
  }

  int get id => _ws.hashCode;

  int get length => sockets.length;

  GetSocket getSocketById(int id) {
    return sockets.firstWhere((element) => element.id == id,
        orElse: () => null);
  }

  void broadcast(Object message) {
    if (sockets.contains(_ws)) {
      sockets.forEach((element) {
        if (element != this) {
          element.send(message);
        }
      });
    }
  }

  void broadcastEvent(String event, Object data) {
    if (sockets.contains(_ws)) {
      sockets.forEach((element) {
        if (element != this) {
          element.emit(event, data);
        }
      });
    }
  }

  void sendToRoom(String room, Object message) {
    _checkAvailable();
    if (rooms.containsKey(room) && rooms.containsValue(_ws)) {
      rooms[room].forEach((element) {
        element.add(message);
      });
    }
  }

  void _checkAvailable() {
    if (isDisposed) throw 'Cannot add events to closed Socket';
  }

  void broadcastToRoom(String room, Object message) {
    _checkAvailable();
    if (rooms.containsKey(room)) {
      rooms[room].forEach((element) {
        if (element != _ws) {
          element.add(message);
        }
      });
    }
  }

  @override
  void emit(String event, Object data) {
    send({'type': event, 'data': data});
  }

  @override
  bool join(String room) {
    _checkAvailable();
    if (rooms.containsKey(room)) {
      return rooms[room].add(_ws);
    } else {
      Get.log("Room [$room] don't exists, creating it");
      rooms[room] = HashSet();
      return rooms[room].add(_ws);
    }
  }

  @override
  void leave(String room) {
    _checkAvailable();
    if (rooms.containsKey(room)) {
      rooms[room].remove(_ws);
    } else {
      Get.log("Room $room don't exists");
    }
  }

  void onOpen(OpenSocket fn) {
    fn(_ws);
  }

  void onClose(CloseSocket fn) {
    socketNotifier.addCloses(fn);
  }

  void onError(CloseSocket fn) {
    socketNotifier.addErrors(fn);
  }

  void onMessage(MessageSocket fn) {
    socketNotifier.addMessages(fn);
  }

  void on(String event, MessageSocket message) {
    socketNotifier.addEvents(event, message);
  }

  @override
  void close([int status, String reason]) {
    _ws.close(status, reason);
  }
}
