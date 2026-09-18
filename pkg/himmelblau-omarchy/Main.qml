import QtQuick 2.0
import SddmComponents 2.0

// Omarchy's greeter with one addition: a username field. The stock theme binds
// the login to userModel.lastUser and has no way to type a name, so an Entra ID
// account (a UPN, never in the local user list) could not log in at all.
// Visual assets are symlinked to the stock theme's, so Omarchy theme changes
// carry over.

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  property bool loginFailed: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  function attemptLogin() {
    var user = root.username.text.trim()
    if (user.length === 0) {
      root.username.forceActiveFocus()
      return
    }
    sddm.login(user, root.password.text, root.sessionIndex)
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      root.password.text = ""
      root.password.forceActiveFocus()
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  component EntryBox: Item {
    id: box
    property alias input: field
    property bool masked: false
    property bool failed: false
    signal edited()
    signal accepted()
    signal tabbed()
    width: bg.width
    height: bg.height

    Component { id: emptyCursor; Item {} }

    Image {
      id: bg
      source: box.failed ? "entry-failed.png" : "entry.png"
      anchors.centerIn: parent
    }

    // Masked entries draw bullets, as the stock theme does, and keep the
    // real text transparent.
    Row {
      visible: box.masked
      anchors.left: parent.left
      anchors.leftMargin: 20
      anchors.verticalCenter: parent.verticalCenter
      spacing: 5
      Repeater {
        model: box.masked ? Math.min(field.text.length, 21) : 0
        Image { source: "bullet.png"; width: 7; height: 7 }
      }
    }

    TextInput {
      id: field
      anchors.fill: parent
      anchors.leftMargin: 20
      anchors.rightMargin: 20
      verticalAlignment: TextInput.AlignVCenter
      echoMode: box.masked ? TextInput.Password : TextInput.Normal
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: box.masked ? 24 : 20
      font.letterSpacing: box.masked ? 5 : 1
      passwordCharacter: "•"
      color: box.masked ? "transparent" : "#c0caf5"
      selectionColor: box.masked ? "transparent" : "#33467c"
      selectedTextColor: box.masked ? "transparent" : "#c0caf5"
      cursorDelegate: box.masked ? emptyCursor : null
      clip: true
      onTextChanged: box.edited()
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          box.accepted(); event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          box.tabbed(); event.accepted = true
        }
      }
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 24

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Column {
      spacing: 12
      anchors.horizontalCenter: parent.horizontalCenter

      Row {
        spacing: 15
        Item { width: 34; height: 38 }   // keeps the two boxes aligned under the lock icon
        EntryBox {
          id: usernameBox
          failed: root.loginFailed
          Component.onCompleted: input.text = userModel.lastUser
          onEdited: root.loginFailed = false
          onAccepted: root.password.forceActiveFocus()
          onTabbed: root.password.forceActiveFocus()
        }
      }

      Row {
        spacing: 15
        Image {
          source: root.loginFailed ? "lock-failed.png" : "lock.png"
          width: 34
          height: 38
          fillMode: Image.PreserveAspectFit
          anchors.verticalCenter: parent.verticalCenter
        }
        EntryBox {
          id: passwordBox
          masked: true
          failed: root.loginFailed
          onEdited: root.loginFailed = false
          onAccepted: root.attemptLogin()
          onTabbed: root.username.forceActiveFocus()
        }
      }
    }
  }

  property alias username: usernameBox.input
  property alias password: passwordBox.input

  Component.onCompleted: {
    if (root.username.text.length > 0) root.password.forceActiveFocus()
    else root.username.forceActiveFocus()
  }
}
