if SERVER then
  AddCSLuaFile()
end

WATCHER_ROLE = WATCHER_ROLE or {}
WATCHER_ROLE.STARE_CLASS = "weapon_ttt2_watcher_stare"
WATCHER_ROLE.STARE_TIME = 2 / 1.5
WATCHER_ROLE.DRAIN_TIME = 6
WATCHER_ROLE.AIM_TOLERANCE = 0.2 -- Degrees beyond the player's bounding box.

local STARE_CLASS = WATCHER_ROLE.STARE_CLASS
local STARE_TIME = WATCHER_ROLE.STARE_TIME
local DRAIN_TIME = WATCHER_ROLE.DRAIN_TIME
local AIM_TOLERANCE_SQUARED = math.tan(math.rad(WATCHER_ROLE.AIM_TOLERANCE)) ^ 2
local STARE_RANGE = 32768
local STATE_MESSAGE = "ttt2_watcher_state"

function WATCHER_ROLE.IsWatcher(ply)
  return IsValid(ply) and ply:IsPlayer() and ROLE_WATCHER ~= nil
    and ply:GetSubRole() == ROLE_WATCHER
end

function WATCHER_ROLE.IsLivingPlayer(ply)
  return IsValid(ply) and ply:IsPlayer() and ply:Alive() and not ply:IsSpec()
end

function WATCHER_ROLE.IsActiveWatcher(ply)
  return GetRoundState() == ROUND_ACTIVE and WATCHER_ROLE.IsWatcher(ply)
    and WATCHER_ROLE.IsLivingPlayer(ply)
end

if SERVER then
  util.AddNetworkString(STATE_MESSAGE)

  -- Nothing about a Watcher's target or progress is broadcast to other players.
  local states = {}

  local function loadoutTimerName(ply)
    return "ttt2_watcher_loadout_" .. ply:EntIndex()
  end

  local function sendState(ply, state)
    net.Start(STATE_MESSAGE)
    net.WriteEntity(state and state.tracked or NULL)
    net.WriteEntity(state and state.focus or NULL)
    net.WriteFloat(state and state.progress / STARE_TIME or 0)
    net.Send(ply)

    if state then
      state.sentTracked = state.tracked
      state.sentFocus = state.focus
      state.sentProgress = state.progress
      state.nextSend = CurTime() + 0.1
    end
  end

  function WATCHER_ROLE.ClearState(ply)
    if states[ply] and IsValid(ply) then
      sendState(ply)
    end

    states[ply] = nil

    if IsValid(ply) then
      timer.Remove(loadoutTimerName(ply))
    end
  end

  local function giveLoadout(ply)
    local active = ply:GetActiveWeapon()
    local selectStare = not IsValid(active) or active:GetClass() == "weapon_ttt_unarmed"

    -- Leave the crowbar, magneto-stick, guns, ammo and player model untouched.
    ply:StripWeapon("weapon_ttt_unarmed")

    if not ply:HasWeapon(STARE_CLASS) then
      ply:Give(STARE_CLASS)
    end

    if not ply:HasWeapon(STARE_CLASS) then return false end

    if selectStare then
      ply:SelectWeapon(STARE_CLASS)
    end

    return true
  end

  function WATCHER_ROLE.QueueLoadout(ply)
    if not IsValid(ply) then return end

    local timerName = loadoutTimerName(ply)
    local attempts = 0

    -- Role changes and the default loadout can run in the same tick. Replace
    -- holstered afterwards, and retry if the engine fails to give the weapon.
    timer.Create(timerName, 0.1, 10, function()
      if not WATCHER_ROLE.IsWatcher(ply) or not WATCHER_ROLE.IsLivingPlayer(ply) then
        timer.Remove(timerName)
        return
      end

      attempts = attempts + 1

      if giveLoadout(ply) or attempts >= 10 then
        timer.Remove(timerName)
      end
    end)
  end

  function WATCHER_ROLE.RemoveLoadout(ply, restoreHolstered)
    if not IsValid(ply) then return end

    local active = ply:GetActiveWeapon()
    local wasSelected = IsValid(active) and active:GetClass() == STARE_CLASS
    ply:StripWeapon(STARE_CLASS)

    if restoreHolstered and WATCHER_ROLE.IsLivingPlayer(ply) then
      ply:Give("weapon_ttt_unarmed")

      if wasSelected then
        ply:SelectWeapon("weapon_ttt_unarmed")
      end
    end
  end

  hook.Add("TTT2ModifyDefaultLoadout", "ttt2_watcher_replace_holstered", function(loadouts, role)
    if ROLE_WATCHER == nil or role ~= ROLE_WATCHER then return end

    local loadout = loadouts[role]
    if not loadout then return end

    -- This hook also runs for items. Only change an actual unarmed entry.
    for i = 1, #loadout do
      if loadout[i] == "weapon_ttt_unarmed" then
        loadout[i] = STARE_CLASS
      end
    end
  end)

  hook.Add("WeaponEquip", "ttt2_watcher_replace_added_holstered", function(wep, ply)
    if IsValid(wep) and wep:GetClass() == "weapon_ttt_unarmed" and WATCHER_ROLE.IsWatcher(ply) then
      WATCHER_ROLE.QueueLoadout(ply)
    end
  end)

  hook.Add("PlayerCanPickupWeapon", "ttt2_watcher_restrict_stare", function(ply, wep)
    if IsValid(wep) and wep:GetClass() == STARE_CLASS and not WATCHER_ROLE.IsWatcher(ply) then
      return false
    end
  end)

  local function canSeeTarget(ply, target, origin, point)
    local trace = util.TraceLine({
      start = origin,
      endpos = point,
      filter = ply,
      mask = MASK_SHOT
    })

    return not trace.Hit or trace.Entity == target
  end

  local function getStareTarget(ply)
    local active = ply:GetActiveWeapon()
    if not IsValid(active) or active:GetClass() ~= STARE_CLASS or not ply:KeyDown(IN_ATTACK) then return end

    local origin = ply:GetShootPos()
    local aim = ply:GetAimVector()
    local trace = util.TraceLine({
      start = origin,
      endpos = origin + aim * STARE_RANGE,
      filter = ply,
      mask = MASK_SHOT
    })

    local target = trace.Entity
    if target ~= ply and WATCHER_ROLE.IsLivingPlayer(target) then
      return target
    end

    -- Prefer a direct hit. Otherwise allow a small angular margin around the
    -- body, so the forgiveness stays consistent at different viewing distances.
    local bestTarget, bestMiss, bestDistance
    for _, candidate in ipairs(player.GetAll()) do
      if candidate ~= ply and WATCHER_ROLE.IsLivingPlayer(candidate) then
        local center = candidate:WorldSpaceCenter()
        local distance = (center - origin):Dot(aim)

        if distance > 0 and distance <= STARE_RANGE then
          local nearest = candidate:NearestPoint(origin + aim * distance)
          local offset = nearest - origin
          local along = offset:Dot(aim)

          if along > 0 then
            local miss = math.max(0, offset:LengthSqr() - along * along) / (along * along)
            local closer = not bestTarget or miss < bestMiss
              or (miss == bestMiss and distance < bestDistance)

            if miss <= AIM_TOLERANCE_SQUARED and closer
              and (canSeeTarget(ply, candidate, origin, center)
                or canSeeTarget(ply, candidate, origin, candidate:EyePos())) then
              bestTarget, bestMiss, bestDistance = candidate, miss, distance
            end
          end
        end
      end
    end

    return bestTarget
  end

  hook.Add("Think", "ttt2_watcher_update_stare", function()
    local now = CurTime()

    for ply, state in pairs(states) do
      if not WATCHER_ROLE.IsActiveWatcher(ply) then
        WATCHER_ROLE.ClearState(ply)
      else
        local delta = math.Clamp(now - state.lastUpdate, 0, 0.1)
        state.lastUpdate = now

        if not WATCHER_ROLE.IsLivingPlayer(state.tracked) then
          state.tracked = nil
        end

        if state.focus and not WATCHER_ROLE.IsLivingPlayer(state.focus) then
          state.focus = nil
          state.progress = 0
        end

        local target = getStareTarget(ply)

        if target and target ~= state.tracked then
          -- Progress belongs to one player; it cannot be carried to another.
          if target ~= state.focus then
            state.focus = target
            state.progress = 0
          end

          state.progress = math.min(STARE_TIME, state.progress + delta)

          if state.progress >= STARE_TIME then
            state.tracked = target
            state.focus = nil
            state.progress = 0
          end
        else
          -- Missing, releasing primary attack or switching away drains more
          -- slowly than charging. An acquired track survives weapon switches.
          state.progress = math.max(0, state.progress - delta * STARE_TIME / DRAIN_TIME)

          if state.progress == 0 then
            state.focus = nil
          end
        end

        local targetChanged = state.tracked ~= state.sentTracked or state.focus ~= state.sentFocus
        if targetChanged or (now >= state.nextSend and state.progress ~= state.sentProgress) then
          sendState(ply, state)
        end
      end
    end
  end)

  local function startWatcher(ply)
    WATCHER_ROLE.ClearState(ply)
    if not WATCHER_ROLE.IsActiveWatcher(ply) then return end

    states[ply] = {progress = 0, lastUpdate = CurTime(), nextSend = 0}
    WATCHER_ROLE.QueueLoadout(ply)
  end

  hook.Add("TTTBeginRound", "ttt2_watcher_begin", function()
    for _, ply in ipairs(player.GetAll()) do
      startWatcher(ply)
    end
  end)

  hook.Add("TTT2UpdateSubrole", "ttt2_watcher_role_change", function(ply, oldRole, newRole)
    if ROLE_WATCHER ~= nil and (oldRole == ROLE_WATCHER or newRole == ROLE_WATCHER) then
      startWatcher(ply)
    end
  end)

  hook.Add("PlayerSpawn", "ttt2_watcher_spawn", function(ply)
    WATCHER_ROLE.ClearState(ply)

    -- The spectator state and role loadout may finish updating after this hook.
    timer.Simple(0, function()
      if IsValid(ply) then startWatcher(ply) end
    end)
  end)

  local function clearPlayer(ply)
    WATCHER_ROLE.ClearState(ply)

    for viewer, state in pairs(states) do
      if state.tracked == ply then state.tracked = nil end
      if state.focus == ply then
        state.focus = nil
        state.progress = 0
      end

      if IsValid(viewer) then sendState(viewer, state) end
    end
  end

  hook.Add("PlayerDeath", "ttt2_watcher_death", clearPlayer)
  hook.Add("PlayerSilentDeath", "ttt2_watcher_silent_death", clearPlayer)
  hook.Add("PlayerDisconnected", "ttt2_watcher_disconnect", clearPlayer)

  local function clearRound()
    for _, ply in ipairs(player.GetAll()) do
      WATCHER_ROLE.ClearState(ply)
    end
  end

  hook.Add("TTTEndRound", "ttt2_watcher_end", clearRound)
  hook.Add("TTTPrepareRound", "ttt2_watcher_prepare", clearRound)

  hook.Add("SetupPlayerVisibility", "ttt2_watcher_target_pvs", function(viewer)
    local state = states[viewer]
    if not state or not WATCHER_ROLE.IsActiveWatcher(viewer) then return end

    if WATCHER_ROLE.IsLivingPlayer(state.tracked) then
      -- Like Barclay's finder, keep the actual player model available for halos
      -- even across map visleaves. Only the Watcher's single target is added.
      AddOriginToPVS(state.tracked:WorldSpaceCenter())
    end
  end)
end

if CLIENT then
  local tracked, focus
  local progress, displayedProgress = 0, 0
  local OUTLINE_COLOR = Color(255, 0, 0, 255)
  local BAR_COLOR = Color(95, 175, 160, 255)
  local BACKGROUND_COLOR = Color(15, 18, 22, 220)
  local TEXT_COLOR = Color(255, 255, 255, 255)

  local function clearState()
    tracked, focus = nil, nil
    progress, displayedProgress = 0, 0
  end

  net.Receive(STATE_MESSAGE, function()
    tracked = net.ReadEntity()
    local nextFocus = net.ReadEntity()
    progress = math.Clamp(net.ReadFloat(), 0, 1)

    if nextFocus ~= focus then displayedProgress = 0 end
    focus = nextFocus
  end)

  hook.Add("TTTEndRound", "ttt2_watcher_clear_end", clearState)
  hook.Add("TTTPrepareRound", "ttt2_watcher_clear_prepare", clearState)

  hook.Add("Think", "ttt2_watcher_clear_inactive", function()
    if not WATCHER_ROLE.IsActiveWatcher(LocalPlayer()) then
      clearState()
    end
  end)

  hook.Add("PreDrawHalos", "ttt2_watcher_outline", function()
    if not WATCHER_ROLE.IsActiveWatcher(LocalPlayer()) then return end
    if not WATCHER_ROLE.IsLivingPlayer(tracked) then return end

    halo.Add({tracked}, OUTLINE_COLOR, 2, 2, 1, true, true)
  end)

  function WATCHER_ROLE.DrawStareHUD()
    if not WATCHER_ROLE.IsActiveWatcher(LocalPlayer()) then return end
    if not IsValid(focus) or progress <= 0 then return end

    local centerX, top = ScrW() * 0.5, ScrH() * 0.5 + 48
    displayedProgress = Lerp(math.Clamp(FrameTime() * 20, 0, 1), displayedProgress, progress)
    local width, height = math.min(280, ScrW() * 0.4), 16
    local left = centerX - width * 0.5
    draw.RoundedBox(4, left - 2, top - 2, width + 4, height + 4, BACKGROUND_COLOR)
    draw.RoundedBox(3, left, top, width * displayedProgress, height, BAR_COLOR)
    local label = LANG.GetTranslation("watcher_stare_progress") .. " " .. math.floor(progress * 100) .. "%"
    top = top + height + 10

    draw.SimpleTextOutlined(label, "Trebuchet18", centerX, top, TEXT_COLOR,
      TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, BACKGROUND_COLOR)
  end
end
