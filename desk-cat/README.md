# DeskCat

A small macOS companion: a black cat peeking out of a yellow box with your cat's name on it.
It floats on your desktop, its eyes follow the pointer, and now and then it jumps out to explore.

Written in pure Swift + AppKit. There are no dependencies and no image assets; the cat is drawn in code.

## Run it

You need macOS 13+ and Xcode or the Command Line Tools (`xcode-select --install`).

```sh
cd desk-cat
swift run                    # quickest way to try it
./scripts/make-app.sh        # builds build/DeskCat.app (menu-bar only, ad-hoc signed)
```

On first launch it asks for a name. You can rename it any time from the 🐈‍⬛ menu-bar icon or by right-clicking the box.

## What it does

| You do | The cat does |
|---|---|
| Move the pointer | Eyes follow it; head tilts; pupils widen when you're close |
| Drag the box | The box moves, and the cat rides along |
| Click the cat in the box | It jumps out |
| Click the box | It plays peekaboo (ducks, then pops back up) |
| Swipe fast past the box | It ducks in, startled |
| Gently move the pointer over its head | You're petting it, so hearts appear |
| Move the pointer near it while it's out | It chases the pointer |
| Hold the pointer still near it | It crouches, wiggles, and **pounces** |
| Swipe fast right next to it | It gets spooked and runs back to the box |
| Drag the cat | You pick it up by the scruff. Drop it on the box to put it back |
| Click the box while it's out / menu "Call back" | It walks home and hops in |
| Leave the Mac alone | It gets bored, goes home and falls asleep (zZ) |

"Wander on its own" (on by default) lets it leave the box every few minutes while you're active.

## Viability notes

**Feasible on stock macOS, with no special permissions:**
- The pet windows are borderless, transparent `NSPanel`s at `.floating` level. They join all Spaces and show over full-screen apps. Clicks on transparent pixels fall through to the apps underneath.
- The panels are non-activating, so clicking the cat never steals keyboard focus from the app you're typing in.
- The pointer position comes from polling `NSEvent.mouseLocation`. This needs **no Accessibility or Input Monitoring permission**, so you get no scary prompts.
- Menu-bar only (`LSUIElement`): no Dock icon and no Cmd-Tab entry.
- It works inside the App Sandbox, so the Mac App Store is possible.

**Why it's lightweight:**
- A single 30 Hz timer, with a tolerance set so macOS can coalesce wake-ups.
- Each view keeps an `Equatable` state and redraws **only when something visible changed**. A cat dozing in its box with a still pointer does no drawing at all.
- Tiny windows (180×260 and 120×120 pt) drawn with Core Graphics. No SpriteKit, SwiftUI, WebView or image decoding.
- Expected footprint (estimate, not yet measured): a few hundred KB binary, ~20–30 MB RAM (the AppKit baseline), ~0% CPU when idle and around 1% while the cat runs around. Check it in Activity Monitor and Instruments on a real Mac.

**Not done yet / next steps:**
- **Art:** the vector cat imitates the logo. For a polished look, have a designer export sprite frames (walk, sit, pounce, sleep) as PDF/PNG and swap them into `CatView`.
- **Physics:** the cat walks freely in 2D. Possible next steps are walking along the Dock edge or the tops of windows. Window frames come from `CGWindowListCopyWindowInfo`; bounds don't need a permission.
- **Multiple monitors:** the cat roams the screen that holds the box.
- **Distribution:** to share outside your own Mac, sign with a Developer ID and notarize ($99/yr Apple Developer account), or ship it through the Mac App Store.
- Launch at login (`SMAppService.mainApp.register()`), sounds (purr/meow), and per-cat colours.

## Code map

| File | Role |
|---|---|
| `DeskCatApp.swift` | Entry point; sets the app as menu-bar only |
| `AppDelegate.swift` | Menu-bar icon, menu, rename dialog |
| `CatController.swift` | Timer loop, pointer tracking, and the cat's state machine (home → jump out → wander / chase / crouch → pounce / sit → go home) |
| `BoxView.swift` | Box, name, and the peeking cat; box dragging |
| `CatView.swift` | Roaming cat poses (walk, sit, crouch, leap, held); picking the cat up |
| `CatArt.swift` | Shared Core Graphics drawing: head, eyes, limbs, hearts |
| `PetWindow.swift` | Transparent, always-on-top, non-activating panel |
| `Settings.swift` | Name, box position, roaming toggle (UserDefaults) |
