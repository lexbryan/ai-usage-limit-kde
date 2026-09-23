/*
 * The panel: a logo per provider, then each window's remaining capacity.
 *
 *   [logo] 5h ▮▮▯▯▯ 38% · 7d ▮▮▮▯▯ 59%   [logo] 7d ▮▮▮▮▯ 81%
 *
 * A vertical panel has no room for that, so it gets the logo and the scarcest
 * window's percentage, stacked.
 *
 * SPDX-License-Identifier: MIT
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

MouseArea {
    id: compact

    required property var host

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    property bool wasExpanded: false

    Layout.minimumWidth: vertical ? 0 : content.implicitWidth
    Layout.preferredWidth: vertical ? -1 : content.implicitWidth
    Layout.minimumHeight: vertical ? content.implicitHeight : 0
    Layout.preferredHeight: vertical ? content.implicitHeight : -1

    hoverEnabled: true
    onPressed: wasExpanded = host.expanded
    onClicked: host.expanded = !wasExpanded

    GridLayout {
        id: content
        anchors.centerIn: parent
        flow: compact.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        Repeater {
            model: compact.host.segments
            delegate: ProviderChip {
                vertical: compact.vertical
            }
        }

        // Alone when there is nothing to report.
        PlasmaComponents3.Label {
            visible: compact.host.segments.length === 0
            text: "⚡ –"
            opacity: 0.5
        }
    }
}
