library panel_controller;

import 'dart:async';

import '../mailbox.dart';
import '../container_view.dart';

part 'panel_view.dart';

abstract class PanelController {
  int id, col;
  StreamController<CommanderMessage> cs;
  bool active;
  String fullName, shortName;

  PanelView view;
  Mailbox mailbox;

//  AnchorElement _closePanelButton;

  PanelController(this.id, this.col, this.fullName, this.shortName, List menuConfig, [StreamController<CommanderMessage> cs, bool externalCss=false]) {
    if (cs == null) {
      mailbox = new Mailbox(fullName, id);
    } else {
      this.cs = cs;
      mailbox = new Mailbox(fullName, id, this.cs);
    }
    registerMailbox();

    PanelView.createPanelView(id, col, fullName, shortName, menuConfig, externalCss).then((tabView) async {
      view = tabView;

//      _closePanelButton = view.refMap['close-panel'];
//      _closePanelButton.onClick.listen((e) => _closePanel());

      await setUpController();
      registerEventHandlers();
    });
  }

  void makeActive() => view.makeActive();
  void makeInactive() => view.makeInactive();

  void registerMailbox();
  void setUpController();
  void registerEventHandlers();
  void cleanUp();

//  void _closePanel() {
//    view.destroy();
//    cleanUp();
//
//    if (cs != null) {
//      cs.add(new CommanderMessage('UPDROIDCLIENT', 'CLOSE_TAB', body: '${panelType}_$id'));
//    } else {
//      UpDroidMessage um = new UpDroidMessage('CLOSE_TAB', '${panelType}_$id');
//      mailbox.ws.send(um.s);
//    }
//  }

//  void _clonePanel(Event e) {
//    e.preventDefault();
//    if (cs != null) {
//      cs.add(new CommanderMessage('UPDROIDCLIENT', 'OPEN_TAB', body: '${col}_${panelType}'));
//    } else {
//      UpDroidMessage um = new UpDroidMessage('CLOSE_TAB', '${panelType}_$id');
//      mailbox.ws.send(um.s);
//    }
//  }
}