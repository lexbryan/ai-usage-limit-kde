/*
 * One provider in the popup. modelData is a parsed provider from logic.mjs.
 *
 * SPDX-License-Identifier: MIT
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

import "../code/logic.mjs" as Logic

ColumnLayout {
    id: section

    required property var modelData
    required property int index
    property int now: 0

    spacing: Kirigami.Units.smallSpacing

    Kirigami.Separator {
        visible: section.index > 0
        Layout.fillWidth: true
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.fillWidth: true

        Kirigami.Icon {
            source: Qt.resolvedUrl("../images/" + section.modelData.key + ".png")
            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        }
        PlasmaExtras.Heading {
            level: 4
            text: section.modelData.name
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            opacity: 0.7
            text: Logic.headline(section.modelData, section.now)
        }
    }

    Repeater {
        model: section.modelData.windows
        delegate: WindowRow {
            now: section.now
            Layout.fillWidth: true
        }
    }
}
