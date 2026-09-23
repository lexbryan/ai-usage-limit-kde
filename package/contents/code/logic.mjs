// AI Usage Limit — the pure half of the Plasma widget.
//
// Plain ECMAScript with no Qt in it, so this one file is imported by the QML
// (`import "../code/logic.mjs" as Logic`) and by the node tests alike. The tests
// therefore run the shipped code, not a copy that can drift from it.
//
// Write it for QML's engine, not node's: V4 lacks some things node accepts —
// a bare `catch {`, object spread, String#trimEnd, Array#flatMap. The tests
// refuse those, because node alone would never notice.
//
// The two providers are read in completely different ways:
//
//   Claude Code publishes its limits to exactly one place — the JSON it pipes
//   into the statusLine command. aiul-statusline.sh sits in that position and
//   writes them to ~/.claude/cache/rate-limits.json; parseClaude reads that.
//
//   Codex writes its own limits into its session rollouts. aiul-codex-read.py
//   picks out the newest reading; parseCodex reads what it prints.
//
// Both are only as fresh as the last time you ran that tool, so a reading dims
// past STALE_AFTER and drops out of the panel past PANEL_HIDE_AFTER, staying in
// the popup with its age spelled out.
//
// Everything on screen reports capacity REMAINING, not consumed: the bars empty
// as you spend and the colour goes green → yellow → red.

// Dimmed past this; still shown, because a recent-ish number is still useful.
export const STALE_AFTER = 15 * 60;

// Dropped from the panel past this. A tool you have not run in a month should
// not hold a permanently grey slot in your panel — the popup still has it.
export const PANEL_HIDE_AFTER = 24 * 60 * 60;

// Thresholds on capacity REMAINING, matching the statusline's own colouring.
export const LOW_AT = 50;
export const CRITICAL_AT = 20;

export const PANEL_BAR_SEGMENTS = 5;

// Claude reports two windows (5h, 7d); Codex one or two depending on plan.
export const MAX_WINDOWS = 2;

// ---------------------------------------------------------------- formatting

export function fmtCountdown(epoch, now) {
    const secs = epoch - now;
    if (secs <= 0)
        return 'any moment now';
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    if (h >= 24)
        return `${Math.floor(h / 24)}d ${h % 24}h`;
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

// The fallback wall clock, "Mon 14:00". The widget passes a locale-aware
// formatter instead; this one exists so the logic stands alone under test.
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
export function fmtWallClock(epoch) {
    const d = new Date(epoch * 1000);
    const pad = n => String(n).padStart(2, '0');
    return `${DAYS[d.getDay()]} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function fmtAge(secs) {
    if (secs < 60)
        return 'just now';
    const m = Math.floor(secs / 60);
    if (m < 60)
        return `${m}m ago`;
    const h = Math.floor(m / 60);
    if (h < 24)
        return `${h}h ago`;
    return `${Math.floor(h / 24)}d ago`;
}

export function severity(remaining) {
    if (remaining < CRITICAL_AT)
        return 'crit';
    if (remaining < LOW_AT)
        return 'warn';
    return 'ok';
}

// How many of the panel bar's blocks are lit.
export function filledSegments(remaining, segments = PANEL_BAR_SEGMENTS) {
    const filled = Math.round(remaining * segments / 100);
    return Math.max(0, Math.min(segments, filled));
}

// "5h" -> "5-hour", "7d" -> "7-day"; anything else as it came.
export function longLabel(label) {
    const m = /^(\d+)([hd])$/.exec(label);
    if (!m)
        return label;
    return `${m[1]}-${m[2] === 'h' ? 'hour' : 'day'}`;
}

// Under a day, time left is what you want; beyond it, a wall clock.
export function resetText(w, now, wallClock = fmtWallClock) {
    if (!w || w.resetsAt === null)
        return '';
    const secs = w.resetsAt - now;
    return secs > 0 && secs < 24 * 3600
        ? `resets in ${fmtCountdown(w.resetsAt, now)}`
        : `resets ${wallClock(w.resetsAt) || ''}`.replace(/\s+$/, '');
}

// ------------------------------------------------------------------- parsing

// A window in the shape the UI wants, from a used-percentage plus a label.
// The conversion from used to remaining happens here and nowhere else.
export function makeWindow(label, usedPercentage, resetsAt) {
    if (typeof usedPercentage !== 'number' || !isFinite(usedPercentage))
        return null;
    const used = Math.max(0, Math.min(100, usedPercentage));
    return {
        label,
        used,
        remaining: 100 - used,
        resetsAt: typeof resetsAt === 'number' ? resetsAt : null,
    };
}

function parseObject(text) {
    if (typeof text !== 'string' || text.trim() === '')
        return null;
    let data;
    try {
        data = JSON.parse(text);
    } catch (e) {   // QML's engine rejects a bare `catch {` that node accepts
        return null;
    }
    return data && typeof data === 'object' && !Array.isArray(data) ? data : null;
}

// The cache aiul-statusline.sh writes. Returns null for every failure mode —
// absent, truncated, unparseable, no usable percentage — so the caller has
// exactly one "no data" branch.
export function parseClaude(text) {
    const data = parseObject(text);
    if (!data)
        return null;

    const windows = [];
    for (const [key, label] of [['five_hour', '5h'], ['seven_day', '7d']]) {
        const raw = data[key];
        if (!raw || typeof raw !== 'object')
            continue;
        const w = makeWindow(label, raw.used_percentage, raw.resets_at);
        if (w)
            windows.push(w);
    }
    if (windows.length === 0)
        return null;

    return {
        key: 'claude',
        name: 'Claude Code',
        glyph: '⚡',
        updatedAt: typeof data.updated_at === 'number' ? data.updated_at : null,
        detail: typeof data.model === 'string' ? data.model : null,
        windows,
    };
}

// What aiul-codex-read.py prints. The helper has already picked the newest
// reading and named each window from its own length, so slot names never leak
// in here. It prints nothing at all when Codex has never run.
export function parseCodex(text) {
    const data = parseObject(text);
    if (!data || !Array.isArray(data.windows))
        return null;

    const windows = [];
    for (const raw of data.windows) {
        if (!raw || typeof raw !== 'object')
            continue;
        const label = typeof raw.label === 'string' && raw.label ? raw.label : '?';
        const w = makeWindow(label, raw.used_percentage, raw.resets_at);
        if (w)
            windows.push(w);
        if (windows.length >= MAX_WINDOWS)
            break;
    }
    if (windows.length === 0)
        return null;

    return {
        key: 'codex',
        name: 'Codex',
        glyph: '◆',
        updatedAt: typeof data.updated_at === 'number' ? data.updated_at : null,
        detail: typeof data.plan === 'string' ? data.plan : null,
        windows,
    };
}

// ------------------------------------------------------------------- display

export function ageOf(provider, now) {
    if (!provider || provider.updatedAt === null)
        return null;
    return Math.max(0, now - provider.updatedAt);
}

// What reaches the panel for one provider, or null when it should not be shown.
export function panelSegment(provider, now) {
    const age = ageOf(provider, now);
    if (age === null || age > PANEL_HIDE_AFTER)
        return null;
    return {
        key: provider.key,
        name: provider.name,
        glyph: provider.glyph,
        windows: provider.windows,
        stale: age > STALE_AFTER,
        scarcest: Math.min(...provider.windows.map(w => w.remaining)),
    };
}

// "Claude Code · 4m ago · Opus 5" — the popup's section heading.
export function headline(provider, now) {
    const age = ageOf(provider, now);
    const bits = [age === null ? 'age unknown' : fmtAge(age)];
    if (provider.detail)
        bits.push(provider.detail);
    return bits.join(' · ');
}

// One line per provider for the hover tooltip.
export function tooltipLine(provider, now) {
    const windows = provider.windows
        .map(w => `${w.label} ${Math.round(w.remaining)}% left`)
        .join(', ');
    const age = ageOf(provider, now);
    return `${provider.name}: ${windows}` +
        (age !== null && age > STALE_AFTER ? ` (${fmtAge(age)})` : '');
}
