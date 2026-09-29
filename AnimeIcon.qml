import QtQuick
import qs.Commons

Text {
    id: root

    property real iconSize: Style.bar.iconFont
    property bool playing: false

    readonly property string playingGlyph: "󰐊"
    readonly property string pausedGlyph: "󰝴"

    text: playing ? playingGlyph : pausedGlyph
    color: Color.foreground
    font.family: Style.font.family
    font.pixelSize: iconSize
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
}
