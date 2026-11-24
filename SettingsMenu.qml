import QtQuick 2.3

// Two-level settings menu: groups on the left, that group's options on the right.
// From the AgeSolo dash (MIT license — see LICENSE-AgeSolo-menu.txt), adapted for
// HethelRace:
//   * the schema comes from the dash (`schema`), and each row is just a key +
//     label. Values are read / changed through the dash's own functions, so all
//     its unit handling and limits stay in one place:
//         target.valueText(k)      text shown for the row
//         target.applyKey(k, dir)  change it (dir = +1 / -1)
//         target.rowHidden(k)      row currently not applicable -> not listed
//         target.isRampable(k)     numeric row -> repeats while held
//         target.settingsRev       bumped by the dash on every change
//   * the option column scrolls when a group has more rows than fit
//   * colors come from the dash's theme (c* properties)
//
//   open   : slide in / out.
//
// Button grammar: left/right MOVE, up/down ACT.
//   move(+1/-1)   next / previous box in the active column
//   press(+1/-1)  on a group: open it (or Save & exit)
//                 on "Back": return to the groups
//                 on an option: change its value (numbers repeat until release())
//   release()     stop auto-repeat
Item {
    id: menu

    property var    target
    property bool   open: false
    property int    level: 0              // 0 = choosing a group, 1 = inside a group
    property int    cat: 0                // selected group
    property int    row: 1                // selected box in the option list (0 = Back)
    property int    firstRow: 0                // first option box in view (scroll position)
    property real   spin: 0               // header X rotation
    property real   pulse: 1              // 1 = white, 0 = black (shared by all boxes)
    property string labelFont: ""
    property string valueFont: ""
    property string title: "Settings"
    property var    schema: []

    // palette, fed by the dash
    property color cText:   "#ffffff"
    property color cBox:    "#474747"
    property color cPanel:  "#0a1712"
    property color cPinned: "#9a9a9a"
    property color cAccent: "#ffd400"

    readonly property int maxRows: 9      // option boxes that fit under the header

    // Key of the value being edited, or "" when closed / browsing groups.
    readonly property string focusKey: (open && curRow) ? curRow.k : ""

    signal exitRequested()

    width: th.pad + th.catW + th.pad + th.flyW + th.pad
    height: 480

    Theme { id: th; white: menu.cText; boxFill: menu.cBox; panel: menu.cPanel; textDim: menu.cPinned; yellow: menu.cAccent }

    readonly property var curCat: schema[cat]
    // option boxes of the current group: Back + every row that is not hidden.
    // Rebuilt only when the set of visible rows changes, so changing a value does
    // not re-create (and re-animate) the boxes.
    property var    rows: []
    property string rowsKey: ""
    readonly property var curRow: (level === 1 && row > 0 && row < rows.length) ? rows[row] : null

    function refreshRows() {
        var out = [{ label: "Back", back: true }], key = String(cat) + ":";
        var c = schema[cat];
        if (c && c.rows && target) {
            for (var i = 0; i < c.rows.length; i++) {
                if (target.rowHidden(c.rows[i].k)) continue;
                out.push(c.rows[i]); key += c.rows[i].k + ",";
            }
        }
        if (key === rowsKey) return;
        rowsKey = key; rows = out;
        if (row > out.length - 1) row = out.length - 1;
        keepInView();
    }
    function keepInView() {
        if (row < firstRow) firstRow = row;
        else if (row >= firstRow + maxRows) firstRow = row - maxRows + 1;
        if (firstRow > Math.max(0, rows.length - maxRows)) firstRow = Math.max(0, rows.length - maxRows);
    }
    onCatChanged: { firstRow = 0; refreshRows(); }
    onSchemaChanged: { rowsKey = ""; refreshRows(); }

    // ------------------------------------------------------------------
    // Logic
    // ------------------------------------------------------------------
    function format(r) {
        var rev = target ? target.settingsRev : 0;      // dependency: refresh on change
        return (r && r.k && target) ? target.valueText(r.k) : "";
    }

    function adjust(dir) {
        var r = curRow;
        if (!r || !target) return;
        target.applyKey(r.k, dir);
        refreshRows();                               // a toggle can show / hide other rows
    }

    function bump() {                               // visual feedback on any navigation
        spin += 90;
        pulse = 1;                                  // new selection always starts white
        pulseAnim.restart();
    }

    function move(dir) {
        repeater.stop();
        if (level === 0) {
            cat = (cat + dir + schema.length) % schema.length;
        } else {
            var n = rows.length;
            row = (row + dir + n) % n;
            keepInView();
        }
        bump();
    }

    function press(dir) {
        if (level === 0) {
            if (curCat.action) { exitRequested(); return; }
            level = 1; row = 1; firstRow = 0;
            refreshRows();
            bump();
            return;
        }
        if (row === 0) { level = 0; bump(); return; }   // Back
        adjust(dir);
        if (curRow && target.isRampable(curRow.k)) {      // hold to repeat; toggles step once
            repeater.dir = dir;
            repeater.interval = 350;
            repeater.restart();
        }
    }

    function release() { repeater.stop(); }

    onOpenChanged: {
        repeater.stop();
        if (open) {
            level = 0; firstRow = 0;
            rowsKey = ""; refreshRows();
            pulse = 1;
            pulseAnim.restart();
        } else {
            pulseAnim.stop();
        }
    }

    Timer {
        id: repeater
        property int dir: 1
        repeat: true
        interval: 350                               // initial hold delay, then fast
        onTriggered: { menu.adjust(dir); interval = 80; }
    }

    SequentialAnimation {
        id: pulseAnim
        loops: Animation.Infinite
        NumberAnimation { target: menu; property: "pulse"; to: 0;  duration: th.pulseMs; easing.type: Easing.InOutSine }
        NumberAnimation { target: menu; property: "pulse"; to: .4; duration: th.pulseMs; easing.type: Easing.InOutSine }
    }

    // ------------------------------------------------------------------
    // Header
    // ------------------------------------------------------------------
    Item {
        id: head
        width: menu.width
        height: th.headH
        x: menu.open ? 0 : -width
        Behavior on x { NumberAnimation { duration: th.slideMs; easing.type: Easing.OutCubic } }

        Item {
            x: 18; y: 18
            width: 28; height: 28
            rotation: menu.spin
            Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
            Rectangle { anchors.centerIn: parent; width: 36; height: 6; rotation: 45;  color: th.yellow }
            Rectangle { anchors.centerIn: parent; width: 36; height: 6; rotation: -45; color: th.yellow }
        }

        Text {
            x: 64
            anchors.verticalCenter: parent.verticalCenter
            text: menu.title
            color: th.white
            font.pixelSize: 28
            font.bold: true
            font.family: menu.labelFont
        }

        Text {                                      // breadcrumb while inside a group
            anchors.right: parent.right
            anchors.rightMargin: th.pad
            anchors.verticalCenter: parent.verticalCenter
            text: (menu.level === 1 && menu.curCat) ? menu.curCat.name : ""
            color: th.white
            font.pixelSize: 20
            font.bold: true
            font.family: menu.labelFont
        }

        Rectangle { y: parent.height - 3; width: menu.width; height: 3; color: th.yellow }
    }

    // ------------------------------------------------------------------
    // Group column (always fully visible, no scrolling)
    // ------------------------------------------------------------------
    Column {
        id: catCol
        y: th.headH + 10
        width: th.catW
        spacing: th.gap
        x: th.pad

        Repeater {
            model: menu.schema
            SettingBox {
                expand: true
                fullWidth: th.catW
                theme: th
                label: modelData.name
                selected: menu.level === 0 && index === menu.cat
                pinned:   menu.level === 1 && index === menu.cat
                pulse: menu.pulse
                shown: menu.open
                order: index
                labelFont: menu.labelFont
                glyph: modelData.glyph !== undefined ? modelData.glyph : "→"
            }
        }
    }

    // ------------------------------------------------------------------
    // Option column: the selected group's options, shown once inside the group.
    // At most maxRows boxes are in view; the list scrolls to follow the selection.
    // ------------------------------------------------------------------
    Item {
        id: fly
        readonly property int count: menu.rows.length
        readonly property int vis: Math.min(count, menu.maxRows)
        readonly property bool shown: menu.open && menu.level === 1 && menu.curCat && !menu.curCat.action

        z: -1                                       // tucks behind the group column
        width: th.flyW
        height: vis * th.boxH + (vis - 1) * th.gap

        x: shown ? th.pad + th.catW + th.pad : th.pad + th.catW - 40
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        visible: opacity > 0

        // level with its group, but never runs off the bottom
        y: Math.min(catCol.y + menu.cat * (th.boxH + th.gap),
                    menu.height - th.footH - 8 - height)
        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Rectangle {                                 // solid backing: nothing shows through
            x: -6; y: -6
            width: fly.width + 12
            height: fly.height + 12
            z: -1
            color: th.panel
            border.width: 1
            border.color: th.boxFill
        }
        Item {
            anchors.fill: parent
            clip: true
            Column {
                spacing: th.gap
                y: -menu.firstRow * (th.boxH + th.gap)
                Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Repeater {
                    model: menu.rows
                    SettingBox {
                        readonly property bool isBack: modelData.back === true
                        width: th.flyW
                        theme: th
                        label: modelData.label
                        valueText: isBack ? "" : menu.format(modelData)
                        selected: menu.level === 1 && index === menu.row
                        pulse: menu.pulse
                        shown: fly.shown
                        order: Math.max(0, index - menu.firstRow)
                        travel: 40
                        labelFont: menu.labelFont
                        valueFont: menu.valueFont
                        glyph: "←"
                    }
                }
            }
        }
        // "more above / below" marks beside the column when it scrolls
        Rectangle { visible: menu.firstRow > 0; x: fly.width + 8; y: 2; width: 4; height: 14; color: th.yellow }
        Rectangle { visible: menu.firstRow + menu.maxRows < fly.count; x: fly.width + 8; y: fly.height - 16; width: 4; height: 14; color: th.yellow }
    }

    // ------------------------------------------------------------------
    // Footer hint
    // ------------------------------------------------------------------
    Item {
        y: menu.height - th.footH
        width: menu.width
        height: th.footH
        opacity: menu.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Rectangle { width: parent.width; height: 3; color: th.yellow }
        Text {
            x: th.pad
            anchors.verticalCenter: parent.verticalCenter
            text: menu.level === 0 ? "Left / Right: select      Up / Down: open"
                                   : "Left / Right: select      Up / Down: change / accept"
            color: th.white
            font.pixelSize: 12
            font.bold: true
            font.family: menu.labelFont
        }
    }
}
