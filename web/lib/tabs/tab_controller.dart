library tab_controller;

import 'dart:html';
import 'dart:async';

import '../mailbox.dart';
import '../container_view.dart';

part 'tab_view.dart';

abstract class TabController {
  int id, col;
  StreamController<CommanderMessage> cs;
  bool active;
  String fullName, shortName;

  TabView view;
  Mailbox mailbox;

  AnchorElement _closeTabButton;

  TabController(this.id, this.col, this.fullName, this.shortName, List menuConfig, [StreamController<CommanderMessage> cs, bool externalCss=false]) {
    if (cs == null) {
      mailbox = new Mailbox(fullName, id);
    } else {
      this.cs = cs;
      mailbox = new Mailbox(fullName, id, this.cs);
    }
    registerMailbox();

    TabView.createTabView(id, col, fullName, shortName, menuConfig, externalCss).then((tabView) {
      view = tabView;

      _closeTabButton = view.refMap['close-tab'];
      _closeTabButton.onClick.listen((e) => _closeTab());
      view.closeControlHitbox.onClick.listen((e) => _closeTab());

      setUpController();
      registerEventHandlers();
    });
  }

  void makeActive() => view.makeActive();
  void makeInactive() => view.makeInactive();

  void registerMailbox();
  void setUpController();
  void registerEventHandlers();
  Future<bool> preClose();
  void cleanUp();

  Future _closeTab() async {
    // Cancel closing if preClose returns false for some reason.
    bool canClose = await preClose();
    if (!canClose) return new Future.value(true);

    view.destroy();
    cleanUp();

    UpDroidMessage um = new UpDroidMessage('CLOSE_TAB', '${fullName}_$id');
    mailbox.ws.send(um.s);
  }

//  void _cloneTab(Event e) {
//    e.preventDefault();
//    if (cs != null) {
//      cs.add(new CommanderMessage('UPDROIDCLIENT', 'OPEN_TAB', body: '${col}_${tabType}'));
//    } else {
//      UpDroidMessage um = new UpDroidMessage('CLOSE_TAB', '${tabType}_$id');
//      mailbox.ws.send(um.s);
//    }
//  }
}