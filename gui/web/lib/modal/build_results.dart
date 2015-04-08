part of updroid_modal;

class UpDroidBuildResultsModal extends UpDroidModal {
  UpDroidBuildResultsModal (String results) {
    _buttonListeners = [];

    _createModal();
    _setupModal(results);

    _modal = new Modal(querySelector('.modal-base'));
    _modal.show();
  }

  void _setupModal(String results) {
    _modalBase.id = "build-results";

    var closer = _createClose();
    _buttonListeners.add(closer.onClick.listen((e) {
      _destroyModal();
    }));
    var h3 = new Element.tag('h3');
    h3.text = ('Build Results');
    _modalHead.children.insert(0, closer);
    _modalHead.children.insert(1, h3);

    var p = new Element.p();
    if (results == '') {
      p.text = 'Success!';
      _modalBody.children.add(p);
    } else {
      p.text = 'Your build was unsuccessful:\n\n';
      _modalBody.children.add(p);
      PreElement pre = new PreElement()
        ..text = results;
      _modalBody.children.add(pre);
    }

    var okay = _createButton('okay');
    _buttonListeners.add(okay.onClick.listen((e) {
      _destroyModal();
    }));
    _modalFooter.children.insert(0, okay);
  }
}