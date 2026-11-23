"""把 Kotlin 分类器的逻辑照搬一份，用来做本地快速验证。

真正的判定跑在 Kotlin 里（AuditEvents.kt），这里只是把同一套规则
用 Python 再写一遍，方便在没装 Android SDK 的机器上先自查一遍
边界条件对不对。CI 上的 Kotlin 单测才是最终依据。
"""

SCREEN_INTERACTIVE = 'SCREEN_INTERACTIVE'
SCREEN_NON_INTERACTIVE = 'SCREEN_NON_INTERACTIVE'
USER_PRESENT = 'USER_PRESENT'
USER_UNLOCKED = 'USER_UNLOCKED'
ACTIVITY_STARTED = 'ACTIVITY_STARTED'
ACTIVITY_RESUMED = 'ACTIVITY_RESUMED'
ACTIVITY_PAUSED = 'ACTIVITY_PAUSED'
ACTIVITY_STOPPED = 'ACTIVITY_STOPPED'

IDLE_GAP_MS = 10 * 60 * 1000
SCREEN_WAKE_WINDOW_MS = 15 * 1000
DEDUPE_WINDOW_MS = 10 * 1000

LOCK_SCREEN_BACKGROUND_START = 'LOCK_SCREEN_BACKGROUND_START'
LOCK_SCREEN_RESUME = 'LOCK_SCREEN_RESUME'
FOCUS_STEAL = 'FOCUS_STEAL'
IDLE_SELF_LAUNCH = 'IDLE_SELF_LAUNCH'


def classify(events):
    out = []
    seen = set()
    foreground = None
    foreground_paused = False
    screen_on = True
    screen_on_at = 0
    saw_screen_on = False
    unlocked_after_screen_on = False
    last_user_active_at = 0

    def is_idle(ts):
        return last_user_active_at == 0 or ts - last_user_active_at >= IDLE_GAP_MS

    def add(kind, pkg, ts, detail):
        key = (pkg, kind, ts // DEDUPE_WINDOW_MS)
        if key in seen:
            return
        seen.add(key)
        out.append((kind, pkg, ts, detail))

    for kind, pkg, ts in sorted(events, key=lambda e: e[2]):
        if kind == SCREEN_INTERACTIVE:
            screen_on = True
            screen_on_at = ts
            saw_screen_on = True
            unlocked_after_screen_on = False
            last_user_active_at = ts
        elif kind == SCREEN_NON_INTERACTIVE:
            screen_on = False
        elif kind in (USER_PRESENT, USER_UNLOCKED):
            unlocked_after_screen_on = True
            last_user_active_at = ts
        elif kind in (ACTIVITY_PAUSED, ACTIVITY_STOPPED):
            if pkg == foreground:
                foreground_paused = True
        elif kind == ACTIVITY_STARTED:
            fg = foreground
            if fg is not None and pkg != fg:
                if not screen_on:
                    add(LOCK_SCREEN_BACKGROUND_START, pkg, ts, '')
                elif not foreground_paused:
                    add(FOCUS_STEAL, pkg, ts, '')
        elif kind == ACTIVITY_RESUMED:
            fg = foreground
            if pkg != fg:
                woke_screen = (
                    screen_on
                    and not unlocked_after_screen_on
                    and saw_screen_on
                    and ts - screen_on_at <= SCREEN_WAKE_WINDOW_MS
                )
                if woke_screen:
                    add(LOCK_SCREEN_RESUME, pkg, ts, '')
                elif fg is None:
                    pass
                elif not foreground_paused:
                    add(FOCUS_STEAL, pkg, ts, '')
                elif is_idle(ts):
                    add(IDLE_SELF_LAUNCH, pkg, ts, '')
            foreground = pkg
            foreground_paused = False
    return out


def background_millis(events, end):
    out = {}
    in_background = set()
    foreground = None
    screen_on = True
    screen_on_since = 0

    def close_screen_on(at):
        if not screen_on:
            return
        duration = at - screen_on_since
        if duration <= 0:
            return
        for pkg in in_background:
            out[pkg] = out.get(pkg, 0) + duration

    for kind, pkg, ts in sorted(events, key=lambda e: e[2]):
        if kind == SCREEN_INTERACTIVE:
            screen_on = True
            screen_on_since = ts
        elif kind == SCREEN_NON_INTERACTIVE:
            close_screen_on(ts)
            screen_on = False
        elif kind == ACTIVITY_RESUMED:
            previous = foreground
            if previous is not None and previous != pkg:
                in_background.add(previous)
            in_background.discard(pkg)
            foreground = pkg
        elif kind in (ACTIVITY_PAUSED, ACTIVITY_STOPPED):
            if pkg == foreground:
                in_background.add(pkg)
                foreground = None
    close_screen_on(end)
    return out


def check(name, condition):
    print(('PASS  ' if condition else 'FAIL  ') + name)
    return condition


ok = True
ok &= check('息屏时别的 App 启动后台任务会被记为硬证据', classify([
    (ACTIVITY_RESUMED, 'com.a', 1000),
    (ACTIVITY_PAUSED, 'com.a', 1500),
    (SCREEN_NON_INTERACTIVE, 'system', 2000),
    (ACTIVITY_STARTED, 'com.sneaky', 3000),
]) == [(LOCK_SCREEN_BACKGROUND_START, 'com.sneaky', 3000, '')])

ok &= check('屏幕刚亮还没解锁就把界面拉到前台算硬证据', classify([
    (SCREEN_INTERACTIVE, 'system', 0),
    (ACTIVITY_RESUMED, 'com.sneaky', 5000),
]) == [(LOCK_SCREEN_RESUME, 'com.sneaky', 5000, '')])

ok &= check('上一个 App 还没退到后台就叠上来算抢焦点', classify([
    (SCREEN_INTERACTIVE, 'system', 0),
    (USER_PRESENT, 'system', 1000),
    (ACTIVITY_RESUMED, 'com.a', 2000),
    (ACTIVITY_RESUMED, 'com.b', 3000),
]) == [(FOCUS_STEAL, 'com.b', 3000, '')])

ok &= check('用户正常切换 App 不产生任何证据', classify([
    (SCREEN_INTERACTIVE, 'system', 0),
    (USER_PRESENT, 'system', 1000),
    (ACTIVITY_RESUMED, 'com.a', 2000),
    (ACTIVITY_PAUSED, 'com.a', 2500),
    (ACTIVITY_RESUMED, 'com.b', 3000),
]) == [])

ok &= check('长时间没人操作却自己弹到前台只算线索', classify([
    (SCREEN_INTERACTIVE, 'system', 0),
    (USER_PRESENT, 'system', 1000),
    (ACTIVITY_RESUMED, 'com.a', 2000),
    (ACTIVITY_PAUSED, 'com.a', 2500),
    (ACTIVITY_RESUMED, 'com.b', 20 * 60 * 1000 + 3000),
]) == [(IDLE_SELF_LAUNCH, 'com.b', 20 * 60 * 1000 + 3000, '')])

ok &= check('10 秒内重复上报只记一条', len(classify([
    (SCREEN_INTERACTIVE, 'system', 0),
    (ACTIVITY_RESUMED, 'com.sneaky', 3000),
    (ACTIVITY_RESUMED, 'com.sneaky', 4000),
    (ACTIVITY_RESUMED, 'com.sneaky', 5000),
])) == 1)

ok &= check('用户刚解锁两分钟内切换 App 不算闲置自启', classify([
    (SCREEN_INTERACTIVE, 'system', 0),
    (USER_PRESENT, 'system', 1000),
    (ACTIVITY_RESUMED, 'com.a', 2000),
    (ACTIVITY_PAUSED, 'com.a', 2500),
    (ACTIVITY_RESUMED, 'com.b', 2 * 60 * 1000 + 3000),
]) == [])

ok &= check('事件乱序时也能正确分类', classify([
    (ACTIVITY_RESUMED, 'com.b', 3000),
    (ACTIVITY_RESUMED, 'com.a', 2000),
    (USER_PRESENT, 'system', 1000),
    (SCREEN_INTERACTIVE, 'system', 0),
]) == [(FOCUS_STEAL, 'com.b', 3000, '')])

ok &= check('亮屏期间在后台的时间要算进去', background_millis([
    (SCREEN_INTERACTIVE, 'system', 0),
    (ACTIVITY_RESUMED, 'com.a', 1000),
    (ACTIVITY_PAUSED, 'com.a', 2000),
    (SCREEN_NON_INTERACTIVE, 'system', 3000),
    (SCREEN_INTERACTIVE, 'system', 10000),
], 20000).get('com.a') == 13000)

ok &= check('息屏那段时间不算后台时长', background_millis([
    (SCREEN_INTERACTIVE, 'system', 0),
    (ACTIVITY_RESUMED, 'com.a', 1000),
    (ACTIVITY_PAUSED, 'com.a', 2000),
    (SCREEN_NON_INTERACTIVE, 'system', 3000),
], 100000).get('com.a') == 3000)

ok &= check('在前台的时间不算后台时间', background_millis([
    (SCREEN_INTERACTIVE, 'system', 0),
    (ACTIVITY_RESUMED, 'com.a', 1000),
], 20000).get('com.a') is None)

print('ALL PASS' if ok else 'SOME FAILED')
raise SystemExit(0 if ok else 1)
