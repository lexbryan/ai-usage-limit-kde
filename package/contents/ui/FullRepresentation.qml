/*
 * The popup: per provider, a heading with the reading's age, then a bar and
 * reset time for each window. Offers to connect Claude Code when it's installed
 * but not publishing yet.
 *
 * SPDX-License-Identifier: MIT
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

Item {
    id: full

    required property var host

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: column.implicitHeight + 2 * Kirigami.Units.largeSpacing
    Layout.preferredHeight: Layout.minimumHeight
    Layout.maximumHeight: Layout.minimumHeight

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Kirigami.Units.largeSpacing
        }
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: full.host.providers
            delegate: ProviderSection {
                now: full.host.now
                Layout.fillWidth: true
            }
        }

        // Claude Code is installed but its statusLine doesn't publish yet.
        ColumnLayout {
            visible: full.host.offerConnect
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Separator {
                visible: full.host.providers.length > 0
                Layout.fillWidth: true
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: Qt.resolvedUrl("../images/claude.png")
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }
                PlasmaExtras.Heading {
                    level: 4
                    text: "Claude Code"
                }
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: i18n("Claude Code reports its rate limits only to its statusline command. Connecting wraps your statusline so it also saves them for this widget. What it shows doesn't change, and settings.json is backed up first.")
            }
            PlasmaComponents3.Button {
                text: i18n("Connect Claude Code")
                icon.name: "network-connect"
                enabled: !full.host.setupRunning
                onClicked: full.host.connectClaude()
            }
        }

        // Set when connecting or disconnecting failed: the helper's own words.
        PlasmaComponents3.Label {
            visible: text !== ""
            text: full.host.setupMessage
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Kirigami.Theme.negativeTextColor
            font: Kirigami.Theme.smallFont
        }

        PlasmaComponents3.Label {
            visible: full.host.providers.length === 0 && !full.host.offerConnect
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.7
            text: full.host.claudeState === "wired"
                ? i18n("Connected. The numbers appear after Claude Code next draws its statusline. Codex readings appear after you next run Codex.")
                : i18n("No readings yet. Run Claude Code or Codex.")
        }
    }
}
