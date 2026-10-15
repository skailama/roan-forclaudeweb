import AppKit

/// Owns the two windows (the box and the roaming cat) and runs the cat's little brain.
///
/// One 30 Hz timer drives everything. The pointer is read with `NSEvent.mouseLocation`,
/// which needs no Accessibility or Input Monitoring permission. Views only redraw when
/// their state actually changes, so a cat sitting in its box with a still pointer costs
/// nothing but the timer tick.
@MainActor
final class CatController: NSObject {
    private enum Mode {
        case home
        case jumpOut(from: CGPoint, to: CGPoint, t: CGFloat)
        case wander(to: CGPoint)
        case sit(left: CGFloat)
        case chase
        case crouch(left: CGFloat)
        case pounce(from: CGPoint, to: CGPoint, t: CGFloat)
        case goHome(speed: CGFloat)
        case jumpIn(from: CGPoint, t: CGFloat)
        case held
    }

    var menuProvider: (() -> NSMenu?)? {
        didSet {
            boxView.menuProvider = menuProvider
            catView.menuProvider = menuProvider
        }
    }

    var name: String {
        get { Settings.name ?? "kitty" }
        set {
            Settings.name = newValue
            boxView.state.name = newValue
        }
    }

    var isHome: Bool {
        if case .home = mode { return true }
        return false
    }

    private let boxWindow: PetWindow
    private let boxView: BoxView
    private let catWindow: PetWindow
    private let catView: CatView
    private var timer: Timer?
    private var mode: Mode = .home
    private var lastTick: Double = 0

    // Pointer
    private var mouse = CGPoint.zero
    private var mouseVelocity = CGVector.zero
    private var lastMouseMove: Double = 0

    // Cat while out of the box (positions are screen coordinates of its paws)
    private var feet = CGPoint.zero
    private var facingRight = true
    private var walkPhase: CGFloat = 0
    private var lastPlay: Double = 0
    private var boredAfter: Double = 120
    private var grabOffset = CGVector.zero
    private var dragged = false

    // Cat while in the box
    private var peek: CGFloat = 1
    private var tilt: CGFloat = -0.3
    private var duckUntil: Double = 0
    private var nextRoam: Double = 0

    // Shared
    private var blinkUntil: Double = 0
    private var nextBlink: Double = 0
    private var hearts: [Heart] = []
    private var heartCooldown: CGFloat = 0

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    override init() {
        boxView = BoxView(frame: NSRect(origin: .zero, size: BoxView.size))
        boxWindow = PetWindow.make(size: BoxView.size)
        catView = CatView(frame: NSRect(origin: .zero, size: CatView.size))
        catWindow = PetWindow.make(size: CatView.size)
        super.init()
        boxWindow.contentView = boxView
        catWindow.contentView = catView
        boxView.state.name = name
        boxView.onClick = { [weak self] point in self?.boxClicked(at: point) }
        boxView.onDragEnded = { [weak self] in self?.boxDragEnded() }
        catView.onPress = { [weak self] in self?.catPressed() }
        catView.onDrag = { [weak self] in self?.catDragged() }
        catView.onRelease = { [weak self] in self?.catReleased() }
    }

    func start() {
        let t = now
        lastTick = t
        mouse = NSEvent.mouseLocation
        lastMouseMove = t
        lastPlay = t
        nextBlink = t + 3
        nextRoam = t + Double.random(in: 60...180)
        placeBox()
        boxWindow.orderFrontRegardless()

        let timer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 1.0 / 120.0
        // .common keeps the cat animating while menus are open or the box is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Public actions

    func letOut() {
        guard isHome else { return }
        let o = boxWindow.frame.origin
        let from = CGPoint(x: o.x + BoxView.headCenter.x, y: o.y + BoxView.boxTop - 10)
        let rightX = o.x + BoxView.size.width + 50
        let to = CGPoint(x: rightX < screenBounds().maxX ? rightX : o.x - 50,
                         y: max(screenBounds().minY, o.y))
        feet = from
        hearts.removeAll()
        lastPlay = now
        boredAfter = Double.random(in: 90...200)
        mode = .jumpOut(from: from, to: to, t: 0)
        boxView.state.catHome = false
        boxView.state.hearts = []
        render(pose: .leap, excited: false, time: now, idle: 0)
        catWindow.orderFrontRegardless()
    }

    func callHome() {
        if case .home = mode { return }
        if case .jumpIn = mode { return }
        mode = .goHome(speed: 200)
    }

    func resetBoxPosition() {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        boxWindow.setFrameOrigin(CGPoint(x: frame.maxX - BoxView.size.width - 40, y: frame.minY + 20))
        Settings.boxOrigin = boxWindow.frame.origin
    }

    // MARK: Main loop

    @objc private func tick() {
        let time = now
        let dt = CGFloat(min(time - lastTick, 0.1))
        lastTick = time
        trackPointer(dt: dt, time: time)
        ageHearts(dt: dt)
        if time > nextBlink {
            blinkUntil = time + 0.14
            nextBlink = time + Double.random(in: 2.5...6)
        }
        if isHome {
            tickHome(dt: dt, time: time)
        } else {
            tickOut(dt: dt, time: time)
        }
    }

    private func trackPointer(dt: CGFloat, time: Double) {
        let m = NSEvent.mouseLocation
        let dx = m.x - mouse.x, dy = m.y - mouse.y
        if abs(dx) + abs(dy) > 0.5 { lastMouseMove = time }
        if dt > 0 {
            let k = min(1, dt * 12)
            mouseVelocity.dx += (dx / dt - mouseVelocity.dx) * k
            mouseVelocity.dy += (dy / dt - mouseVelocity.dy) * k
        }
        mouse = m
    }

    private var pointerSpeed: CGFloat { hypot(mouseVelocity.dx, mouseVelocity.dy) }

    // MARK: In the box

    private func tickHome(dt: CGFloat, time: Double) {
        let o = boxWindow.frame.origin
        let head = CGPoint(x: o.x + BoxView.headCenter.x, y: o.y + BoxView.headCenter.y)
        let v = CGVector(dx: mouse.x - head.x, dy: mouse.y - head.y)
        let dist = hypot(v.dx, v.dy)
        let idle = time - lastMouseMove

        // A fast swipe right past the box makes the cat duck.
        if dist < 160 && pointerSpeed > 2500 { duckUntil = time + 1.2 }
        let peekTarget: CGFloat = time < duckUntil ? 0 : 1
        peek = approach(peek, peekTarget, rate: peekTarget < peek ? 14 : 5, dt: dt)
        tilt = approach(tilt, -0.3 - clamped(v.dx / 800, -0.3, 0.2), rate: 6, dt: dt)

        // Gently moving the pointer over its head = petting.
        let petting = dist < 40 && peek > 0.9 && pointerSpeed > 20 && pointerSpeed < 900
        if petting {
            lastPlay = time
            addHeart(at: CGPoint(x: BoxView.headCenter.x + CGFloat.random(in: -14...14),
                                 y: BoxView.headCenter.y + 36))
        }

        var s = boxView.state
        s.catHome = true
        s.peek = peek
        s.tilt = tilt
        s.look = gaze(v, dist: dist)
        s.dilation = clamped((200 - dist) / 100, 0, 1)
        s.asleep = idle > 45
        s.eyesClosed = s.asleep || time < blinkUntil
        s.hearts = hearts
        boxView.state = s

        if Settings.roamsOnItsOwn && time > nextRoam && idle < 20 {
            letOut()
        }
    }

    private func boxClicked(at point: CGPoint) {
        if isHome {
            if point.y > BoxView.boxTop - 5 {
                letOut()
            } else {
                duckUntil = now + 0.5   // peekaboo
            }
        } else {
            callHome()
        }
    }

    private func boxDragEnded() {
        Settings.boxOrigin = boxWindow.frame.origin
    }

    // MARK: Out of the box

    private var isBusy: Bool {
        switch mode {
        case .home, .held, .jumpOut, .jumpIn, .pounce, .goHome: return true
        case .wander, .sit, .chase, .crouch: return false
        }
    }

    private func tickOut(dt: CGFloat, time: Double) {
        let d = hypot(mouse.x - feet.x, mouse.y - (feet.y + 35))
        let idle = time - lastMouseMove
        let pointerActive = idle < 1.0
        let speed = pointerSpeed
        let petting = d < 42 && speed > 20 && speed < 900
        var pose: CatPose = .sit
        var excited = false

        // Spooked by a fast swipe right next to it: bolt back to the box.
        if d < 140 && speed > 3500 && !isBusy {
            mode = .goHome(speed: 560)
        }

        switch mode {
        case .home:
            return

        case let .jumpOut(from, to, t):
            let nt = min(1, t + dt / 0.5)
            feet = arc(from, to, nt, height: 70)
            facingRight = to.x >= from.x
            pose = .leap
            mode = nt >= 1 ? .sit(left: 1.5) : .jumpOut(from: from, to: to, t: nt)

        case let .wander(to):
            pose = .walk
            if pointerActive && d > 70 && d < 280 {
                mode = .chase
            } else if !step(toward: to, speed: 110, dt: dt) {
                mode = .sit(left: CGFloat.random(in: 2...5))
            }

        case let .sit(left):
            var remaining = left - dt
            if petting {
                remaining = max(remaining, 2)
                lastPlay = time
                addHeart(at: heartSpawnPoint(for: .sit))
            }
            if d < 320 { face(mouse.x) }
            if pointerActive && d > 70 && d < 280 && !petting {
                mode = .chase
            } else if remaining <= 0 {
                let bored = time - lastPlay > boredAfter || idle > 30
                mode = bored ? .goHome(speed: 130) : .wander(to: randomSpot(near: feet))
            } else {
                mode = .sit(left: remaining)
            }

        case .chase:
            excited = true
            if !pointerActive {
                // Pointer went still nearby: get ready to pounce on it.
                mode = d > 50 && d < 110 ? .crouch(left: 0.6) : .sit(left: 3)
            } else if d > 420 {
                mode = .sit(left: 2)
            } else if d < 42 && speed < 900 {
                mode = .sit(left: 3)
            } else if d > 55 {
                pose = .walk
                step(toward: CGPoint(x: mouse.x, y: mouse.y - 35), speed: 260, dt: dt)
            } else {
                face(mouse.x)
            }

        case let .crouch(left):
            excited = true
            pose = .crouch
            walkPhase += dt * 30   // butt wiggle
            face(mouse.x)
            if pointerActive && d > 120 {
                mode = .chase
            } else if left - dt <= 0 {
                lastPlay = time
                mode = .pounce(from: feet, to: clampToScreen(CGPoint(x: mouse.x, y: mouse.y - 30)), t: 0)
            } else {
                mode = .crouch(left: left - dt)
            }

        case let .pounce(from, to, t):
            excited = true
            let nt = min(1, t + dt / 0.35)
            feet = arc(from, to, nt, height: 40)
            pose = .leap
            mode = nt >= 1 ? .sit(left: 2.5) : .pounce(from: from, to: to, t: nt)

        case let .goHome(speed):
            pose = .walk
            if !step(toward: homeApproachPoint(), speed: speed, dt: dt) {
                mode = .jumpIn(from: feet, t: 0)
            }

        case let .jumpIn(from, t):
            let nt = min(1, t + dt / 0.45)
            let to = homeDropPoint()
            feet = arc(from, to, nt, height: 60)
            facingRight = to.x >= from.x
            pose = .leap
            if nt >= 1 {
                arriveHome()
                return
            }
            mode = .jumpIn(from: from, t: nt)

        case .held:
            excited = true
            pose = .held
        }

        render(pose: pose, excited: excited, time: time, idle: idle)
    }

    private func render(pose: CatPose, excited: Bool, time: Double, idle: Double) {
        let origin = CGPoint(x: feet.x - CatView.feet.x, y: feet.y - CatView.feet.y)
        if catWindow.frame.origin != origin {
            catWindow.setFrameOrigin(origin)
        }
        let head = CatView.headPoint(for: pose, facingRight: facingRight)
        let v = CGVector(dx: mouse.x - (origin.x + head.x), dy: mouse.y - (origin.y + head.y))
        let dist = hypot(v.dx, v.dy)
        let dozing = pose == .sit && idle > 30

        var s = CatView.State()
        s.pose = pose
        s.facingRight = facingRight
        s.phase = walkPhase
        s.look = gaze(v, dist: dist)
        s.dilation = excited ? 1 : clamped((200 - dist) / 100, 0, 1)
        s.eyesClosed = dozing || time < blinkUntil
        s.tailSway = dozing ? 0 : sin(CGFloat(time) * 2.6) * 4
        s.hearts = hearts
        catView.state = s
    }

    private func arriveHome() {
        mode = .home
        catWindow.orderOut(nil)
        hearts.removeAll()
        peek = 0   // dives in, then pops back up
        nextRoam = now + Double.random(in: 180...480)
    }

    // MARK: Picking the cat up

    private func catPressed() {
        let m = NSEvent.mouseLocation
        grabOffset = CGVector(dx: m.x - feet.x, dy: m.y - feet.y)
        dragged = false
    }

    private func catDragged() {
        let m = NSEvent.mouseLocation
        if !dragged {
            guard hypot(m.x - feet.x - grabOffset.dx, m.y - feet.y - grabOffset.dy) > 3 else { return }
            guard !isBusy || isHeld else { return }
            dragged = true
            mode = .held
            // Hold it by the scruff: re-anchor so the head hangs from the pointer.
            grabOffset = CGVector(dx: 0, dy: 74)
        }
        feet = CGPoint(x: m.x - grabOffset.dx, y: m.y - grabOffset.dy)
    }

    private func catReleased() {
        if dragged {
            dragged = false
            let o = boxWindow.frame.origin
            let overBox = CGRect(x: o.x, y: o.y, width: BoxView.size.width, height: BoxView.boxTop + 30)
            if overBox.contains(NSEvent.mouseLocation) {
                mode = .jumpIn(from: feet, t: 0)
            } else {
                feet = clampToScreen(feet)
                mode = .sit(left: 3)
            }
        } else {
            // A plain click: happy cat.
            lastPlay = now
            let head = CatView.headPoint(for: catView.state.pose, facingRight: facingRight)
            for i in 0..<3 {
                addHeart(at: CGPoint(x: head.x - 12 + CGFloat(i) * 12, y: head.y + 18), force: true)
            }
            if !isBusy { mode = .sit(left: 3) }
        }
    }

    private var isHeld: Bool {
        if case .held = mode { return true }
        return false
    }

    // MARK: Helpers

    /// Moves the cat toward `target` (kept on screen). Returns false once it has arrived.
    @discardableResult
    private func step(toward target: CGPoint, speed: CGFloat, dt: CGFloat) -> Bool {
        let target = clampToScreen(target)
        let dx = target.x - feet.x, dy = target.y - feet.y
        let dist = hypot(dx, dy)
        if dist < 4 { return false }
        let s = min(dist, speed * dt)
        feet.x += dx / dist * s
        feet.y += dy / dist * s
        if abs(dx) > 2 { facingRight = dx > 0 }
        walkPhase += s * 0.12
        return true
    }

    private func face(_ x: CGFloat) {
        if abs(x - feet.x) > 8 { facingRight = x > feet.x }
    }

    private func arc(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t + sin(.pi * t) * height)
    }

    private func gaze(_ v: CGVector, dist: CGFloat) -> CGVector {
        guard dist > 1 else { return .zero }
        let reach = min(1, dist / 90)
        return CGVector(dx: v.dx / dist * reach, dy: v.dy / dist * reach)
    }

    private func homeDropPoint() -> CGPoint {
        let o = boxWindow.frame.origin
        return CGPoint(x: o.x + BoxView.headCenter.x, y: o.y + BoxView.boxTop - 10)
    }

    private func homeApproachPoint() -> CGPoint {
        let o = boxWindow.frame.origin
        let fromLeft = feet.x < o.x + BoxView.size.width / 2
        return CGPoint(x: fromLeft ? o.x - 30 : o.x + BoxView.size.width + 30, y: o.y)
    }

    private func heartSpawnPoint(for pose: CatPose) -> CGPoint {
        let head = CatView.headPoint(for: pose, facingRight: facingRight)
        return CGPoint(x: head.x + CGFloat.random(in: -10...10), y: head.y + 18)
    }

    private func addHeart(at point: CGPoint, force: Bool = false) {
        guard force || heartCooldown <= 0 else { return }
        heartCooldown = 0.3
        hearts.append(Heart(pos: point, age: 0))
        if hearts.count > 10 { hearts.removeFirst() }
    }

    private func ageHearts(dt: CGFloat) {
        heartCooldown -= dt
        guard !hearts.isEmpty else { return }
        for i in hearts.indices {
            hearts[i].age += dt
            hearts[i].pos.y += 18 * dt
        }
        hearts.removeAll { $0.age > Heart.lifetime }
    }

    /// The area the cat may roam: the visible part of the box's screen, keeping the cat fully on it.
    private func screenBounds() -> CGRect {
        let frame = (boxWindow.screen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGRect(x: frame.minX + 40, y: frame.minY, width: frame.width - 80, height: frame.height - 100)
    }

    private func clampToScreen(_ p: CGPoint) -> CGPoint {
        let b = screenBounds()
        return CGPoint(x: clamped(p.x, b.minX, b.maxX), y: clamped(p.y, b.minY, b.maxY))
    }

    private func randomSpot(near p: CGPoint) -> CGPoint {
        clampToScreen(CGPoint(x: p.x + CGFloat.random(in: -400...400), y: p.y + CGFloat.random(in: -250...250)))
    }

    private func placeBox() {
        if let saved = Settings.boxOrigin,
           NSScreen.screens.contains(where: { $0.frame.contains(CGPoint(x: saved.x + 90, y: saved.y + 60)) }) {
            boxWindow.setFrameOrigin(saved)
        } else {
            resetBoxPosition()
        }
    }
}

private func clamped(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
    min(max(value, low), high)
}

/// Eases `value` toward `target`, snapping when close so idle frames compare equal and skip redraws.
private func approach(_ value: CGFloat, _ target: CGFloat, rate: CGFloat, dt: CGFloat) -> CGFloat {
    let next = value + (target - value) * min(1, rate * dt)
    return abs(target - next) < 0.002 ? target : next
}
