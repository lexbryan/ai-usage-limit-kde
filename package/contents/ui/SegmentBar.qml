/*
 * The panel's compact bar: a few blocks, lit for capacity remaining.
 *
 * SPDX-License-Identifier: MIT
 */

import QtQuick

import org.kde.kirigami as Kirigami

import "../code/logic.mjs" as Logic

Row {
    id: bar

    property real remaining: 0
    property color color: Kirigami.Theme.textColor
    property int segments: Logic.PANEL_BAR_SEGMENTS

    readonly property int filled: Logic.filledSegments(remaining, segments)

    spacing: 1

    Repeater {
        model: bar.segments
        delegate: Rectangle {
            required property int index
            width: Math.max(3, Math.round(Kirigami.Units.gridUnit * 0.3))
            height: Math.max(6, Math.round(Kirigami.Units.gridUnit * 0.55))
            radius: 1
            color: bar.color
            opacity: index < bar.filled ? 1 : 0.25
        }
    }
}
