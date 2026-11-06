# Watcher (TTT2)

An Innocent subrole with the normal Innocent health, movement, model, weapons and win condition. Requires TTT2; there is no dependency on Barclay or Bigfoot.

The normal Holstered tool is replaced by **Watcher's Stare**, in the same slot and with the same empty-handed appearance. Hold primary attack while aiming at or just beside a living player for 2 seconds to track them. A tiny 0.2-degree margin around the player's body accepts small aim errors at different distances. Direct hits take priority; otherwise the visible player closest to the crosshair is selected. Walls still block acquisition. Progress drains at one sixth of a full bar per second when you look away, release primary attack or switch weapons, taking six seconds to empty a full bar. Keep primary attack held to resume staring automatically when your aim returns, even after progress has fully drained. Aiming at a different player starts a fresh bar. The HUD shows the progress bar and "Staring at [Name] [Number]%" while a stare is in progress.

The tracked player gets a red outline visible through walls and across the map, using the same halo and PVS approach as Barclay's Woman Finder. Tracking persists with other weapons equipped. Completing another stare replaces the old target; partial progress leaves the old track intact. Death, spectating, losing the Watcher role and round cleanup stop the ability. A target who dies or disconnects loses their track, including if subsequently revived.

Default selection settings follow Bigfoot: at most one Watcher, a minimum of six players, a proportion of 0.15, no starting credits and no shop fallback. Use TTT2's role settings to change selection settings.

## Verification

Run the Lua behavior harness with a Lua 5.1+ interpreter from the addon directory:

```text
lua tests/watcher_behavior_tests.lua
```

In a TTT2 multiplayer round, verify:

1. A Watcher retains their crowbar, magneto-stick and normal gun pickups, with Stare replacing Holstered. Other roles keep Holstered.
2. Holding primary attack over or slightly beside a player fills the bar in 2 seconds. Check the aiming margin both nearby and far away, including beside cover: walls must block hidden players. Missed aim or released primary attack drains the bar at one sixth of a full bar per second. While holding the same click, look away and back before and after the bar empties: staring must resume without another click. Changing the aimed-at player starts fresh progress.
3. Completion reveals only that player's red outline. Check behind walls and at opposite ends of the map, then switch to a gun and verify tracking continues. Other players should see no outline and a normal holstered Watcher while Stare is equipped.
4. Starting a second stare retains the first outline until completion, then swaps it. Two Watchers should track independently.
5. Watcher death, silent death, spectating, role change and round end remove the outline and progress. Tracked-player death or disconnect also clears that target; revival does not restore the old track.
6. Starting another round or respawning gives the appropriate tool with no previous track. Changing away from Watcher restores Holstered.

The automated harness uses mocked engine APIs. Multiplayer rendering, weapon selection and networking still require the in-game checks above.
