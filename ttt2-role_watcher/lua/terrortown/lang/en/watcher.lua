local L = LANG.GetLanguageTableReference("en")

L[WATCHER.name] = "Watcher"
L["info_popup_" .. WATCHER.name] = [[You are the Watcher! You win with the Innocents.
Select Watcher's Stare and hold primary attack while aiming at a player for 2 seconds.
Losing your aim drains progress. A tracked player has a red outline, even through walls.
Tracking another player replaces the previous target. Tracking ends when you die or the round ends.]]
L["body_found_" .. WATCHER.abbr] = "They were a Watcher."
L["search_role_" .. WATCHER.abbr] = "This person was a Watcher!"
L["target_" .. WATCHER.name] = "Watcher"
L["ttt2_desc_" .. WATCHER.name] = [[The Watcher is an Innocent with a special holstered tool.
Hold primary attack on a visible player for 2 seconds to track their outline through walls.
Only one player can be tracked at a time. Tracking persists when switching weapons.]]

L.watcher_stare_name = "Watcher's Stare"
L.watcher_stare_progress = "Staring at"
