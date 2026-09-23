/*
 * One provider's slot in the panel. modelData is a Logic.panelSegment().
 *
 * SPDX-License-Identifier: MIT
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/logic.mjs" as Logic

Item {
    id: chip

    required property var modelData
    property bool vertical: false

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    // A reading nobody is refreshing any more: no colour, just faded.
    opacity: modelData.stale ? 0.5 : 1

    // The theme's own positive/neutral/negative colours rather than raw green
    // and red, so the panel keeps looking like your panel.
    function tone(remaining) {
        if (modelData.stale)
            return Kirigami.Theme.textColor;
        switch (Logic.severity(remaining)) {
        case "crit": return Kirigami.Theme.negativeTextColor;
        case "warn": return Kirigami.Theme.neutralTextColor;
        default: return Kirigami.Theme.positiveTextColor;
        }
    }

    GridLayout {
        id: layout
        anchors.centerIn: parent
        flow: chip.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: Kirigami.Units.smallSpacing
        rowSpacing: 0

        Kirigami.Icon {
            source: Qt.resolvedUrl("../images/" + chip.modelData.key + ".png")
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            Layout.alignment: Qt.AlignCenter
        }

        Repeater {
            model: chip.vertical ? [] : chip.modelData.windows
            delegate: RowLayout {
                id: win
                required property var modelData
                required property int index
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    visible: win.index > 0
                    text: "·"
                    opacity: 0.6
                }
                PlasmaComponents3.Label {
                    text: win.modelData.label
                }
                SegmentBar {
                    remaining: win.modelData.remaining
                    color: chip.tone(win.modelData.remaining)
                    Layout.alignment: Qt.AlignVCenter
                }
                PlasmaComponents3.Label {
                    text: Math.round(win.modelData.remaining) + "%"
                    color: chip.tone(win.modelData.remaining)
                    // Fixed-width digits: the panel stops twitching as
                    // percentages tick over.
                    font.features: { "tnum": 1 }
                }
            }
        }

        PlasmaComponents3.Label {
            visible: chip.vertical
            text: Math.round(chip.modelData.scarcest) + "%"
            color: chip.tone(chip.modelData.scarcest)
            font: Kirigami.Theme.smallFont
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
