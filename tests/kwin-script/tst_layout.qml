// SPDX-License-Identifier: GPL-3.0-or-later
// Unit tests for the pure layout functions (docs/design.md 4.2, 4.3, 7).
// Run: qmltestrunner -input tests/kwin-script
import QtQuick
import QtTest
import "../../src/kwin-script/contents/code/layout.js" as Layout

TestCase {
    name: "AginoTilingLayout"

    readonly property var area: ({ x: 0, y: 0, width: 1000, height: 600 })

    function noMins(n) {
        return Array.from({ length: n }, () => ({ minWidth: 0, minHeight: 0 }));
    }

    function overlaps(a, b) {
        return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
    }

    function noOverlap(rects) {
        for (let i = 0; i < rects.length; ++i) {
            for (let j = i + 1; j < rects.length; ++j)
                verify(!overlaps(rects[i], rects[j]), "rects " + i + " and " + j + " overlap");
        }
    }

    function test_inner() {
        compare(Layout.inner(area, 8), { x: 8, y: 8, width: 984, height: 584 });
        compare(Layout.inner({ x: 50, y: 30, width: 100, height: 100 }, 0), { x: 50, y: 30, width: 100, height: 100 });
    }

    function test_masterStack_empty() {
        compare(Layout.masterStack(area, 8, 0.55, 0), []);
    }

    function test_masterStack_one() {
        compare(Layout.masterStack(area, 8, 0.55, 1), [{ x: 8, y: 8, width: 984, height: 584 }]);
    }

    function test_masterStack_two() {
        const r = Layout.masterStack(area, 8, 0.5, 2);
        compare(r.length, 2);
        // inner width 984, master = (984 - 8) * 0.5 = 488
        compare(r[0], { x: 8, y: 8, width: 488, height: 584 });
        compare(r[1], { x: 504, y: 8, width: 488, height: 584 });
        noOverlap(r);
    }

    function test_masterStack_five() {
        const r = Layout.masterStack(area, 8, 0.55, 5);
        compare(r.length, 5);
        const stack = r.slice(1);
        for (const s of stack) {
            compare(s.x, r[1].x);
            compare(s.width, r[1].width);
            compare(s.height, 140); // (584 - 3 * 8) / 4
        }
        compare(stack[3].y + stack[3].height, 592);
        compare(r[1].x - (r[0].x + r[0].width), 8);
        compare(r[1].x + r[1].width, 992);
        noOverlap(r);
    }

    function test_masterStack_ratio_clamped() {
        compare(Layout.masterStack(area, 0, 0.01, 2)[0].width, 150);
        compare(Layout.masterStack(area, 0, 5, 2)[0].width, 850);
    }

    function test_ratioLimits() {
        // area 1000 wide, gap 8: the width the ratio applies to is 1000 - 2 * 8 - 8 = 976
        const l = Layout.ratioLimits(area, 8, 488, 244)
        fuzzyCompare(l.min, 0.5, 0.001)
        fuzzyCompare(l.max, 0.75, 0.001)
        compare(Layout.ratioLimits(area, 8, 0, 0), { min: 0, max: 1 })
    }

    function test_adjustedRatio() {
        const limits = { min: 0.5, max: 0.75 }
        fuzzyCompare(Layout.adjustedRatio(0.55, -0.05, limits), 0.5, 0.001)
        fuzzyCompare(Layout.adjustedRatio(0.5, -0.05, limits), 0.5, 0.001)       // already at the limit
        fuzzyCompare(Layout.adjustedRatio(0.45, -0.05, limits), 0.45, 0.001)     // beyond it: does not go further
        fuzzyCompare(Layout.adjustedRatio(0.45, 0.05, limits), 0.5, 0.001)       // but may grow
        fuzzyCompare(Layout.adjustedRatio(0.7, 0.05, limits), 0.75, 0.001)
        fuzzyCompare(Layout.adjustedRatio(0.75, 0.05, limits), 0.75, 0.001)
        fuzzyCompare(Layout.adjustedRatio(0.8, 0.05, limits), 0.8, 0.001)        // beyond the upper limit
        fuzzyCompare(Layout.adjustedRatio(0.8, -0.05, limits), 0.75, 0.001)
    }

    function test_adjustedRatio_unfit_and_unlimited() {
        // the two minimum widths together are wider than the area: limits are ignored (4.3)
        fuzzyCompare(Layout.adjustedRatio(0.55, -0.05, { min: 0.7, max: 0.3 }), 0.5, 0.001)
        fuzzyCompare(Layout.adjustedRatio(0.55, 0.05, { min: 0, max: 1 }), 0.6, 0.001)
        // the global range still applies
        fuzzyCompare(Layout.adjustedRatio(0.16, -0.05, { min: 0, max: 1 }), 0.15, 0.001)
        fuzzyCompare(Layout.adjustedRatio(0.84, 0.05, { min: 0, max: 1 }), 0.85, 0.001)
    }

    function test_misfit_and_floatedForMinimums() {
        // area 1000x600, gap 8, ratio 0.5: the master is 488 wide, the stack cells 488 wide and 288 high
        const none = { minWidth: 0, minHeight: 0 }
        compare(Layout.misfit("master", area, 8, 0.5, [none, none, none]), -1)
        compare(Layout.misfit("master", area, 8, 0.5, [none, { minWidth: 500, minHeight: 0 }, none]), 1)
        compare(Layout.misfit("master", area, 8, 0.5, [{ minWidth: 489, minHeight: 0 }, none]), 0)
        compare(Layout.misfit("master", area, 8, 0.5, [none, none, { minWidth: 0, minHeight: 300 }]), 2)
        compare(Layout.misfit("monocle", area, 8, 0.5, [{ minWidth: 5000, minHeight: 5000 }, none]), -1)
        compare(Layout.misfit("master", area, 8, 0.5, [{ minWidth: 5000, minHeight: 5000 }]), -1)
        compare(Layout.floatedForMinimums("master", area, 8, 0.5, [none, none]), [])
        // one window does not fit: it floats, the others are tried again
        compare(Layout.floatedForMinimums("master", area, 8, 0.5, [none, { minWidth: 500, minHeight: 0 }, none]), [1])
        // the master is too narrow for its minimum: it floats and the other window is alone
        compare(Layout.floatedForMinimums("master", area, 8, 0.5, [{ minWidth: 700, minHeight: 0 }, none]), [0])
        // the stack gets crowded: the first window that is too low floats, then the other has room again
        const low = { minWidth: 0, minHeight: 250 }
        compare(Layout.floatedForMinimums("master", area, 8, 0.5, [none, low, low, low]), [1])
        // the last window stays even if its minimum is larger than the box
        compare(Layout.floatedForMinimums("master", area, 8, 0.5, [{ minWidth: 5000, minHeight: 0 }, { minWidth: 5000, minHeight: 0 }]), [0])
        compare(Layout.floatedForMinimums("columns", area, 8, 0.5, [none, { minWidth: 600, minHeight: 0 }]), [1])
    }

    function test_masterStack_offset_area() {
        const r = Layout.masterStack({ x: 1920, y: 40, width: 800, height: 400 }, 10, 0.5, 2);
        compare(r[0].x, 1930);
        compare(r[0].y, 50);
    }

    function test_columns() {
        const r = Layout.columns(area, 8, 1);
        compare(r, [{ x: 8, y: 8, width: 984, height: 584 }]);
        const c = Layout.columns(area, 8, 2);
        compare(c[0], { x: 8, y: 8, width: 488, height: 584 });
        compare(c[1], { x: 504, y: 8, width: 488, height: 584 });
        const five = Layout.columns(area, 8, 5);
        compare(five.length, 5);
        compare(five[4].x + five[4].width, 992);
        noOverlap(five);
        compare(Layout.columns(area, 8, 0), []);
    }

    function test_monocle() {
        const r = Layout.monocle(area, 8, 3);
        compare(r.length, 3);
        for (const x of r)
            compare(x, { x: 8, y: 8, width: 984, height: 584 });
        compare(Layout.monocle(area, 8, 0), []);
    }

    function test_arrange_dispatch() {
        compare(Layout.arrange("master", area, 8, 0.55, noMins(3)).rects, Layout.masterStack(area, 8, 0.55, 3));
        compare(Layout.arrange("columns", area, 8, 0.55, noMins(3)).rects, Layout.columns(area, 8, 3));
        compare(Layout.arrange("monocle", area, 8, 0.55, noMins(3)).rects, Layout.monocle(area, 8, 3));
        compare(Layout.arrange("master", area, 8, 0.55, noMins(3)).fallback, false);
    }

    function test_firstMisfit() {
        const rects = Layout.masterStack(area, 8, 0.55, 3);
        compare(Layout.firstMisfit(rects, noMins(3)), -1);
        const mins = noMins(3);
        mins[2] = { minWidth: 100, minHeight: 400 };
        compare(Layout.firstMisfit(rects, mins), 2);
    }

    function test_fallback_master_stack() {
        const mins = noMins(4);
        mins[3] = { minWidth: 200, minHeight: 300 }; // stack slots are ~190 high
        const res = Layout.arrange("master", area, 8, 0.55, mins);
        verify(res.fallback);
        compare(res.rects[0], Layout.masterStack(area, 8, 0.55, 4)[0]);
        for (let i = 1; i < 4; ++i)
            compare(res.rects[i], { x: res.rects[1].x, y: 8, width: res.rects[1].width, height: 584 });
        compare(Layout.firstMisfit(res.rects, mins), -1);
    }

    function test_fallback_columns() {
        const mins = noMins(5);
        mins[0] = { minWidth: 400, minHeight: 100 };
        const res = Layout.arrange("columns", area, 8, 0.55, mins);
        verify(res.fallback);
        compare(res.rects, Layout.monocle(area, 8, 5));
    }

    function test_no_fallback_when_fits() {
        const mins = noMins(2);
        mins[1] = { minWidth: 400, minHeight: 500 };
        verify(!Layout.arrange("master", area, 8, 0.55, mins).fallback);
    }

    function test_nextLayout() {
        compare(Layout.nextLayout("master"), "columns");
        compare(Layout.nextLayout("columns"), "monocle");
        compare(Layout.nextLayout("monocle"), "master");
        compare(Layout.nextLayout("unknown"), "master");
    }

    function test_ratio_roundtrip() {
        const w = Layout.masterWidth(area, 8, 0.6);
        fuzzyCompare(Layout.ratioFromWidth(w, area, 8), 0.6, 0.002);
        compare(Layout.ratioFromWidth(10, area, 8), Layout.MIN_RATIO);
        compare(Layout.ratioFromWidth(990, area, 8), Layout.MAX_RATIO);
    }

    function test_indexAt() {
        const r = Layout.masterStack(area, 8, 0.5, 3);
        compare(Layout.indexAt(r, 100, 100, -1), 0);
        compare(Layout.indexAt(r, 700, 100, -1), 1);
        compare(Layout.indexAt(r, 700, 500, -1), 2);
        compare(Layout.indexAt(r, 100, 100, 0), -1);
        compare(Layout.indexAt(r, 500, 100, -1), -1); // inside the gap
    }

    function test_swap() {
        const o = ["a", "b", "c"];
        compare(Layout.swap(o, 0, 2), ["c", "b", "a"]);
        compare(o, ["a", "b", "c"]);
        compare(Layout.swap(o, 1, 1), o);
        compare(Layout.swap(o, 0, 5), o);
    }

    function test_moveBy() {
        const o = ["a", "b", "c"];
        compare(Layout.moveBy(o, "a", 1), ["b", "a", "c"]);
        compare(Layout.moveBy(o, "c", 1), ["c", "b", "a"]);
        compare(Layout.moveBy(o, "a", -1), ["c", "b", "a"]);
        compare(Layout.moveBy(o, "x", 1), o);
        compare(Layout.moveBy(["a"], "a", 1), ["a"]);
    }

    function test_swapMaster() {
        const o = ["a", "b", "c"];
        compare(Layout.swapMaster(o, "c"), ["c", "b", "a"]);
        compare(Layout.swapMaster(o, "a"), ["b", "a", "c"]);
        compare(Layout.swapMaster(["a"], "a"), ["a"]);
        compare(Layout.swapMaster(o, "x"), o);
    }

    function test_moveTo() {
        compare(Layout.moveTo(["a", "b", "c"], "c", 0), ["c", "a", "b"]);
        compare(Layout.moveTo(["a", "b", "c"], "a", 1), ["b", "a", "c"]);
        compare(Layout.moveTo(["a", "b", "c"], "a", 9), ["b", "c", "a"]);
        compare(Layout.moveTo(["a"], "a", 1), ["a"]);
        compare(Layout.moveTo(["a", "b"], "x", 0), ["a", "b"]);
    }

    function test_wrapIndex() {
        compare(Layout.wrapIndex(3, 2, 1), 0);
        compare(Layout.wrapIndex(3, 0, -1), 2);
        compare(Layout.wrapIndex(0, 0, 1), -1);
    }

    function test_applyMemberOrder() {
        // "x" and "y" are non-members (e.g. minimized windows or other outputs) and keep their slots
        compare(Layout.applyMemberOrder(["a", "x", "b", "y", "c"], ["c", "a", "b"]), ["c", "x", "a", "y", "b"]);
        compare(Layout.applyMemberOrder(["a", "b"], ["a", "b"]), ["a", "b"]);
    }

    // ---- remembered window sizes (design 4.8) ----

    function test_sizesClose() {
        verify(Layout.sizesClose(756, 613, 756, 613, 6));
        verify(Layout.sizesClose(760, 610, 756, 613, 6));
        verify(!Layout.sizesClose(763, 613, 756, 613, 6));
        verify(!Layout.sizesClose(756, 620, 756, 613, 6));
        // an unknown size never matches
        verify(!Layout.sizesClose(0, 0, 0, 0, 6));
        verify(!Layout.sizesClose(5, 5, 0, 0, 6));
    }

    function test_restoredRect_keepsCentreAndStaysInside() {
        const current = { x: 100, y: 100, width: 400, height: 300 };
        // bigger window around the same centre (300, 250): 800x500 would start at (-100, 0), so it is moved to x 0
        compare(Layout.restoredRect(800, 500, current, area), { x: 0, y: 0, width: 800, height: 500 });
        // a smaller one keeps the centre
        compare(Layout.restoredRect(200, 100, current, area), { x: 200, y: 200, width: 200, height: 100 });
        // would stick out on the left: moved into the area
        const left = { x: 0, y: 0, width: 200, height: 200 };
        compare(Layout.restoredRect(600, 400, left, area), { x: 0, y: 0, width: 600, height: 400 });
        // would stick out on the right and at the bottom
        const corner = { x: 800, y: 500, width: 200, height: 100 };
        compare(Layout.restoredRect(600, 400, corner, area), { x: 400, y: 200, width: 600, height: 400 });
        // bigger than the area: the window gets the size of the area
        compare(Layout.restoredRect(3000, 2000, current, area), { x: 0, y: 0, width: 1000, height: 600 });
        // an area that does not start at 0 (dock, second screen)
        const second = { x: 1000, y: 40, width: 800, height: 500 };
        compare(Layout.restoredRect(400, 300, { x: 1000, y: 40, width: 100, height: 100 }, second), { x: 1000, y: 40, width: 400, height: 300 });
    }

    function test_remember_ordersByUseAndCaps() {
        let map = {};
        map = Layout.remember(map, "a", [1, 2, 0, 0], 3);
        map = Layout.remember(map, "b", [3, 4, 0, 0], 3);
        map = Layout.remember(map, "c", [5, 6, 0, 0], 3);
        compare(Object.keys(map), ["a", "b", "c"]);
        // touching "a" moves it to the end and replaces the entry
        map = Layout.remember(map, "a", [7, 8, 9, 10], 3);
        compare(Object.keys(map), ["b", "c", "a"]);
        compare(map.a, [7, 8, 9, 10]);
        // a fourth application pushes the oldest one out
        map = Layout.remember(map, "d", [1, 1, 1, 1], 3);
        compare(Object.keys(map), ["c", "a", "d"]);
        // the input is not changed
        const before = { x: [1, 2, 3, 4] };
        Layout.remember(before, "y", [1, 1, 1, 1], 5);
        compare(Object.keys(before), ["x"]);
        // fractions are rounded
        compare(Layout.remember({}, "z", [10.4, 20.6, 0, 0], 3).z, [10, 21, 0, 0]);
    }

    function test_mergeSizes_extraWins() {
        const base = { a: [1, 1, 0, 0], b: [2, 2, 0, 0] };
        const extra = { b: [3, 3, 4, 4], c: [5, 5, 0, 0] };
        const merged = Layout.mergeSizes(base, extra, 10);
        compare(Object.keys(merged), ["a", "b", "c"]);
        compare(merged.b, [3, 3, 4, 4]);
        compare(Object.keys(Layout.mergeSizes(base, extra, 2)), ["b", "c"]);
        compare(Layout.mergeSizes({}, {}, 5), {});
    }

    function test_parseSizes_leavesOutWhatIsNotATable() {
        compare(Layout.parseSizes(""), {});
        compare(Layout.parseSizes("not json"), {});
        compare(Layout.parseSizes("[1,2]"), {});
        compare(Layout.parseSizes("null"), {});
        compare(Layout.parseSizes("{\"a\":[1,2,3,4],\"b\":[1,2,3],\"c\":\"x\",\"d\":[1,2,3,-4],\"e\":[5,6,7,8]}"), { a: [1, 2, 3, 4], e: [5, 6, 7, 8] });
        // more entries than the cap: the last ones are kept
        const big = {};
        for (let i = 0; i < Layout.MAX_REMEMBERED_APPS + 5; ++i)
            big["app" + i] = [i, i, 0, 0];
        const parsed = Layout.parseSizes(JSON.stringify(big));
        compare(Object.keys(parsed).length, Layout.MAX_REMEMBERED_APPS);
        verify(parsed["app" + (Layout.MAX_REMEMBERED_APPS + 4)] !== undefined);
        verify(parsed.app0 === undefined);
    }
}
