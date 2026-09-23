// The widget's pure logic, under plain node — no Plasma, no session.
//
// This imports the very file the QML imports (package/contents/code/logic.mjs),
// so the tests can't drift from what ships. Run: node --test test/*.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';

import {
    fmtCountdown, fmtWallClock, fmtAge, severity, filledSegments, longLabel,
    resetText, parseClaude, parseCodex, panelSegment, headline, tooltipLine,
    STALE_AFTER,
} from '../package/contents/code/logic.mjs';

const now = Math.floor(Date.now() / 1000);

test('countdown and age', () => {
    assert.equal(fmtCountdown(now + 9420, now), '2h 37m');
    assert.equal(fmtCountdown(now + 43 * 60 + 5, now), '43m');
    assert.equal(fmtCountdown(now - 10, now), 'any moment now');
    assert.equal(fmtCountdown(now + 3 * 86400 + 4 * 3600, now), '3d 4h');
    assert.equal(fmtAge(30), 'just now');
    assert.equal(fmtAge(4 * 60), '4m ago');
    assert.equal(fmtAge(3 * 3600 + 120), '3h ago');
    assert.equal(fmtAge(2 * 86400), '2d ago');
    assert.match(fmtWallClock(now + 230000), /^[A-Z][a-z]{2} \d{2}:\d{2}$/);
});

// Colour tracks capacity REMAINING, so a high number is the healthy one.
test('severity is on remaining', () => {
    assert.equal(severity(100), 'ok');
    assert.equal(severity(50), 'ok');
    assert.equal(severity(49), 'warn');
    assert.equal(severity(20), 'warn');
    assert.equal(severity(19), 'crit');
    assert.equal(severity(0), 'crit');
});

test('panel bar rounds and clamps', () => {
    assert.equal(filledSegments(100), 5);
    assert.equal(filledSegments(0), 0);
    assert.equal(filledSegments(50), 3, 'half rounds up');
    assert.equal(filledSegments(38), 2);
    assert.equal(filledSegments(5), 0, 'a sliver still empties');
    assert.equal(filledSegments(140), 5);
    assert.equal(filledSegments(-20), 0);
    assert.equal(filledSegments(63, 10), 6, 'other widths');
});

test('window labels', () => {
    assert.equal(longLabel('5h'), '5-hour');
    assert.equal(longLabel('7d'), '7-day');
    assert.equal(longLabel('?'), '?');
});

test('reset text: countdown under a day, wall clock beyond', () => {
    const clock = () => 'Mon 14:00';
    assert.equal(resetText({resetsAt: now + 9420}, now, clock), 'resets in 2h 37m');
    assert.equal(resetText({resetsAt: now + 3 * 86400}, now, clock), 'resets Mon 14:00');
    assert.equal(resetText({resetsAt: now - 5}, now, clock), 'resets Mon 14:00');
    assert.equal(resetText({resetsAt: null}, now, clock), '');
    assert.equal(resetText({resetsAt: now + 3 * 86400}, now, () => null), 'resets');
});

test('parseClaude converts used to remaining exactly once', () => {
    const good = parseClaude(JSON.stringify({
        updated_at: now, model: 'Opus 5',
        five_hour: {used_percentage: 62.3, resets_at: now + 9420},
        seven_day: {used_percentage: 41.0, resets_at: now + 230000},
    }));
    assert.ok(good);
    assert.equal(good.key, 'claude');
    assert.equal(good.name, 'Claude Code');
    assert.equal(good.windows.length, 2);
    assert.equal(good.windows[0].label, '5h');
    assert.equal(Math.round(good.windows[0].used), 62);
    assert.equal(Math.round(good.windows[0].remaining), 38);
    assert.equal(Math.round(good.windows[1].remaining), 59);
    assert.equal(good.detail, 'Opus 5');
});

test('parseClaude: every degraded input is null', () => {
    assert.equal(parseClaude(''), null, 'empty (cat of a missing file)');
    assert.equal(parseClaude('{"five_hour": {"used_per'), null, 'truncated');
    assert.equal(parseClaude('[1,2,3]'), null, 'not an object');
    assert.equal(parseClaude('null'), null);
    assert.equal(parseClaude('{"updated_at": 1}'), null, 'no rate limits');
    assert.equal(parseClaude('{"five_hour":{"used_percentage":"62"},"seven_day":null}'),
        null, 'percentage not a number');
    assert.equal(parseClaude(undefined), null);
});

test('parseClaude: partial and wild values', () => {
    const partial = parseClaude(JSON.stringify({
        updated_at: now, five_hour: {used_percentage: 5}, seven_day: null,
    }));
    assert.equal(partial.windows.length, 1);
    assert.equal(partial.windows[0].resetsAt, null);
    assert.equal(partial.detail, null);

    const wild = parseClaude(JSON.stringify({
        updated_at: 'nope', five_hour: {used_percentage: 130}, seven_day: {used_percentage: -4},
    }));
    assert.equal(wild.windows[0].remaining, 0, 'over-100 used clamps to 0 left');
    assert.equal(wild.windows[1].remaining, 100, 'negative used clamps to 100 left');
    assert.equal(wild.updatedAt, null);
});

test('parseCodex reads the helper output', () => {
    const cx = parseCodex(JSON.stringify({
        updated_at: now, provider: 'codex', plan: 'pro',
        windows: [{label: '7d', window_minutes: 10080,
                   used_percentage: 100.0, resets_at: now + 5000}],
    }));
    assert.equal(cx.key, 'codex');
    assert.equal(cx.name, 'Codex');
    assert.equal(cx.windows.length, 1);
    assert.equal(cx.windows[0].label, '7d', 'label kept from the helper');
    assert.equal(cx.windows[0].remaining, 0);
    assert.equal(cx.detail, 'pro');

    const two = parseCodex(JSON.stringify({updated_at: now, windows: [
        {label: '5h', used_percentage: 10}, {label: '7d', used_percentage: 20},
        {label: 'extra', used_percentage: 30}]}));
    assert.equal(two.windows.length, 2, 'caps at MAX_WINDOWS');
});

// The helper prints nothing at all when Codex has never been run. That is a
// normal state, not a parse failure.
test('parseCodex: absent and broken are null', () => {
    assert.equal(parseCodex(''), null);
    assert.equal(parseCodex('   \n'), null);
    assert.equal(parseCodex('boom'), null);
    assert.equal(parseCodex('{"provider":"codex"}'), null);
    assert.equal(parseCodex('{"windows":[]}'), null);
    assert.equal(parseCodex('{"windows":[{"label":"7d"}]}'), null);
    assert.equal(parseCodex(undefined), null);
});

test('panelSegment: what reaches the panel at each age', () => {
    const fresh = {key: 'x', name: 'X', glyph: '◆', updatedAt: now, detail: null,
                   windows: [{label: '7d', used: 62, remaining: 38, resetsAt: null}]};
    const seg = panelSegment(fresh, now);
    assert.equal(seg.key, 'x');
    assert.equal(seg.stale, false);
    assert.equal(seg.scarcest, 38);
    assert.equal(seg.windows.length, 1);

    const dimmed = panelSegment({...fresh, updatedAt: now - 20 * 60}, now);
    assert.ok(dimmed, '20m old still shown');
    assert.equal(dimmed.stale, true, '20m old marked stale');

    assert.equal(panelSegment({...fresh, updatedAt: now - 28 * 86400}, now), null,
        '28d old dropped from the panel');
    assert.equal(panelSegment({...fresh, updatedAt: null}, now), null, 'unknown age dropped');
    assert.equal(panelSegment(null, now), null);

    const multi = {...fresh, windows: [
        {label: '5h', used: 5, remaining: 95, resetsAt: null},
        {label: '7d', used: 88, remaining: 12, resetsAt: null}]};
    assert.equal(panelSegment(multi, now).scarcest, 12);
});

test('headline and tooltip', () => {
    const p = {key: 'claude', name: 'Claude Code', updatedAt: now - 4 * 60, detail: 'Opus 5',
               windows: [{label: '5h', remaining: 38.2}, {label: '7d', remaining: 59}]};
    assert.equal(headline(p, now), '4m ago · Opus 5');
    assert.equal(headline({...p, updatedAt: null, detail: null}, now), 'age unknown');
    assert.equal(tooltipLine(p, now), 'Claude Code: 5h 38% left, 7d 59% left');
    assert.equal(tooltipLine({...p, updatedAt: now - STALE_AFTER - 3600}, now),
        'Claude Code: 5h 38% left, 7d 59% left (1h ago)', 'stale says how old');
});

// Node runs this file happily with syntax Plasma's QML engine (V4) rejects, and
// then the widget fails to load at all. Each of these was confirmed missing in
// V4 under Plasma 6.7 / Qt 6.11.
test('logic.mjs sticks to what QML can run', async () => {
    const {readFile} = await import('node:fs/promises');
    const src = (await readFile(
        new URL('../package/contents/code/logic.mjs', import.meta.url), 'utf8'))
        .split('\n').map(l => l.replace(/\/\/.*$/, '')).join('\n');   // comments may say anything
    const banned = {
        'bare catch': /catch\s*\{/,
        'object spread': /\{\s*\.\.\./,
        'trimEnd/trimStart': /\.trim(End|Start)\(/,
        'flat/flatMap': /\.flat(Map)?\(/,
    };
    for (const [what, re] of Object.entries(banned))
        assert.doesNotMatch(src, re, `${what} does not parse or exist in QML`);
});
