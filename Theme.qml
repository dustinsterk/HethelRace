import QtQuick 2.3

// Design tokens for the settings menu (from the AgeSolo dash, MIT license — see
// LICENSE-AgeSolo-menu.txt). The palette is writable here so SettingsMenu can
// feed it from the dash's current theme.
QtObject {
    // palette
    property color white:    "#ffffff"   // text + box borders
    property color black:    "#000000"
    property color boxFill:  "#474747"
    property color panel:    "#0a1712"   // opaque backing of the option column
    property color yellow:   "#ffd400"   // header mark + rules
    property color textDim:  "#9a9a9a"   // "pinned" group fill
    property color boxEdge:  "#CFCFCF"   // arrow square

    // boxes
    readonly property int borderW: 2
    readonly property int boxH:    30
    readonly property int gap:     3

    // layout
    readonly property int pad:   14
    readonly property int headH: 64
    readonly property int footH: 36
    readonly property int catW:  160              // group column
    readonly property int flyW:  236              // option column

    // motion
    readonly property int pulseMs: 700            // one white->black fade
    readonly property int slideMs: 220
    readonly property int stagger: 50
}
