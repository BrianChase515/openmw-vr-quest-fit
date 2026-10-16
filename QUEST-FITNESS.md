# Morrowind VR Fitness (OpenMW-VR on Meta Quest)

Play Morrowind standalone on a Meta Quest 3 and get a workout doing it: walk and jog in place
to move, throw real punches, slip and squat under enemy attacks, swim with a breaststroke,
and lie down to rest.

Built on [OpenMW-VR for Quest](https://github.com/tomups/openmw-vr-quest) (OpenMW 0.51 + VR).
You need your own copy of Morrowind (Steam or GOG, ideally with Tribunal and Bloodmoon).

## Setup (Windows PC, about 10 minutes)

1. **Quest in developer mode**, USB debugging allowed, and [SideQuest](https://sidequestvr.com)
   installed on the PC (the installer uses SideQuest's `adb`).
2. **Morrowind installed** on the PC. The installer looks in the usual Steam / GOG folders on
   drives C-H; if it can't find it, it asks you to paste the path of the `Data Files` folder once.
3. Download **[install-to-quest.bat](https://github.com/BrianChase515/openmw-vr-quest-fit/raw/apk/install-to-quest.bat)**
   and double-click it with the Quest plugged in and on your head (or nearby to accept prompts).

The installer downloads the newest game build and fitness scripts, installs them, copies your
Morrowind data to the Quest (first time only, ~600 MB), and launches the game. Once the game is
up you can unplug. When you're done, plug back in and press a key: it saves logs, any headset
screenshots and a backup of your saves to `Documents\openmw-fitness`.

Run the same file again any time to update. Saves live in the Quest's `Morrowind/userdata`
folder, so updates never touch them.

## How you play

| Do this | Happens in game |
|---|---|
| Walk in place | Walk forward. Your pace sets the speed |
| Jog in place (about 2+ steps a second) | Run |
| Jump | Jump |
| Squat down | Sneak (if Physical Sneak is on in the VR settings) |
| Throw a punch with either hand | Fists come up automatically; real punches land, arm swings don't |
| Mix punch types and hands (L JAB > R JAB > L HOOK) | Combo multiplier, up to x1.8. Same punch 3 times = stale |
| Enemy winds up: screen says SQUAT / SLIP LEFT / SLIP RIGHT | Do it to dodge (green flash) or soften the hit |
| Breaststroke in water (both hands from chest, push forward together) | Swim forward |
| Lie down on the floor for 2 seconds | Opens the Rest window |
| Thumbstick | Always works and overrides everything (turning, strafing, backing up) |

The HUD shows your health / magicka / fatigue bars, the enemy you're fighting at the top, and
your punches, combos and dodge calls in the middle of your view.

Safety: clear a big play area, use wrist straps, and remember jogging in place tends to creep
forward.

## Tuning

Everything adjustable is in `fitness-mod/scripts/fitness/config.lua` (punch strictness, combo
values, dodge chances, HUD layout, drift warning for small rooms). Movement feel is at the top of
`locomotion.lua`.

## For developers

* Fitness gameplay: Lua scripts in `fitness-mod/` (loaded as `fitness.omwscripts`).
* Engine changes for VR fists (off-hand punches, punch-position gate, menu cooldown):
  `apps/openmw/mwvr/realisticcombat.*`, `apps/openmw/mwvr/vrinputmanager.*`.
* Every push to `main` builds the APK on GitHub Actions and publishes it, with the scripts and
  installer, to the `apk` branch. Script-only changes publish in about a minute without a rebuild.
