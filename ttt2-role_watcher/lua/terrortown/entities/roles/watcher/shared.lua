if SERVER then
  AddCSLuaFile()
end

function ROLE:PreInitialize()
  self.color = Color(95, 180, 140, 255)
  self.abbr = "wtch"
  self.icon = "vgui/ttt/dynamic/roles/icon_inno"
  self.defaultTeam = TEAM_INNOCENT
  self.isPublicRole = false
  self.isPolicingRole = false
  self.unknownTeam = true
  self.isOmniscientRole = false
  self.score.killsMultiplier = 2
  self.score.teamKillsMultiplier = -8

  self.conVarData = {
    pct = 0.15,
    maximum = 1,
    minPlayers = 6,
    credits = 0,
    shopFallback = SHOP_DISABLED,
    togglable = true,
    random = 33
  }
end

function ROLE:Initialize()
  roles.SetBaseRole(self, ROLE_INNOCENT)
end

if SERVER then
  function ROLE:GiveRoleLoadout(ply, isRoleChange)
    WATCHER_ROLE.QueueLoadout(ply)
  end

  function ROLE:RemoveRoleLoadout(ply, isRoleChange)
    -- TTT2 calls both loadout methods even when SetRole assigns the same role.
    if isRoleChange and WATCHER_ROLE.IsWatcher(ply) then return end

    WATCHER_ROLE.ClearState(ply)
    WATCHER_ROLE.RemoveLoadout(ply, isRoleChange)
  end
end
