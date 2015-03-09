#!/usr/bin/env dart

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http_server/http_server.dart' show VirtualDirectory;
import 'package:args/args.dart';
import 'package:watcher/watcher.dart';

import 'lib/server_helper.dart' as help;
import 'lib/client_responses.dart';

VirtualDirectory virDir;
DirectoryWatcher watcher;

String defaultWorkspacePath = '/home/user/workspace';
String defaultGuiPath = '/etc/updroid/web';
bool defaultDebugFlag = false;

/// Handler for the [WebSocket]. Performs various actions depending on requests
/// it receives or local events that it detects.
void handleWebSocket(WebSocket socket, Directory dir) {
  help.debug('Client connected!', 0);
  StreamController<String> processInput = new StreamController<String>.broadcast();

  Process bash;
  IOSink shellStdin;
  List<int> inputEcho = [];
  Process.start('bash', ['-i'], workingDirectory: dir.path).then((Process shell) {
    bash = shell;
    shellStdin = shell.stdin;
    shell.stdout.listen((data) {
      help.debug('stdout: ' + data.toString(), 0);
      socket.add('[[CONSOLE_OUTPUT]]' + JSON.encode(data));
    });

    shell.stderr.listen((data) {
      List err = new List.from(data, growable: true);
      if (inputEcho.isNotEmpty) {
        help.debug('echo: ' + inputEcho.toString(), 0);
        err.removeWhere((char) => inputEcho.contains(char));
      }
      help.debug('stderr: ' + err.toString(), 0);
      socket.add('[[CONSOLE_OUTPUT]]' + JSON.encode(err));
      inputEcho = [];
    });
  });

  socket.listen((String s) {
    help.UpDroidMessage um = new help.UpDroidMessage(s);
    help.debug('Incoming message: ' + s, 0);

    switch (um.header) {
      case 'EXPLORER_DIRECTORY_PATH':
        sendPath(socket, dir);
        break;

      case 'EXPLORER_DIRECTORY_LIST':
        sendDirectory(socket, dir);
        break;

      case 'EXPLORER_DIRECTORY_REFRESH':
        refreshDirectory(socket, dir);
        break;

      case 'EXPLORER_NEW_FILE':
        fsNewFile(um.body);
        break;

      case 'EXPLORER_NEW_FOLDER':
        fsNewFolder(um.body);
        // Empty folders don't trigger an incremental update, so we need to
        // refresh the entire workspace.
        sendDirectory(socket, dir);
        break;

      case 'EXPLORER_RENAME':
        fsRename(um.body);
        break;

      case 'EXPLORER_MOVE':
        // Currently implemented in the same way as RENAME as there is no
        // direct API for MOVE.
        fsRename(um.body);
        break;

      case 'EXPLORER_DELETE':
        fsDelete(um.body, socket);
        break;

      case 'EDITOR_OPEN':
        sendFileContents(socket, um.body);
        break;

      case 'EDITOR_SAVE':
        saveFile(um.body);
        break;

      case 'EDITOR_REQUEST_FILENAME':
        requestFilename(socket, um.body);
        break;

      case 'CONSOLE_COMMAND':
        processCommand(socket, processInput, um.body, dir);
        break;

      case 'CONSOLE_INVALID':
        sendErrorMessage(socket);
        break;

      case 'CONSOLE_INPUT':
        inputEcho.addAll(JSON.decode(um.body));
        shellStdin.add(JSON.decode(um.body));
        break;

      default:
        help.debug('Message received without updroid header.', 1);
    }
  }, onDone: () {
    help.debug('Client disconnected... killing shell process', 0);
    // Kill the shell process.
    bash.kill();
  }, onError: () {
    help.debug('Socket error... killing shell process', 1);
    // Kill the shell process.
    bash.kill();
  });

  watcher.events.listen((e) => help.formattedFsUpdate(socket, e));
}

void initServer(dir) {
  // Set up an HTTP webserver and listen for standard page requests or upgraded
  // [WebSocket] requests.
  HttpServer.bind(InternetAddress.ANY_IP_V4, 12060).then((HttpServer server) {
    help.debug("HttpServer listening on port:${server.port}...", 0);
    server.listen((HttpRequest request) {
      // WebSocket requests are considered "upgraded" HTTP requests.
      help.debug("${request.method} request for: ${request.uri.path}", 0);
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        WebSocketTransformer.upgrade(request).then((WebSocket ws) => handleWebSocket(ws, dir));
      } else {
        virDir.serveRequest(request);
      }
    });
  });
}

void directoryHandler(dir, request) {
  var indexUri = new Uri.file(dir.path).resolve('index.html');
  virDir.serveFile(new File(indexUri.toFilePath()), request);
}

void main(List<String> args) {
  // Create an args parser.
  var parser = new ArgParser();
  parser.addFlag('debug', abbr: 'd', defaultsTo: defaultDebugFlag);

  // Add the 'gui' command and an option to override the default workspace.
  var command = parser.addCommand('gui');
  command.addOption('workspace', abbr: 'w', defaultsTo: defaultWorkspacePath);
  command.addOption('path', abbr: 'p', defaultsTo: defaultGuiPath);
  var results = parser.parse(args);

  // Set up logging.
  bool debugFlag = results['debug'];
  help.enableDebug(debugFlag);

  // Creating Virtual Directory
  String guiPath = results.command['path'];
  virDir = new VirtualDirectory(Platform.script.resolve(guiPath).toFilePath())
      ..allowDirectoryListing = true
      ..directoryHandler = directoryHandler
      ..followLinks = true;

  // Initialize the DirectoryWatcher.
  Directory dir = new Directory(results.command['workspace']);
  watcher = new DirectoryWatcher(dir.path);

  initServer(dir);
}
