library tab_interface;

import 'dart:async';
import 'dart:io';

import 'tab/api/tab.dart';
import 'tab/pty.dart';
import 'tab/camera/camera.dart';
import 'tab/teleop.dart';
import 'tab/editor.dart';

class TabInterface {
  String tabType;
  int id;
  Directory dir;
  List extra;

  Tab tab;
  Stream<String> input;
  Stream<String> output;

  StreamController<String> _inputController;
  StreamController<String> _outputController;

  TabInterface(this.tabType, this.id, this.dir, [this.extra]) {
    _inputController = new StreamController<String>();
    input = _inputController.stream;

    _outputController = new StreamController<String>();
    output = _outputController.stream;

    _spawnTab();
  }

  void _spawnTab() {
    switch (tabType) {
      case 'updroideditor':
        tab = new CmdrEditor(id, dir);
        break;
      case 'updroidcamera':
        tab = new CmdrCamera(id, dir);
        break;
      case 'updroidteleop':
        tab = new CmdrTeleop(id, dir);
        break;
      case 'updroidconsole':
        String idRows = extra[0];
        String idCols = extra[1];
        tab = new CmdrPty(id, dir.path, idRows, idCols);
        break;
    }
  }

  void close() {
    tab.cleanup();
  }
}