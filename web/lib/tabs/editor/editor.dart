library updroid_editor;

import 'dart:html';
import 'dart:async';
import 'dart:convert';
import 'package:dnd/dnd.dart';

import 'package:ace/ace.dart' as ace;
import 'package:ace/proxy.dart';
import "package:path/path.dart" as pathLib;

import '../../mailbox.dart';
import '../tab_controller.dart';
import '../../modal/modal.dart';

part 'templates.dart';

/// [UpDroidEditor] is a wrapper for an embedded Ace Editor. Sets styles
/// for the editor and an additional menu bar with some filesystem operations.
class UpDroidEditor extends TabController {
  static String className = 'UpDroidEditor';

  static List getMenuConfig() {
    List menu = [
      {'title': 'File', 'items': [
        {'type': 'submenu', 'title': 'New...', 'items':
          ['Blank', 'Publisher', 'Subscriber', 'Basic Launch File']},
        {'type': 'submenu', 'title': 'Examples', 'items':
          ['Hello World Talker', 'Hello World Listener']},
        {'type': 'toggle', 'title': 'Save'},
        {'type': 'toggle', 'title': 'Save As'},
        {'type': 'toggle', 'title': 'Close Tab'}]},
      {'title': 'Settings', 'items': [
        {'type': 'toggle', 'title': 'Invert'},
        {'type': 'input', 'title': 'Font Size'}]}
    ];
    return menu;
  }

  Map _pathMap;
  String _absolutePathPrefix;

  AnchorElement _blankButton;
  AnchorElement _launchButton;
  AnchorElement _talkerButton;
  AnchorElement _listenerButton;
  AnchorElement _pubButton;
  AnchorElement _subButton;
  AnchorElement _saveButton;
  AnchorElement _saveAsButton;
  AnchorElement _themeButton;
  InputElement _fontSizeInput;

  Element _saveCommit;
  ButtonElement _modalSaveButton;
  ButtonElement _modalDiscardButton;
  Element _warning;
  Element _overwriteCommit;
  DivElement _explorersDiv;
  var _curModal;
  int _fontSize = 12;

  // Stream Subscriptions.
  StreamSubscription _saveAsClickEnd;
  StreamSubscription _saveAsEnterEnd;
  StreamSubscription _unsavedSave;
  StreamSubscription _unsavedDiscard;
  StreamSubscription _overwrite;
  StreamSubscription _fontInputListener;
  StreamSubscription _fileChangesListener;

  ace.Editor _aceEditor;
  String _openFilePath;
  String _originalContents;
  String _currentParPath;
  bool _exec;

  UpDroidEditor(int id, int col, StreamController<CommanderMessage> cs) :
  super(id, col, className, 'Editor', getMenuConfig(), cs, true) {

  }

  void setUpController() {
    _blankButton = view.refMap['blank-button'];
    _pubButton = view.refMap['publisher-button'];
    _subButton = view.refMap['subscriber-button'];
    _launchButton = view.refMap['basic-launch-file-button'];
    _talkerButton = view.refMap['hello-world-talker-button'];
    _listenerButton = view.refMap['hello-world-listener-button'];
    _saveButton = view.refMap['save'];
    _saveAsButton = view.refMap['save-as'];
    _themeButton = view.refMap['invert'];
    _fontSizeInput = view.refMap['font-size'];
    _explorersDiv = querySelector('#exp-container');


    _fontSizeInput.placeholder = _fontSize.toString();

    _setUpEditor();
//    cs.add(new CommanderMessage('UPDROIDEXPLORER', 'EDITOR_READY', body: [id, view.content]));
  }

  /// Sets up the editor and styles.
  void _setUpEditor() {
    ace.implementation = ACE_PROXY_IMPLEMENTATION;
    ace.BindKey ctrlS = new ace.BindKey(win: "Ctrl-S", mac: "Command-S");
    ace.Command save = new ace.Command('save', ctrlS, sendSave);

    DivElement aceDiv = new DivElement()
    // Necessary to allow our styling (in main.css) to override Ace's.
    ..classes.add('updroid_editor');
    view.content.children.add(aceDiv);

    _aceEditor = ace.edit(aceDiv)
    ..session.mode = new ace.Mode.named(ace.Mode.PYTHON)
    ..fontSize = _fontSize
    ..theme = new ace.Theme.named(ace.Theme.SOLARIZED_DARK)
    ..commands.addCommand(save);

    _resetSavePoint();

    // Create listener to indicate that there are unsaved changes when file is altered
    // TODO: should this listener be cancelled at some point? If not, remove var.
    _fileChangesListener = _aceEditor.onChange.listen((e) {
      if (_openFilePath != null && _noUnsavedChanges() == false) view.extra.text = pathLib.basename(_openFilePath) + '*';
    });
  }

  void registerMailbox() {
    mailbox.registerCommanderEvent('CLASS_ADD', _classAddHandler);
    mailbox.registerCommanderEvent('CLASS_REMOVE', _classRemoveHandler);
    mailbox.registerCommanderEvent('OPEN_FILE', _openFileHandler);
    mailbox.registerCommanderEvent('PARENT_PATH', _currentPathHandler);
    mailbox.registerCommanderEvent('RESEND_DROP', _resendDrop);
    mailbox.registerCommanderEvent('FILE_UPDATE', _editorRenameHandler);

    mailbox.registerWebSocketEvent(EventType.ON_MESSAGE, 'PATH_LIST', _pathListHandler);
    mailbox.registerWebSocketEvent(EventType.ON_MESSAGE, 'EDITOR_DIRECTORY_PATH', _editorDirPathHandler);
    mailbox.registerWebSocketEvent(EventType.ON_MESSAGE, 'EDITOR_FILE_TEXT', _editorFileTextHandler);
    mailbox.registerWebSocketEvent(EventType.ON_MESSAGE, 'NO_CURRENT_WORKSPACE', _noCurrentWorkspaceAlert);
  }

  /// Sets up event handlers for the editor's menu buttons.
  void registerEventHandlers() {
    _blankButton.onClick.listen((e) => _handleNewFileButton(e, ''));
    _talkerButton.onClick.listen((e) => _handleNewFileButton(e, RosTemplates.talkerTemplate));
    _listenerButton.onClick.listen((e) => _handleNewFileButton(e, RosTemplates.listenerTemplate));
    _launchButton.onClick.listen((e) => _handleNewFileButton(e, RosTemplates.launchTemplate));
    _pubButton.onClick.listen((e) => _handleNewFileButton(e, RosTemplates.pubTemplate));
    _subButton.onClick.listen((e) => _handleNewFileButton(e, RosTemplates.subTemplate));

    _saveButton.onClick.listen((e) => _saveText());

    /// Save as click handler
    _saveAsButton.onClick.listen((e) {
      _exec = false;
      cs.add(new CommanderMessage('EXPLORER', 'REQUEST_PARENT_PATH'));
      mailbox.ws.send("[[EDITOR_REQUEST_LIST]]");
    });

    _themeButton.onClick.listen((e) => _updateTheme(e));
    _fontSizeInput.onClick.listen((e) => _updateFontSize(e));
  }

  void _updateTheme(Event e) {
    // Stops the button from sending the page to the top (href=#).
    e.preventDefault();

    bool dark = _aceEditor.theme.name == 'solarized_dark';
    String newTheme = dark ? ace.Theme.SOLARIZED_LIGHT : ace.Theme.SOLARIZED_DARK;
    _aceEditor.theme = new ace.Theme.named(newTheme);
  }

  void _updateFontSize(Event e) {
    // Keeps bootjack dropdown from closing
    e.stopPropagation();

    _fontInputListener = _fontSizeInput.onKeyUp.listen((e) {
      if (e.keyCode != KeyCode.ENTER) return;

      var fontVal;
      try {
        fontVal = int.parse(_fontSizeInput.value);
        assert(fontVal is int);
        if(fontVal >= 1 && fontVal <= 60){
          _aceEditor.fontSize = fontVal;
          _fontSizeInput.placeholder = fontVal.toString();
        }
      }
      finally {
        _fontSizeInput.value = "";
        _aceEditor.focus();
        _fontInputListener.cancel();
      }
    });
  }

  void sendSave(d) {
    _saveButton.click();
  }

  //\/\/ Mailbox Handlers /\/\//

  bool _classAddHandler(CommanderMessage m) => view.content.classes.add(m.body);
  bool _classRemoveHandler(CommanderMessage m) => view.content.classes.remove(m.body);
  void _currentPathHandler(CommanderMessage m) => _currentParPath = m.body;

  void _openFileHandler(CommanderMessage m) {
    if (id != m.body[0]) return;
    mailbox.ws.send('[[EDITOR_OPEN]]' + m.body[1]);
    if (pathLib.basename(m.body[1]) == 'CMakeLists.txt'){
      view.extra.text = pathLib.basename(m.body[1]) + ' (Read Only)';
      _aceEditor.setOptions({'readOnly': true});
    }
    else {
      view.extra.text = pathLib.basename(m.body[1]);
      _aceEditor.setOptions({'readOnly': false});
    }
  }

  void _pathListHandler(UpDroidMessage um) => _pullPaths(um.body);
  void _editorDirPathHandler(UpDroidMessage um) { _absolutePathPrefix = um.body; }

  // Editor receives the open file contents from the server.
  void _editorFileTextHandler(UpDroidMessage um) {
    var returnedData = um.body.split('[[CONTENTS]]');
    var newPath = returnedData[0];
    var newText = returnedData[1];
    _handleNewText(newPath, newText);
  }

  void _noCurrentWorkspaceAlert(UpDroidMessage um) {
    window.alert("No workspace set. Please open one from Explorer.");
  }

  void _editorRenameHandler(CommanderMessage m) {
    if (_openFilePath != null) {
      if (_openFilePath == m.body[0]) {
        _openFilePath = m.body[1];
        view.extra.text = pathLib.basename(m.body[1]);
      }
    }
  }

  void _resendDrop(CommanderMessage m) {
    cs.add(new CommanderMessage('EXPLORER', 'EDITOR_READY', body: [id, view.content]));
  }

  void _saveFile() {
    if (_curModal != null) _curModal.hide();

    String saveAsPath = '';
    _curModal = new UpDroidSavedModal();

    //TODO: remove query selectors
    InputElement input = querySelector('#save-as-input');
    CheckboxInputElement makeExec = querySelector('#make-exec');
    _saveCommit = querySelector('#save-as-commit');
    _overwriteCommit = querySelector('#warning button');
    _warning = querySelector('#warning');

    // Check to make sure that the supplied input doesn't conflict with existing files
    // on system.  Also determines what action to take depending on whether the file exists or not.



    _saveAsClickEnd = _saveCommit.onClick.listen((e) {
      if (makeExec.checked == true) _exec = true;
      _checkSave(input, saveAsPath);
    });

    _saveAsEnterEnd = input.onKeyUp.listen((e) {
      if (e.keyCode != KeyCode.ENTER) return;

      if (makeExec.checked == true) _exec = true;
      _checkSave(input, saveAsPath);
    });
  }

  void _completeSave(InputElement input, String saveAsPath) {
    mailbox.ws.send('[[EDITOR_SAVE]]' + JSON.encode([_aceEditor.value, saveAsPath, _exec]));

    view.extra.text = input.value;
    _curModal.hide();
    input.value = '';
    _resetSavePoint();
    _saveAsClickEnd.cancel();
    _saveAsEnterEnd.cancel();
    _openFilePath = saveAsPath;
  }

  void _checkSave(InputElement input, String saveAsPath) {
    // User enters no input
    if (input.value == '') window.alert("Please enter a valid filename");

    // Determining the save path
    if (_openFilePath == null) {
      if(_currentParPath == null) {
        var activeFolderName = _checkActiveExplorer();
        saveAsPath = pathLib.normalize(pathLib.normalize(_absolutePathPrefix + '/' + activeFolderName +'/src') + "/${input.value}");
      } else{
        saveAsPath = pathLib.normalize(_currentParPath + "/${input.value}");
      }
    }
    else {
      if(_currentParPath == null) saveAsPath = pathLib.dirname(_openFilePath)+  "/${input.value}";
      else {
        saveAsPath = pathLib.normalize(_currentParPath + "/${input.value}");
      }
    }

    // Filename already exists on system
    if (_pathMap.containsKey(saveAsPath)) {
      if (_pathMap[saveAsPath] == 'directory') {
        window.alert("That filename already exists as a directory");
        input.value = "";
      } else if (_pathMap[saveAsPath] == 'file') {
        _warning.classes.remove('hidden');
        _overwrite = _overwriteCommit.onClick.listen((e){
          _completeSave(input, saveAsPath);
          _warning.classes.add('hidden');
          _overwrite.cancel();
        });
      }
    }

    // Filename clear, continue with save
    else {
      _completeSave(input, saveAsPath);
    }
  }

  void _handleNewFileButton(Event e, String text) {
    e.preventDefault();

    _aceEditor.setOptions({'readOnly' : false});
    _openFilePath = null;

    if (_noUnsavedChanges()) {
      _aceEditor.setValue(text, 1);
      view.extra.text = "untitled*";
      _aceEditor.focus();
      return;
    }

    new UpDroidUnsavedModal();

    // TODO: refine this case
    _modalSaveButton = querySelector('.modal-save');
    _modalDiscardButton = querySelector('.modal-discard');

    _unsavedSave = _modalSaveButton.onClick.listen((e) {
      _saveText();
      _aceEditor.setValue(text, 1);
      view.extra.text = "untitled*";
      _unsavedSave.cancel();
    });

    _unsavedDiscard = _modalDiscardButton.onClick.listen((e) {
      _aceEditor.setValue(text, 1);
      view.extra.text = "untitled*";
      _unsavedDiscard.cancel();
    });
  }

  /// Handles changes to the Editor model, new files and opening files.
  void _handleNewText(String newPath, String newText) {
    if (_noUnsavedChanges()) {
      _setEditorText(newPath, newText);
      return;
    }

    new UpDroidUnsavedModal();
    _modalSaveButton = querySelector('.modal-save');
    _modalDiscardButton = querySelector('.modal-discard');

    _unsavedSave = _modalSaveButton.onClick.listen((e) {
      _saveText();
      _setEditorText(newPath, newText);
      _unsavedSave.cancel();
    });
    _unsavedDiscard = _modalDiscardButton.onClick.listen((e) {
      _setEditorText(newPath, newText);
      _unsavedDiscard.cancel();
    });
  }

  /// Sets the Editor's text with [newText], updates [_openFilePath], and resets the save point.
  void _setEditorText(String newPath, String newText) {
    view.extra.text = newPath.split('/').last;
    _openFilePath = newPath;
    _aceEditor.setValue(newText, 1);
    _resetSavePoint();

    // Set focus to the interactive area so the user can typing immediately.
    _aceEditor.focus();
    _aceEditor.scrollToLine(0);
  }

  /// parses through DOM to get the current active explorer
  String _checkActiveExplorer() {
    String activeName;
    for (var explorer in _explorersDiv.children) {
      if (explorer.id != 'recycle' && !explorer.classes.contains('control-buttons')) {
        if (!explorer.classes.contains('hidden')) {
          activeName = explorer.dataset['name'];
        }
      }
    }
    return activeName;
  }

  /// Sends the file path and contents to the server to be saved to disk.
  void _saveText() {
    if (_openFilePath == null) {
      _saveAsButton.click();
      return;
    }

    if (pathLib.basename(_openFilePath) != 'CMakeLists.txt') {
      mailbox.ws.send('[[EDITOR_SAVE]]' + JSON.encode([_aceEditor.value, _openFilePath, false]));
      _resetSavePoint();
      view.extra.text = pathLib.basename(_openFilePath);
    }
  }

  void _pullPaths(String raw) {
    raw = raw.replaceAll(new RegExp(r"(\[|\]|')"), '');
    List<String> pathList = raw.split(',');
    _pathMap = new Map.fromIterable(pathList,
    key: (item) => item.replaceAll(new RegExp(r"(Directory: | File: |Directory: |File:)"), '').trim(),
    value: (item) => item.contains("Directory:") ? "directory" : "file"
    );

    _saveFile();
  }

  /// Compares the Editor's current text with text at the last save point.
  bool _noUnsavedChanges() => _aceEditor.value == _originalContents;

  /// Resets the save point based on the Editor's current text.
  String _resetSavePoint() => _originalContents = _aceEditor.value;

  Future<bool> preClose() async {
    Completer c = new Completer();

    if (_noUnsavedChanges()) {
      c.complete(true);
    } else {
      new UpDroidUnsavedModal();

      _modalSaveButton = querySelector('.modal-save');
      _modalDiscardButton = querySelector('.modal-discard');

      _unsavedSave = _modalSaveButton.onClick.listen((e) {
        _saveText();
        _unsavedSave.cancel();
        c.complete(true);
      });

      _unsavedDiscard = _modalDiscardButton.onClick.listen((e) {
        _unsavedDiscard.cancel();
        c.complete(true);
      });
    }

    return c.future;
  }

  void cleanUp() {

  }
}