import QtQuick

// The real catcher turns key events into these; a test raises them directly,
// which is the seam that lets the panel's key handling be exercised at all.
Item {
    property bool blocked: false

    signal moveRequested(int dx, int dy)
    signal activateRequested
    signal returnRequested
    signal closeRequested
    signal deleteRequested
    signal tabRequested(int direction)
    signal textKey(string text)
}
