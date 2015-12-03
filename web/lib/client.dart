library updroid_client;

import 'dart:async';
import 'dart:html';
import 'dart:convert';

import 'package:upcom-api/web/mailbox/mailbox.dart';
import 'package:quiver/async.dart';

import 'column_controller.dart';
import 'panel_column_controller.dart';
import 'tab_column_controller.dart';
import 'panel_interface.dart';
import 'tab_interface.dart';

class UpDroidClient {
  static const String upcomName = 'upcom';
  static const String explorerRefName = 'upcom-explorer';

  List _config;
  List<PanelColumnController> _panelColumnControllers;
  List<TabColumnController> _tabColumnControllers;
  Map _panelsInfo, _tabsInfo;
  Completer _gotConfig, _gotPluginsInfo;

  bool disconnectAlert = false;

  Mailbox _mailbox;

  UpDroidClient() {
    _gotConfig = new Completer();
    _gotPluginsInfo = new Completer();
    FutureGroup readyForInitialization = new FutureGroup();
    readyForInitialization.add(_gotConfig.future);
    readyForInitialization.add(_gotPluginsInfo.future);

    // TODO: figure out how to handle panels along with the logo.
    _panelColumnControllers = [];
    _tabColumnControllers = [];

    _mailbox = new Mailbox(upcomName, 1);

    _registerMailbox();
    _registerEventHandlers();

    readyForInitialization.future.then((_) => _initializeClient());
  }

  void _registerMailbox() {
    _mailbox.registerWebSocketEvent(EventType.ON_OPEN, 'MAKE_REQUESTS', _makeInitialRequests);
    _mailbox.registerWebSocketEvent(EventType.ON_MESSAGE, 'PLUGINS_INFO', _refreshTabsInfo);
    _mailbox.registerWebSocketEvent(EventType.ON_MESSAGE, 'SERVER_READY', _setUpConfig);
    _mailbox.registerWebSocketEvent(EventType.ON_MESSAGE, 'REQUEST_TAB', _requestTabFromServer);
    _mailbox.registerWebSocketEvent(EventType.ON_MESSAGE, 'CLOSE_TAB', _closeTabFromServer);
    _mailbox.registerWebSocketEvent(EventType.ON_MESSAGE, 'CLONE_TAB', _cloneTabFromServer);
    _mailbox.registerWebSocketEvent(EventType.ON_MESSAGE, 'MOVE_TAB', _moveTabFromServer);
    _mailbox.registerWebSocketEvent(EventType.ON_MESSAGE, 'ISSUE_ALERT', _issueAlert);
    _mailbox.registerWebSocketEvent(EventType.ON_CLOSE, 'CLEAN_UP', _cleanUp);
  }

  /// Sets up external event handlers for the various Commander classes. These
  /// are mostly listening events for [WebSocket] messages.
  void _registerEventHandlers() {

  }

  //\/\/ Mailbox Handlers /\/\//

  void _makeInitialRequests(Msg um) {
    _mailbox.ws.send('[[REQUEST_PLUGINSINFO]]');
    _mailbox.ws.send('[[CLIENT_CONFIG]]');
  }

  void _setUpConfig(Msg um) {
    _config = JSON.decode(um.body);
    _gotConfig.complete();
  }

  void _refreshTabsInfo(Msg um) {
    Map pluginsInfo = JSON.decode(um.body);
    _panelsInfo = pluginsInfo['panels'];
    _tabsInfo = pluginsInfo['tabs'];
    _gotPluginsInfo.complete();
  }

  void _requestTabFromServer(Msg um) {
    int tabId = _getAvailableId(um.body);

    for (TabColumnController controller in _tabColumnControllers) {
      if (controller.canAddMoreTabs) {
        controller.openTab(tabId, _tabsInfo[um.body], true);
        break;
      }
    }
  }

  void _closeTabFromServer(Msg um) {
    String id = um.body;
    List idList = id.split(':');
    String refName = idList[0];
    int tabId = int.parse(idList[1]);

    for (TabColumnController controller in _tabColumnControllers) {
      // Break once one of the controllers finds the tab to close.
      if (controller.findAndCloseTab(tabId, refName)) break;
    }
  }

  void _cloneTabFromServer(Msg um) {
    String id = um.body;
    List idList = id.split(':');
    String refName = idList[0];
    int col = int.parse(idList[2]);

    _tabsInfo.keys.forEach((String key) {
      if (_tabsInfo[key].containsValue(refName)) {
        int id = _getAvailableId(_tabsInfo[key]);
        _tabColumnControllers[col == 1 ? 0 : 1].openTab(id, _tabsInfo[key]);
      }
    });
  }

  void _moveTabFromServer(Msg um) {
    List idList = um.body.split(':');
    String refName = idList[0];
    int id = int.parse(idList[1]);

    // Working with indexes here, not the columnId.
    int oldColIndex = int.parse(idList[2]) - 1;
    int newColIndex = int.parse(idList[3]) - 1;

    // Don't go any further if a move request can't be done.
    if (!_tabColumnControllers[newColIndex].canAddMoreTabs) {
      window.alert('Can\'t move tab. Already at max on this side.');
      return;
    }

    TabInterface tab = _tabColumnControllers[oldColIndex].removeTab(refName, id);
    _tabColumnControllers[newColIndex].addTab(tab);
  }

  void _issueAlert(Msg m) => window.alert(m.body);

  void _cleanUp(Msg m) {
    _panelColumnControllers.forEach((controller) => controller.cleanUp());
    _tabColumnControllers.forEach((controller) => controller.cleanUp());

    String alertMessage = 'UpDroid Commander has lost connection to the server.';
    alertMessage = alertMessage + ' Please restart the server (if necessary) and refresh the page.';
    window.alert(alertMessage);
  }

  //\/\/ Event Handlers /\/\/

  //\/\/ Misc Functions /\/\//

  /// Initializes all classes based on the loaded configuration in [_config].
  /// TODO: use isolates.
  void _initializeClient() {
    PanelColumnController controller = new PanelColumnController(0, _config[0], _mailbox, _panelsInfo, _getAvailableId);
    _panelColumnControllers.add(controller);

    controller.columnEvents.listen((ColumnEvent event) {
      if (event == ColumnEvent.LOST_FOCUS) {
        _panelColumnControllers.firstWhere((c) => c != controller).getsFocus();
      }
    });

    String userAgent = window.navigator.userAgent;
    if (userAgent.contains('Mobile')) {
      querySelectorAll('html,body,#column-0,#col-0-tab-content,.footer,.text-muted')
        .forEach((e) => e.classes.add('mobile'));
      window.scrollTo(0, 1);
      return;
    }

    // TODO: make the initial min-width more responsive to how the tabs start out initially.
    // For now we assume they start off 50/50.
    querySelector('body').style.minWidth = '1211px';

    for (int i = 1; i < _config.length; i++) {
      // Start the Client with Column 1 maximized by default.
      ColumnState defaultState = i == 1 ? ColumnState.MAXIMIZED : ColumnState.MINIMIZED;

      TabColumnController controller = new TabColumnController(i, defaultState, _config[i], _mailbox, _tabsInfo, _getAvailableId);
      _tabColumnControllers.add(controller);

      controller.columnStateChanges.listen((ColumnState newState) {
        if (newState == ColumnState.MAXIMIZED) {
          querySelector('body').style.minWidth = '770px';
          _tabColumnControllers.where((c) => c != controller).forEach((c) => c.minimize(false));
        } else if (newState == ColumnState.MINIMIZED) {
          querySelector('body').style.minWidth = '770px';
          _tabColumnControllers.where((c) => c != controller).forEach((c) => c.maximize(false));
        } else {
          querySelector('body').style.minWidth = '1211px';
          _tabColumnControllers.where((c) => c != controller).forEach((c) => c.resetToNormal(false));
        }
      });

      controller.columnEvents.listen((ColumnEvent event) {
        if (event == ColumnEvent.LOST_FOCUS) {
          _tabColumnControllers.firstWhere((c) => c != controller).getsFocus();
        }
      });
    }
  }

  int _getAvailableId(String className) {
    List ids = [];

    // Add all used ids for [className] to ids.
    _tabColumnControllers.forEach((controller) {
      ids.addAll(controller.returnIds(className));
    });

    // Find the lowest unused ID possible.
    int id = 0;
    bool found = false;
    while (!found) {
      id++;
      if (!ids.contains(id)) break;
    }

    return id;
  }
}
