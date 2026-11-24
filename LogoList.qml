import QtQuick 2.3
import Qt.labs.folderlistmodel 2.1

// Lists the right-wing logo choices: every assets/wing_logo_<NAME>.png, as <NAME>.
// Kept in its own file and loaded through a Loader by HethelRace.qml, so that a
// unit whose Qt has no Qt.labs.folderlistmodel module still runs the dash (the
// Logo file setting then just offers DEFAULT).
Item {
    id: lister
    property alias folder: files.folder
    property var names: []

    function rebuild() {
        var out = [];
        for (var i = 0; i < files.count; i++) {
            var f = String(files.get(i, "fileName"));
            var low = f.toLowerCase();
            if (low.indexOf("wing_logo_") !== 0 || low.lastIndexOf(".png") !== low.length - 4) continue;
            var n = f.substring(10, f.length - 4);
            if (n.length > 0) out.push(n);
        }
        names = out;
    }

    FolderListModel {
        id: files
        nameFilters: ["wing_logo_*.png", "wing_logo_*.PNG"]
        showDirs: false
        sortField: FolderListModel.Name
        onCountChanged: lister.rebuild()
    }
    Component.onCompleted: rebuild()
}
