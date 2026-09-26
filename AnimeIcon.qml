import QtQuick
import qs.Commons

// Literal glyphs, not \u escapes: these codepoints are above U+FFFF and a
// four-digit \u cannot reach them.
Text {
    id: root

    property real iconSize: Style.bar.iconFont
    property bool playing: false

    text: playing ? "󰐊" : "󰝴"
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: iconSize
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
}
