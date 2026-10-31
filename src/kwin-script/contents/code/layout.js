// SPDX-License-Identifier: GPL-3.0-or-later
// agino-tiling layout maths (docs/design.md 4.2, 4.3). Pure functions: no KWin objects, no state.
// Rectangles are plain {x, y, width, height}; minimum sizes are plain {minWidth, minHeight}.
.pragma library

var MIN_RATIO = 0.15
var MAX_RATIO = 0.85
var DEFAULT_RATIO = 0.55
var LAYOUTS = ["master", "columns", "monocle"]

function rect(x, y, width, height) {
    return { x: Math.round(x), y: Math.round(y), width: Math.round(width), height: Math.round(height) }
}

// The work area shrunk by the gap on every side.
function inner(area, gap) {
    return rect(area.x + gap, area.y + gap, Math.max(1, area.width - 2 * gap), Math.max(1, area.height - 2 * gap))
}

function clampRatio(ratio) {
    return Math.min(MAX_RATIO, Math.max(MIN_RATIO, ratio))
}

// Master width that goes with a ratio, and the ratio that goes with a master width.
function masterWidth(area, gap, ratio) {
    return Math.round((inner(area, gap).width - gap) * clampRatio(ratio))
}

function ratioFromWidth(width, area, gap) {
    return clampRatio(width / (inner(area, gap).width - gap))
}

// Master on the left (ratio of the width), the others share the right side top to bottom.
function masterStack(area, gap, ratio, count) {
    if (count <= 0)
        return []
    const box = inner(area, gap)
    if (count === 1)
        return [box]
    const mw = masterWidth(area, gap, ratio)
    const sx = box.x + mw + gap
    const sw = box.width - mw - gap
    const stack = count - 1
    const sh = (box.height - gap * (stack - 1)) / stack
    const rects = [rect(box.x, box.y, mw, box.height)]
    for (let i = 0; i < stack; ++i)
        rects.push(rect(sx, box.y + i * (sh + gap), sw, sh))
    return rects
}

// Equal-width columns side by side.
function columns(area, gap, count) {
    if (count <= 0)
        return []
    const box = inner(area, gap)
    const cw = (box.width - gap * (count - 1)) / count
    const rects = []
    for (let i = 0; i < count; ++i)
        rects.push(rect(box.x + i * (cw + gap), box.y, cw, box.height))
    return rects
}

// Every window gets the whole box.
function monocle(area, gap, count) {
    const rects = []
    for (let i = 0; i < count; ++i)
        rects.push(inner(area, gap))
    return rects
}

// Index of the first rect that does not satisfy its window's minimum size, or -1.
function firstMisfit(rects, mins) {
    for (let i = 0; i < rects.length; ++i) {
        const m = mins[i]
        if (m && (rects[i].width < m.minWidth || rects[i].height < m.minHeight))
            return i
    }
    return -1
}

// 4.3: the master stays, everything else shares the full stack column (focus decides who is on top).
function stackFallback(area, gap, ratio, count) {
    if (count <= 1)
        return masterStack(area, gap, ratio, count)
    const box = inner(area, gap)
    const mw = masterWidth(area, gap, ratio)
    const sx = box.x + mw + gap
    const sw = box.width - mw - gap
    const rects = [rect(box.x, box.y, mw, box.height)]
    for (let i = 1; i < count; ++i)
        rects.push(rect(sx, box.y, sw, box.height))
    return rects
}

// Rectangles for one output: {rects, fallback}. layout is "master", "columns" or "monocle"; a layout
// that cannot give some window its minimum size is replaced by the 4.3 fallback (master) or by the
// single-window layout (columns).
function arrange(layout, area, gap, ratio, mins) {
    const count = mins.length
    let rects
    if (layout === "monocle")
        return { rects: monocle(area, gap, count), fallback: false }
    if (layout === "columns") {
        rects = columns(area, gap, count)
        if (firstMisfit(rects, mins) < 0)
            return { rects: rects, fallback: false }
        return { rects: monocle(area, gap, count), fallback: true }
    }
    rects = masterStack(area, gap, ratio, count)
    if (firstMisfit(rects, mins) < 0)
        return { rects: rects, fallback: false }
    return { rects: stackFallback(area, gap, ratio, count), fallback: true }
}

function nextLayout(layout) {
    const i = LAYOUTS.indexOf(layout)
    return LAYOUTS[(i + 1) % LAYOUTS.length]
}

// Index of the rect containing the point, ignoring index `skip`; -1 when none.
function indexAt(rects, px, py, skip) {
    for (let i = 0; i < rects.length; ++i) {
        const r = rects[i]
        if (i !== skip && px >= r.x && px < r.x + r.width && py >= r.y && py < r.y + r.height)
            return i
    }
    return -1
}

// ---- order helpers (arrays of ids; they return new arrays) ----

function swap(order, i, j) {
    if (i < 0 || j < 0 || i >= order.length || j >= order.length || i === j)
        return order.slice()
    const result = order.slice()
    result[i] = order[j]
    result[j] = order[i]
    return result
}

// Index `step` places away from i, wrapping around.
function wrapIndex(count, i, step) {
    if (count <= 0)
        return -1
    return (((i + step) % count) + count) % count
}

// Swap id with its neighbour `step` places away (wrapping).
function moveBy(order, id, step) {
    const i = order.indexOf(id)
    if (i < 0 || order.length < 2)
        return order.slice()
    return swap(order, i, wrapIndex(order.length, i, step))
}

// Swap id with the master; if it already is the master, with the first stack window.
function swapMaster(order, id) {
    const i = order.indexOf(id)
    if (i < 0 || order.length < 2)
        return order.slice()
    return swap(order, i, i === 0 ? 1 : 0)
}

// Put `id` at index `to` (clamped), shifting the others.
function moveTo(order, id, to) {
    const rest = order.filter(x => x !== id)
    if (rest.length === order.length)
        return order.slice()
    rest.splice(Math.max(0, Math.min(rest.length, to)), 0, id)
    return rest
}

// `order` holds ids of members and non-members; `members` is a reordering of the members only.
// The members take the member slots of `order` in the new sequence, non-members stay where they are.
function applyMemberOrder(order, members) {
    const result = []
    let next = 0
    for (const id of order)
        result.push(members.indexOf(id) >= 0 ? members[next++] : id)
    return result
}
