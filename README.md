# Morrowind VR Fitness — work out in Vvardenfell on Meta Quest

**Play The Elder Scrolls III: Morrowind standalone on a Meta Quest 3, and move your body to play it.**
Walk and jog in place to travel, throw real punches with both fists, squat and slip under enemy
attacks, swim with a breaststroke, lie down to rest — with a workout tracker counting your steps,
punches and calories. Level up Athletics by actually running.

**Based on [tomups' native Quest port](https://github.com/tomups/openmw-vr-quest)** of
[OpenMW-VR](https://gitlab.com/madsbuvi/openmw) by Mads Buvik Sandvei, on the
[OpenMW](https://openmw.org) engine — their work makes this possible, and their full commit
history is kept in this repo. Free and open source (GPLv3).
**You need your own copy of Morrowind** — nothing from the game is included here.

> Hobby project, tested on one Quest 3. Expect rough edges; feedback and issues welcome.
> Not affiliated with Bethesda, Team Beef or the OpenMW team.

---

## What it does

| You do this | In the game |
|---|---|
| **Walk in place** | Walk forward; your pace sets the speed |
| **Jog in place** (about 2+ steps a second) | Run |
| **Jump** | Jump |
| **Throw a punch**, either hand — jab, cross, hook or uppercut, to the head or body | Fists come up on their own; real punches land (even on rats and mudcrabs at your feet), jogging arm swings don't |
| **Mix punches and hands** (L JAB › R CROSS › L HOOK › R UPPERCUT) | Combo multiplier up to ×1.8 damage; the same punch 3× in a row goes stale |
| **Enemy winds up** → screen calls **SQUAT!** / **SLIP LEFT** / **SLIP RIGHT** | Do it in time to dodge (green flash) or soften the hit. Enemy wind-ups are slowed so you can react |
| **Breaststroke** in water (hands from chest, push forward together) | Swim forward |
| **Lie down** on the floor for 2 seconds | Rest until healed |
| **Drop to half health in a fight** | Your own fight song kicks in (bring your own music — see below) |
| **Left trigger** (the old jump button) | Opens the full map — you jump for real |
| **Thumbstick** | Always works and overrides the body controls (turning, strafing, backing up) |

**Fitness HUD**, locked to your view:
- your **health / magicka / fatigue** bars, colour-coded green → yellow → red — shown while you're fighting
  (and 10 s after), when you lose health or magicka, and whenever health or fatigue is low
- the **direction you're facing** (N, NE, E…) in the upper right
- the **enemy you're fighting** (name, health, fatigue) across the top
- **every punch's type and speed**, graded green / yellow / red for that punch type (set your stance —
  orthodox or southpaw — in Options → Scripts → Fitness)
- **combos**, **dodge calls and results** in the middle

**Workout tracker:** open any menu (or pause) to see this session's and your **all-time** steps, jumps, squats,
punches, dodges and estimated calories at the bottom of your view.
All-time totals are kept on the Quest and also tucked into every save game, so a reinstall can't lose them.

Calories use the standard MET method (activity intensity × your resting burn from height,
weight, age and sex). Set your profile in **Options → Scripts → Fitness**.

**Comeback anthem:** put any song you own (.mp3 or .ogg) in `Documents\openmw-fitness\music`
and rerun the installer. When you're at half health or less in a fight it takes over from the
battle music, once per fight (several files = a random pick). No music is included with the mod.
Turn it off or change the health % in **Options → Scripts → Fitness**.

## See it in action

<!-- VIDEO: replace with your link, e.g. [![Watch the video](https://img.youtube.com/vi/VIDEO_ID/maxresdefault.jpg)](https://www.youtube.com/watch?v=VIDEO_ID) -->

## What you need

- **Meta Quest 3** (Quest 2 / Pro may work, untested) in **developer mode**
- A **Windows PC** with [SideQuest](https://sidequestvr.com) installed and a **USB cable**
- **Morrowind** installed on that PC (Steam or GOG; Game of the Year edition with Tribunal and Bloodmoon recommended)
- A **clear play area** — you will be jogging, jumping, punching and lying on the floor

## Install (about 10 minutes, then one click to update)

1. Put the Quest in developer mode (Meta Horizon phone app → Devices → Developer mode) and
   install SideQuest on the PC. Plug the Quest in and allow USB debugging when it asks.
2. Download **[install-to-quest.bat](https://raw.githubusercontent.com/BrianChase515/openmw-vr-quest-fit/apk/install-to-quest.bat)**
   (right-click → *Save link as*). Or skip the browser: press **Win + R**, paste this and press Enter
   (it downloads the installer to your Downloads folder and runs it):
   ```
   cmd /k "curl -L -o %USERPROFILE%\Downloads\install-to-quest.bat https://raw.githubusercontent.com/BrianChase515/openmw-vr-quest-fit/apk/install-to-quest.bat && %USERPROFILE%\Downloads\install-to-quest.bat"
   ```
3. Double-click it with the headset plugged in. It will:
   - find Morrowind (common Steam/GOG folders; otherwise it asks once for your `Data Files` folder)
   - download the newest game build and fitness scripts from this repo
   - install the app, copy your Morrowind data to the Quest (first time only, ~600 MB)
   - launch the game
4. Once the game is up, **unplug and play**. When done, plug back in and press a key in the window:
   it saves logs, any headset screenshots and a **backup of your saves** to `Documents\openmw-fitness`.

**Updating:** run the same file again. Your saves live in the Quest's `Morrowind/userdata` folder,
so updates and reinstalls never touch them.

## Tips

- **Recenter** (VR menu) if you're ever offset from your character; the mod also re-centres
  automatically if you wander more than 35 cm from your body in the game.
- **Physical sneak:** turn on *Physical Sneak* in the VR settings to crouch-sneak.
- **Hand-to-hand is your friend early on:** a committed punch always lands; damage grows with your skill.
- **Jogging in place creeps forward.** Check your Guardian now and then (or turn on the drift
  warning in `config.lua` for small rooms).
- **Screenshots:** hold the Meta button and pull a trigger; the installer copies them to your PC.

## Tuning

Everything adjustable is in [`fitness-mod/scripts/fitness/config.lua`](fitness-mod/scripts/fitness/config.lua):
punch strictness, combo values, dodge chances, HUD layout and visibility, the game's own wrist
HUD (hidden by default), re-centre distance. Movement feel (step sensitivity, run pace, jump,
swim, rest) is at the top of [`locomotion.lua`](fitness-mod/scripts/fitness/locomotion.lua).
To use your own edits, put them in `Documents\openmw-fitness\fitness-mod` and comment out the
"Downloading the latest fitness scripts" lines in the installer.

## Troubleshooting

| Problem | Fix |
|---|---|
| *"Quest not detected"* | Headset on, cable in, accept the USB debugging prompt inside the headset |
| *"Could not find adb"* | Open SideQuest once (it installs adb), then rerun |
| Game opens and closes instantly | Rerun the installer; check `Documents\openmw-fitness\openmw-log.txt` for "No content file" (Morrowind data missing) |
| *INSTALL_FAILED_UPDATE_INCOMPATIBLE* | You have an older/different build installed; answer **Y** — saves are backed up first |
| Ghosting / judder | The game runs below the headset's refresh rate in busy areas; lower view distance in Options → Video |
| Walking won't start | Step a little more firmly; light steps need a steady rhythm to register |

---

## How it works (for developers)

```
fitness-mod/                 Lua gameplay mod (fitness.omwscripts), no rebuild needed to change
  scripts/fitness/
    locomotion.lua           walk/jog/jump from head bob, breaststroke swimming, lie-down rest
    punch.lua                fist tracking, punch classification, L/R combos
    dodge.lua                attack calls, squat/slip dodge judging
    target.lua               (on every NPC/creature) wind-up telegraph + slowdown, hit rules, enemy status
    coach.lua                the view-locked fitness HUD
    anthem.lua               plays your song when you're hurt in a fight
    tracker.lua              steps / jumps / squats / punches / calories, profile settings
    align.lua  hud.lua       keep you lined up with your character; manage the game's wrist HUD
apps/openmw/mwvr/            engine changes: off-hand fist, punch-position gate, menu cooldown
android/                     Quest build (cross-compiles engine + deps, packages the APK)
tools/install-to-quest.bat   the installer
```

Every push to `main` builds the APK on GitHub Actions and publishes it — with the scripts,
installer and this guide — to the [`apk`](https://github.com/BrianChase515/openmw-vr-quest-fit/tree/apk)
branch. Script-only changes publish in about a minute without rebuilding the engine.

### Building it yourself

```sh
cd android/buildscripts
./build.sh            # downloads the NDK, builds deps + libopenmw.so, deploys into app/
cd ..
ANDROID_HOME=$HOME/Android/Sdk ./gradlew :app:assembleDebug
```

`build.sh` keeps unstripped libs in `buildscripts/symbols/arm64-v8a/` for symbolizing tombstones.
Watch startup with `adb logcat -s OpenMW SDL openxr VrApi DEBUG`.

## Credits

- [OpenMW](https://openmw.org) — the open-source Morrowind engine (GPLv3)
- [Mads Buvik Sandvei](https://gitlab.com/madsbuvi/openmw) — OpenMW-VR
- [tomups](https://github.com/tomups/openmw-vr-quest) — the native Meta Quest port this builds on
- [xyzz/openmw-android](https://github.com/xyzz/openmw-android) — Android build scripts
- Fitness mod by Brian Chase, built with Claude

The Elder Scrolls III: Morrowind is © Bethesda Softworks. You must own the game to play.
