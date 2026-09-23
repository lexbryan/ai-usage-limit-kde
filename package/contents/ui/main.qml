/*
 * AI Usage Limit — Claude Code and Codex rate limits in the Plasma panel.
 *
 * The data side lives here; how it looks is CompactRepresentation (the panel)
 * and FullRepresentation (the popup). All parsing and formatting is in
 * code/logic.mjs, which the node tests exercise directly.
 *
 * A plain QML widget can't read files or watch them, so every reading comes
 * from a short command run through Plasma's executable engine:
 *
 *   Claude  `cat` of the cache aiul-statusline.sh writes     every 5 s
 *   Codex   code/aiul-codex-read.py, which reads only the     every 30 s
 *           tail of the newest session rollout
 *   state   code/claude-state.py — is statusLine wired?       on load and
 *                                                             on every open
 *
 * Nothing is parsed or re-rendered unless a command's output actually changed.
 *
 * SPDX-License-Identifier: MIT
 */

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

import "../code/logic.mjs" as Logic

PlasmoidItem {
    id: root

    // Parsed readings, null when there is none.
    property var claude: null
    property var codex: null

    // "wired" | "unwired" | "absent", or "" until the first check comes back.
    property string claudeState: ""
    property bool setupRunning: false
    property string setupMessage: ""

    property int now: Math.floor(Date.now() / 1000)

    readonly property var providers: [claude, codex].filter(p => p !== null)
    readonly property var segments: providers
        .map(p => Logic.panelSegment(p, now))
        .filter(s => s !== null)

    // Only nag when there is something to connect and nothing to show for it.
    readonly property bool offerConnect: claudeState === "unwired" && claude === null

    // ------------------------------------------------------------- commands

    // The helpers ship inside the package, wherever the store unpacked it.
    function codePath(name) {
        const url = Qt.resolvedUrl("../code/" + name).toString();
        return decodeURIComponent(url.replace(/^file:\/\//, ""));
    }
    function shellQuote(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'";
    }

    readonly property string claudeCmd:
        'cat -- "${AIUL_CACHE:-$HOME/.claude/cache/rate-limits.json}" 2>/dev/null'
    readonly property string codexCmd: "python3 " + shellQuote(codePath("aiul-codex-read.py"))
    readonly property string stateCmd: "python3 " + shellQuote(codePath("claude-state.py"))
    readonly property string connectCmd: "bash " + shellQuote(codePath("connect.sh")) + " 2>&1"
    readonly property string disconnectCmd:
        "python3 " + shellQuote(codePath("unwrap-statusline.py")) + " 2>&1"

    property string lastClaudeOut: ""
    property string lastCodexOut: ""

    function tick() {
        now = Math.floor(Date.now() / 1000);
    }

    function refresh() {
        tick();
        runner.run(claudeCmd);
        runner.run(codexCmd);
        runner.run(stateCmd);
    }

    function connectClaude() {
        setupRunning = true;
        setupMessage = "";
        runner.run(connectCmd);
    }

    function disconnectClaude() {
        setupRunning = true;
        setupMessage = "";
        runner.run(disconnectCmd);
    }

    function handle(source, exitCode, out) {
        if (source === claudeCmd) {
            if (out === lastClaudeOut)
                return;
            lastClaudeOut = out;
            tick();
            claude = Logic.parseClaude(out);
            // A reading proves the wiring, whatever settings.json looks like.
            if (claude !== null && claudeState === "unwired")
                runner.run(stateCmd);
        } else if (source === codexCmd) {
            // A failed run keeps the previous reading. Empty output is not a
            // failure: it is what the reader prints when Codex was never run.
            if (exitCode !== 0 || out === lastCodexOut)
                return;
            lastCodexOut = out;
            tick();
            codex = Logic.parseCodex(out);
        } else if (source === stateCmd) {
            if (exitCode === 0)
                claudeState = out.trim();
        } else if (source === connectCmd || source === disconnectCmd) {
            setupRunning = false;
            setupMessage = exitCode === 0 ? "" : out.trim();
            runner.run(stateCmd);
        }
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []

        // Connecting a command runs it; a command that is still running is not
        // started twice. Disconnecting on output is what lets it run again.
        onNewData: (source, data) => {
            disconnectSource(source);
            root.handle(source, data["exit code"], data["stdout"] || "");
        }

        function run(cmd) {
            connectSource(cmd);
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: runner.run(root.claudeCmd)
    }

    // Re-reads Codex and redraws ages and countdowns.
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.tick();
            runner.run(root.codexCmd);
        }
    }

    Component.onCompleted: runner.run(stateCmd)

    // Opening the popup is when stale state is most visible, so catch up then.
    onExpandedChanged: isExpanded => {
        if (isExpanded)
            refresh();
    }

    // ------------------------------------------------------------ plasmoid

    Plasmoid.icon: "speedometer"

    toolTipMainText: i18n("AI Usage Limit")
    toolTipSubText: {
        if (providers.length > 0)
            return providers.map(p => Logic.tooltipLine(p, now)).join("\n");
        if (offerConnect)
            return i18n("Claude Code isn't connected yet. Click to set it up.");
        return i18n("No readings yet. Run Claude Code or Codex.");
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Connect Claude Code")
            icon.name: "network-connect"
            visible: root.claudeState === "unwired"
            enabled: !root.setupRunning
            onTriggered: root.connectClaude()
        },
        PlasmaCore.Action {
            text: i18n("Disconnect Claude Code")
            icon.name: "network-disconnect"
            visible: root.claudeState === "wired"
            enabled: !root.setupRunning
            onTriggered: root.disconnectClaude()
        }
    ]

    compactRepresentation: CompactRepresentation {
        host: root
    }

    fullRepresentation: FullRepresentation {
        host: root
    }
}
