/*
 * One rate-limit window in the popup: name, capacity left, bar, reset time.
 * modelData is a window from logic.mjs's makeWindow().
 *
 * SPDX-License-Identifier: MIT
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/logic.mjs" as Logic

ColumnLayout {
    id: row

    required property var modelData
    property int now: 0

    readonly property color tone: {
        switch (Logic.severity(modelData.remaining)) {
        case "crit": return Kirigami.Theme.negativeTextColor;
        case "warn": return Kirigami.Theme.neutralTextColor;
        default: return Kirigami.Theme.positiveTextColor;
        }
    }

    // "Mon 14:00" in the user's own locale: their day names, 12 or 24 hour.
    function wallClock(epoch) {
        const d = new Date(epoch * 1000);
        return Qt.locale().dayName(d.getDay(), Locale.ShortFormat) + " "
            + d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
    }

    spacing: Math.round(Kirigami.Units.smallSpacing / 2)

    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents3.Label {
            text: Logic.longLabel(row.modelData.label)
            font.bold: true
        }
        Item {
            Layout.fillWidth: true
        }
        PlasmaComponents3.Label {
            text: i18n("%1% left", Math.round(row.modelData.remaining))
            color: row.tone
            font.features: { "tnum": 1 }
        }
    }

    // The track is the empty channel; the fill is what's left.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Math.round(Kirigami.Units.gridUnit / 3)
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b, 0.15)

        Rectangle {
            width: Math.round(parent.width * row.modelData.remaining / 100)
            height: parent.height
            radius: parent.radius
            color: row.tone
        }
    }

    PlasmaComponents3.Label {
        visible: text !== ""
        // Wrapped: a bare QML method handed to the module is not callable there.
        text: Logic.resetText(row.modelData, row.now, epoch => row.wallClock(epoch))
        font: Kirigami.Theme.smallFont
        opacity: 0.7
    }
}
