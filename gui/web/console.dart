part of client;

const String CONSOLE_HELP_TEXT =
r'''
Console only accepts commands that are non-interactive and command-line based.
For example:
  pwd, ls -ls

Programs that are curses-based, such as htop, will not work.
''';

/// [UpDroidConsole] functions like a trimmed down terminal that allows the
/// user to pass in white-listed commands to the server and view their output.
/// It is not meant to be a complete terminal emulator like xterm.
class UpDroidConsole {
  WebSocket ws;
  StreamController<CommanderMessage> cs;

  DivElement console;
  SpanElement prompt;
  TextInputElement input;
  AnchorElement consoleButton;
  AnchorElement themeButton;
  
  bool lightTheme;
  
  UpDroidConsole(WebSocket ws, StreamController<CommanderMessage> cs) {
    this.ws = ws;
    this.cs = cs;
    
    lightTheme = false;

    console = querySelector('#console');
    prompt = querySelector('#prompt');
    input = querySelector('#input');
    consoleButton = querySelector('#button-console');
    themeButton = querySelector('.button-console-theme');
    
    registerConsoleEventHandlers();
    
    // This is a hack to account for the fact that Console is set up
    // after the initial connection is made and thus, misses the first
    // message.
    updateOutputHandler('Connected to updroid.');
  }
  
  /// Toggles between a Solarized dark and light theme.
  void toggleTheme() {
    if (lightTheme) {
      console.style.backgroundColor = '#002b36'; // base-green
      querySelectorAll('.pre-output').style.color = '#93a1a1'; // light-grey
      querySelectorAll('.prompt').style.color = '#859900'; // green
      querySelectorAll('.user-command').style.color = '#268bd2';  // blue
      lightTheme = false;
    } else {
      console.style.backgroundColor = '#fdf6e3'; // base-tan
      querySelectorAll('.pre-output').style.color = '#586e75'; // dark-grey
      querySelectorAll('.prompt').style.color = '#b58900'; // yellow
      querySelectorAll('.user-command').style.color = '#dc322f';  // red
      lightTheme = true;
    }
  }
  
  /// Process messages that Console has picked up according to the type.
  void processMessage(CommanderMessage m) {
    switch (m.type) {
      case 'OUTPUT':
        updateOutputHandler(m.body);
        break;
        
      default:
        print('Console error: unrecognized message type.');
    }
  }
  
  /// Updates the output field based on string messages passed in.
  void updateOutputHandler(String s) {
    // Generate the new line.
    PreElement newLine = new PreElement();
    newLine
        ..text = s
        ..classes.add('pre-output');
    
    if (lightTheme) {
      newLine.style.color = '#586e75';
    }
    
    console.children.insert(console.children.length - 1, newLine);

    // Autoscroll the new messages as they come in.
    console.scrollTop = console.scrollHeight;
  }
  
  /// Copies the prompt and user's command and adds them to the console.
  void copyCommand(String cmd) {
    SpanElement userInput = new SpanElement();
    
    SpanElement prompt = new SpanElement();
    prompt
        ..text = '[up, droid!] '
        ..classes.add('prompt');
    
    if (lightTheme) {
      prompt.style.color = '#b58900';
    }
    
    SpanElement command = new SpanElement();
    command
        ..text = cmd
        ..classes.add('user-command');
    
    if (lightTheme) {
      command.style.color = '#dc322f';
    }
    
    userInput.children.add(prompt);
    userInput.children.add(command);
    
    console.children.insert(console.children.length - 1, userInput);
    console.children.insert(console.children.length - 1, new BRElement());
    
    // Autoscroll the new messages as they come in.
    console.scrollTop = console.scrollHeight;
  }

  /// Sets up the event handlers for the console.
  void registerConsoleEventHandlers() {
    ws.onMessage.transform(updroidTransformer)
        .where((um) => um.header == 'CONSOLE_COMMAND')
        .listen((um) => updateOutputHandler(um.body));
    
    cs.stream
        .where((m) => m.dest == 'CONSOLE')
        .listen((m) => processMessage(m));
    
    input.onChange.listen((e) {

    });
    
    input.onKeyUp.listen((e) {
      var keyEvent = new KeyEvent.wrap(e);
      if (keyEvent.keyCode == KeyCode.ENTER) {
        RegExp allWhitespace = new RegExp(r'^[\s]*$');
        if (!input.value.contains(allWhitespace)) {
          ws.send('[[CONSOLE_COMMAND]]' + input.value.trim());
        }
        copyCommand(input.value.trim());
        input.value = "";
      }
    });
    
    themeButton.onClick.listen((e) {
      toggleTheme();
      e.preventDefault();
    });
    
    consoleButton.onClick.listen((e) => input.focus());
    console.onClick.listen((e) => input.focus());
  }
}