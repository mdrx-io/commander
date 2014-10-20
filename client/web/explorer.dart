part of client;

class UpDroidExplorer {
  WebSocket ws;
  UpDroidEditor ed;
  String absolutePathPrefix;

  ParagraphElement recycle;
  Dropzone dzRecycle;
  Dropzone dzEditor;
  
  UpDroidExplorer(WebSocket ws, UpDroidEditor ed) {
    this.ws = ws;
    this.ed = ed;
    absolutePathPrefix = '';

    dzEditor = new Dropzone(ed.editorDiv);
    
    recycle = querySelector('#recycle');
    dzRecycle = new Dropzone(recycle);
    
    registerExplorerEventHandlers();
  }
  
  registerExplorerEventHandlers() {
    dzRecycle.onDragEnter.listen((e) => recycle.classes.add('recycle-entered'));
    dzRecycle.onDragLeave.listen((e) => recycle.classes.remove('recycle-entered'));
    
    dzRecycle.onDrop.listen((e) {
      var path = e.draggableElement.dataset['path'];
      ws.send('[[EXPLORER_DELETE]]' + path);
    });
    
    // Dragging through nested dropzones appears to be glitchy
    dzEditor.onDragEnter.listen((e) {
      var isDir = e.draggableElement.dataset['isDir'];
      if (isDir == 'false') {
        ed.editorDiv.classes.add('editor-entered');
      }
    });
    
    dzEditor.onDragLeave.listen((e) => ed.editorDiv.classes.remove('editor-entered'));
    
    dzEditor.onDrop.listen((e) {
      var isDir = e.draggableElement.dataset['isDir'];
      if (isDir == 'false') {
        ed.openFile = e.draggableElement.dataset['path'];
        ws.send('[[EDITOR_OPEN]]' + ed.openFile);
      }
    });
  }
  
  /// Returns a list of file objects from the flattened string returned from
  /// the server.
  List<SimpleFile> fileList(String data) {
    var files = [];
    
    // Strip the brackets/single-quotes and split by ','.
    data = data.replaceAll(new RegExp(r"(\[|\]|')"), '');
    List<String> entities = data.split(',');
    
    // Build SimpleFile list our of raw strings.
    for (String entity in entities) {
      files.add(new SimpleFile(entity, absolutePathPrefix));
    }
    
    return files;
  }
  
  /// Returns a generated LIElement with inner HTML based on the SimpleFile's
  /// contents.
  LIElement generateLiHtml(file) {
    LIElement li = new LIElement();
    li
      ..id = file.name
      ..dataset['path'] = file.path
      ..dataset['isDir'] = file.isDirectory.toString()
      ..draggable = true
      ..classes.add('explorer-li');
    
    SpanElement span = new SpanElement();
    var glyphType = (file.isDirectory) ? 'glyphicon-folder-open' : 'glyphicon-file';
    span.classes.addAll(['glyphicon', glyphType]);
    li.children.add(span);
    
    li.appendHtml(' ${file.name}');
    
    if (file.isDirectory) {
      UListElement ul = new UListElement();
      ul
        ..id = 'explorer-ul-${file.name}'
        ..classes.addAll(['explorer', 'explorer-ul']);
      li.children.add(ul);
    }
    
    return li;
  }
  
  void syncExplorer(String data) {
    var files = fileList(data);
    
    // Set the explorer list to empty for a full refresh.
    UListElement explorer = querySelector('#explorer-top');
    explorer.innerHtml = '';

    // Generate the HTML for the File Explorer.
    for (SimpleFile file in files) {
      LIElement li = generateLiHtml(file);
      
      Draggable d = new Draggable(li, avatarHandler: new AvatarHandler.clone());
      
      // Dragging through nested dropzones appears to be glitchy
      d.onDragStart.listen((event) {
        recycle.classes.add('recycle-ondrag');
        if (!file.isDirectory) {
          ed.editorDiv.classes.add('editor-ondrag');
        }
      });
      
      d.onDragEnd.listen((event) {
        recycle.classes.remove('recycle-ondrag');
        ed.editorDiv.classes.remove('editor-ondrag');
      });
      
      UListElement dirElement = (file.parentDir == 'root') ? querySelector('#explorer-top') : querySelector('#explorer-ul-${file.parentDir}');
      dirElement.children.add(li);
    }
  }
}

class SimpleFile implements Comparable {
  String raw;
  String path;
  bool isDirectory;
  String name;
  String parentDir;
  
  SimpleFile(String raw, String prefix) {
    this.raw = raw;
    String workingString = stripFormatting(raw, prefix);
    getData(workingString);
  }
  
  @override
  int compareTo(SimpleFile other) {
    return name.compareTo(other.name);
  }
  
  String stripFormatting(String raw, String prefix) {
    raw = raw.trim();
    isDirectory = raw.startsWith('Directory: ') ? true : false;
    raw = raw.replaceFirst(new RegExp(r'(Directory: |File: )'), '');
    
    // Save the absolute path.
    path = raw;
    
    raw = raw.replaceFirst(prefix, '');
    return raw;
  }
  
  void getData(String fullPath) {
    List<String> pathList = fullPath.split('/');
    name = pathList[pathList.length - 1];
    if (pathList.length > 1) {
      parentDir = pathList[pathList.length - 2];
    } else {
      parentDir = 'root';
    }
  }
}