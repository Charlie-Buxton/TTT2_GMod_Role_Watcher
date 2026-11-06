-- Run from the addon root with Lua 5.1+, including LuaJIT.
SERVER, CLIENT = true, false
ROLE_INNOCENT, ROLE_WATCHER = 0, 20
TEAM_INNOCENT, SHOP_DISABLED = "innocent", -1
ROUND_PREP, ROUND_ACTIVE, ROUND_POST = 1, 2, 3
WEAPON_UNARMED, IN_ATTACK, MASK_SHOT = 0, 1, 1174421507
TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP = 1, 3
NULL = {valid = false}

local now, roundState = 0, ROUND_PREP
local players, messages, timers, callbacks = {}, {}, {}, {}
local lastTrace, pvs, halos, drawings = nil, {}, {}, {}
local localPlayer, incoming, outgoing
local simpleTimerId, passed = 0, 0

function IsValid(entity) return type(entity) == "table" and entity.valid == true end
function CurTime() return now end
function GetRoundState() return roundState end
function AddCSLuaFile() end
function Color(r, g, b, a) return {r = r, g = g, b = b, a = a} end
function AddOriginToPVS(origin) pvs[#pvs + 1] = origin end
function LocalPlayer() return localPlayer end
function ScrW() return 1920 end
function ScrH() return 1080 end
function FrameTime() return 1 / 60 end
function Lerp(fraction, a, b) return a + (b - a) * fraction end
function math.Clamp(value, low, high) return math.max(low, math.min(high, value)) end

local vectorMeta = {}
vectorMeta.__index = vectorMeta
local function vector(x, y, z)
  return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vectorMeta)
end
vectorMeta.__add = function(a, b) return vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vectorMeta.__sub = function(a, b) return vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vectorMeta.__mul = function(a, b) return vector(a.x * b, a.y * b, a.z * b) end
function vectorMeta:Dot(other) return self.x * other.x + self.y * other.y + self.z * other.z end
function vectorMeta:LengthSqr() return self:Dot(self) end
local function sameVector(a, b) return (a - b):LengthSqr() < 0.000001 end

hook = {}
function hook.Add(event, id, callback)
  callbacks[event] = callbacks[event] or {}
  callbacks[event][id] = callback
end
function hook.Run(event, ...)
  for _, callback in pairs(callbacks[event] or {}) do
    local result = callback(...)
    if result ~= nil then return result end
  end
end

timer = {}
function timer.Create(id, delay, repetitions, callback)
  timers[id] = {at = now + delay, delay = delay, left = repetitions, callback = callback}
end
function timer.Remove(id) timers[id] = nil end
function timer.Simple(delay, callback)
  simpleTimerId = simpleTimerId + 1
  timer.Create("simple_" .. simpleTimerId, delay, 1, callback)
end

player = {GetAll = function() return players end}
util = {AddNetworkString = function() end}
function util.TraceLine(request)
  lastTrace = request
  for _, candidate in ipairs(players) do
    if candidate ~= request.filter and IsValid(candidate) then
      local isCenter = sameVector(request.endpos, candidate:WorldSpaceCenter())
      if isCenter or sameVector(request.endpos, candidate:EyePos()) then
        if candidate.hidden or (candidate.centerBlocked and isCenter) then
          return {Hit = true, Entity = NULL}
        end
        return {Hit = true, Entity = candidate}
      end
    end
  end
  local entity = request.filter.lookingAt or NULL
  return {Entity = entity, Hit = IsValid(entity)}
end

net = {receivers = {}}
function net.Start(name) outgoing = {name = name} end
function net.WriteEntity(entity) outgoing[#outgoing + 1] = entity end
function net.WriteFloat(value) outgoing[#outgoing + 1] = value end
function net.Send(recipient)
  assert(IsValid(recipient) and recipient:IsPlayer(), "state must have one explicit player recipient")
  messages[recipient] = outgoing
end
function net.Receive(name, callback) net.receivers[name] = callback end
function net.ReadEntity() return table.remove(incoming, 1) end
function net.ReadFloat() return table.remove(incoming, 1) end

local function newWeapon(class)
  return {valid = true, class = class, GetClass = function(self) return self.class end}
end

local function newPlayer(role)
  local ply = {
    valid = true, alive = true, spec = false, role = role or ROLE_INNOCENT,
    weapons = {}, index = #players + 1, center = vector(), failures = 0
  }
  function ply:IsPlayer() return true end
  function ply:Alive() return self.alive end
  function ply:IsSpec() return self.spec end
  function ply:GetSubRole() return self.role end
  function ply:EntIndex() return self.index end
  function ply:Nick() return self.nick or ("Player " .. self.index) end
  function ply:GetShootPos() return vector() end
  function ply:GetAimVector() return vector(1, 0, 0) end
  function ply:WorldSpaceCenter() return self.center end
  function ply:EyePos() return self.center + vector(0, 0, 28) end
  function ply:NearestPoint(point)
    return vector(
      math.Clamp(point.x, self.center.x - 16, self.center.x + 16),
      math.Clamp(point.y, self.center.y - 16, self.center.y + 16),
      math.Clamp(point.z, self.center.z - 36, self.center.z + 36)
    )
  end
  function ply:KeyDown(key)
    return key == IN_ATTACK and self.attacking and not self.suppressProcessedAttack
  end
  function ply:GetActiveWeapon() return self.active or NULL end
  function ply:HasWeapon(class) return self.weapons[class] ~= nil end
  function ply:Give(class)
    if self:HasWeapon(class) then return self.weapons[class] end
    if self.failures > 0 then self.failures = self.failures - 1; return NULL end
    local weapon = newWeapon(class)
    if hook.Run("PlayerCanPickupWeapon", self, weapon) == false then return NULL end
    self.weapons[class] = weapon
    hook.Run("WeaponEquip", weapon, self)
    return weapon
  end
  function ply:StripWeapon(class)
    if self.active == self.weapons[class] then self.active = nil end
    self.weapons[class] = nil
  end
  function ply:SelectWeapon(class) self.active = self.weapons[class] end
  players[#players + 1] = ply
  ply:Give("weapon_ttt_unarmed")
  ply:Give("weapon_zm_improvised")
  ply:Give("weapon_zm_carry")
  ply:Give("weapon_zm_pistol")
  ply:SelectWeapon("weapon_ttt_unarmed")
  return ply
end

local function tick(seconds)
  local steps = math.floor(seconds / 0.05 + 0.5)
  for _ = 1, steps do
    now = now + 0.05
    local due = {}
    for id, request in pairs(timers) do
      if request.at <= now + 0.000001 then due[#due + 1] = {id, request} end
    end
    for _, entry in ipairs(due) do
      local id, request = entry[1], entry[2]
      if timers[id] == request then
        request.left = request.left - 1
        if request.left == 0 then timers[id] = nil else request.at = now + request.delay end
        request.callback()
      end
    end
    for _, ply in ipairs(players) do
      local held = ply.attacking == true
      hook.Run("StartCommand", ply, {
        KeyDown = function(_, key) return key == IN_ATTACK and held end
      })
    end
    hook.Run("Think")
  end
end

local function assertNear(value, expected, tolerance)
  -- Owner-only HUD updates arrive at 10 Hz, up to 0.075 of a bar apart.
  assert(math.abs(value - expected) <= (tolerance or 0.08),
    "expected " .. tostring(expected) .. ", got " .. tostring(value))
end

local function test(name, callback)
  callback()
  passed = passed + 1
  print("PASS " .. name)
end

dofile("lua/terrortown/autorun/shared/sh_watcher.lua")
ROLE = {score = {}}
roles = {SetBaseRole = function(role, base) role.baserole = base end}
dofile("lua/terrortown/entities/roles/watcher/shared.lua")
ROLE:PreInitialize()
ROLE:Initialize()
SWEP = {}
dofile("lua/weapons/weapon_ttt2_watcher_stare.lua")
local serverWeapon = SWEP

local function fixture()
  roundState = ROUND_PREP
  hook.Run("TTTPrepareRound")
  players, messages, timers, pvs = {}, {}, {}, {}
  local watcher, target, other = newPlayer(ROLE_WATCHER), newPlayer(), newPlayer()
  roundState = ROUND_ACTIVE
  hook.Run("TTTBeginRound")
  tick(0.2)
  watcher:SelectWeapon(WATCHER_ROLE.STARE_CLASS)
  return watcher, target, other
end

local function stare(watcher, target, seconds)
  watcher.attacking, watcher.lookingAt = true, target
  tick(seconds)
end

local function tracked(ply) return (messages[ply] or {})[1] end
local function progress(ply) return (messages[ply] or {})[3] or 0 end

test("innocent role defaults and a harmless unarmed tool", function()
  assert(ROLE.defaultTeam == TEAM_INNOCENT and ROLE.baserole == ROLE_INNOCENT)
  assert(ROLE.unknownTeam and not ROLE.isPublicRole and not ROLE.isPolicingRole)
  assert(ROLE.score.killsMultiplier == 2 and ROLE.score.teamKillsMultiplier == -8)
  assert(ROLE.conVarData.credits == 0 and ROLE.conVarData.shopFallback == SHOP_DISABLED)
  assert(serverWeapon.Base == "weapon_ttt_unarmed" and serverWeapon.Kind == WEAPON_UNARMED)
  assert(#serverWeapon.InLoadoutFor == 0 and not serverWeapon.AllowDrop)
  assert(not serverWeapon.ShowDefaultViewModel and serverWeapon.HoldType == "normal")
  assert(serverWeapon:GetClass() == WATCHER_ROLE.STARE_CLASS)
  serverWeapon:PrimaryAttack()
  serverWeapon:SecondaryAttack()
end)

test("only Holstered is replaced; ordinary innocent weapons survive", function()
  local watcher, target = fixture()
  assert(watcher:HasWeapon(WATCHER_ROLE.STARE_CLASS) and not watcher:HasWeapon("weapon_ttt_unarmed"))
  assert(watcher:HasWeapon("weapon_zm_improvised") and watcher:HasWeapon("weapon_zm_carry"))
  assert(watcher:HasWeapon("weapon_zm_pistol") and watcher:GetActiveWeapon():GetClass() == WATCHER_ROLE.STARE_CLASS)
  assert(target:HasWeapon("weapon_ttt_unarmed") and not target:HasWeapon(WATCHER_ROLE.STARE_CLASS))
  local loadouts = {[ROLE_WATCHER] = {"weapon_ttt_unarmed", "weapon_zm_improvised"}, [ROLE_INNOCENT] = {"weapon_ttt_unarmed"}}
  hook.Run("TTT2ModifyDefaultLoadout", loadouts, ROLE_WATCHER)
  assert(loadouts[ROLE_WATCHER][1] == WATCHER_ROLE.STARE_CLASS)
  assert(loadouts[ROLE_INNOCENT][1] == "weapon_ttt_unarmed")
  local items = {[ROLE_WATCHER] = {"item_example"}}
  hook.Run("TTT2ModifyDefaultLoadout", items, ROLE_WATCHER)
  assert(#items[ROLE_WATCHER] == 1 and items[ROLE_WATCHER][1] == "item_example")
  assert(not IsValid(target:Give(WATCHER_ROLE.STARE_CLASS)))
end)

test("charging takes two seconds and state is private", function()
  local watcher, target, other = fixture()
  stare(watcher, target, 1.95)
  assert(tracked(watcher) == NULL)
  assertNear(progress(watcher), 0.975)
  tick(0.1)
  assert(tracked(watcher) == target and progress(watcher) == 0)
  assert(messages[target] == nil and messages[other] == nil)
  assert(lastTrace.mask == MASK_SHOT and lastTrace.filter == watcher)
  watcher.attacking = false
  tick(0.5)
  assert(tracked(watcher) == target)
end)

test("missed aim and released attack drain at half the previous speed", function()
  local watcher, target = fixture()
  stare(watcher, target, 1.2)
  assertNear(progress(watcher), 0.6)
  watcher.lookingAt = NULL
  tick(1.2)
  assertNear(progress(watcher), 0.4)
  watcher.lookingAt, watcher.attacking = target, false
  tick(1.2)
  assertNear(progress(watcher), 0.2)
  watcher.attacking = true
  tick(1.5)
  assert(tracked(watcher) == NULL)
  tick(0.3)
  assert(tracked(watcher) == target)
end)

test("one held click resumes staring after leaving and returning to a player", function()
  local watcher, target = fixture()
  -- Raw commands still hold attack even if the weapon's processed button state
  -- no longer reports it. Do not release or invoke PrimaryAttack during this test.
  watcher.attacking, watcher.suppressProcessedAttack = true, true
  watcher.lookingAt = NULL
  tick(0.3)
  watcher.lookingAt = target
  tick(0.9)
  assertNear(progress(watcher), 0.45)
  watcher.lookingAt = NULL
  tick(0.6)
  assertNear(progress(watcher), 0.35)
  watcher.lookingAt = target
  tick(1.35)
  assert(tracked(watcher) == target)
end)

test("a held click restarts after full decay and can acquire a different player", function()
  local watcher, target, other = fixture()
  watcher.attacking, watcher.suppressProcessedAttack = true, true
  watcher.lookingAt = target
  tick(0.9)
  watcher.lookingAt = NULL
  tick(3)
  assert(progress(watcher) == 0)
  watcher.lookingAt = target
  tick(2.8)
  assert(tracked(watcher) == target)
  watcher.lookingAt = NULL
  tick(0.3)
  watcher.lookingAt = other
  tick(2.8)
  assert(tracked(watcher) == other)
end)

test("blocked traces, spectators and dead targets cannot be acquired", function()
  local watcher, target = fixture()
  local wall = {valid = true, IsPlayer = function() return false end}
  stare(watcher, wall, 2.8)
  assert(tracked(watcher) == NULL and progress(watcher) == 0)
  target.spec = true
  stare(watcher, target, 2.8)
  assert(tracked(watcher) == NULL)
  target.spec, target.alive = false, false
  stare(watcher, target, 2.8)
  assert(tracked(watcher) == NULL)
end)

test("aiming a tiny amount beside a visible player acquires them", function()
  local watcher, target = fixture()
  target.center = vector(1000, 18, 0)
  stare(watcher, NULL, 2.8)
  assert(tracked(watcher) == target)
end)

test("aim forgiveness works at longer distances", function()
  local watcher, target = fixture()
  target.center = vector(2000, 21, 0)
  stare(watcher, NULL, 2.8)
  assert(tracked(watcher) == target)
end)

test("aiming outside the tiny margin does not acquire a player", function()
  local watcher, target = fixture()
  target.center = vector(1000, 20, 0)
  stare(watcher, NULL, 2.8)
  assert(tracked(watcher) == NULL and progress(watcher) == 0)
end)

test("aim forgiveness never acquires a player hidden behind cover", function()
  local watcher, target = fixture()
  target.center, target.hidden = vector(1000, 18, 0), true
  stare(watcher, NULL, 2.8)
  assert(tracked(watcher) == NULL and progress(watcher) == 0)
end)

test("a visible head allows forgiveness when the body is behind cover", function()
  local watcher, target = fixture()
  target.center, target.centerBlocked = vector(1000, 18, 0), true
  stare(watcher, NULL, 2.8)
  assert(tracked(watcher) == target)
end)

test("directly aimed players take priority over nearby candidates", function()
  local watcher, target, other = fixture()
  target.center, other.center = vector(1000, 18, 0), vector(1000, 19, 0)
  stare(watcher, other, 2.8)
  assert(tracked(watcher) == other)
end)

test("the visible candidate closest to the crosshair is chosen", function()
  local watcher, target, other = fixture()
  target.center, other.center = vector(1000, 18, 0), vector(1000, 17, 0)
  stare(watcher, NULL, 2.8)
  assert(tracked(watcher) == other)
end)

test("aim forgiveness excludes spectators, dead players and players behind you", function()
  local watcher, target = fixture()
  target.center, target.spec = vector(1000, 18, 0), true
  stare(watcher, NULL, 2.8)
  assert(tracked(watcher) == NULL)
  target.spec, target.alive = false, false
  tick(2.8)
  assert(tracked(watcher) == NULL)
  target.alive, target.center = true, vector(-1000, 0, 0)
  tick(2.8)
  assert(tracked(watcher) == NULL)
  target.center = vector(33000, 40, 0)
  tick(2.8)
  assert(tracked(watcher) == NULL)
end)

test("progress cannot transfer to a different aimed-at player", function()
  local watcher, target, other = fixture()
  stare(watcher, target, 1.5)
  stare(watcher, other, 0.6)
  assert(tracked(watcher) == NULL)
  assertNear(progress(watcher), 0.3)
  tick(2)
  assert(tracked(watcher) == other)
end)

test("only a completed second stare replaces the old track", function()
  local watcher, target, other = fixture()
  stare(watcher, target, 2.8)
  stare(watcher, other, 1.8)
  assert(tracked(watcher) == target)
  tick(0.4)
  assert(tracked(watcher) == other)
  hook.Run("SetupPlayerVisibility", watcher)
  assert(#pvs == 1 and pvs[1] == other.center)
  hook.Run("SetupPlayerVisibility", target)
  assert(#pvs == 1)
end)

test("switching weapons preserves the track and prevents charging", function()
  local watcher, target, other = fixture()
  stare(watcher, target, 2.8)
  stare(watcher, other, 1.2)
  watcher:SelectWeapon("weapon_zm_pistol")
  tick(1.2)
  assert(tracked(watcher) == target)
  assertNear(progress(watcher), 0.4)
  tick(5)
  assert(progress(watcher) == 0 and tracked(watcher) == target)
  hook.Run("SetupPlayerVisibility", watcher)
  assert(#pvs == 1 and pvs[1] == target.center)
end)

test("two Watchers track independently", function()
  local watcher, target, other = fixture()
  local second = newPlayer(ROLE_WATCHER)
  hook.Run("TTT2UpdateSubrole", second, ROLE_INNOCENT, ROLE_WATCHER)
  tick(0.2)
  second:SelectWeapon(WATCHER_ROLE.STARE_CLASS)
  second.attacking, second.lookingAt = true, other
  stare(watcher, target, 2.8)
  assert(tracked(watcher) == target and tracked(second) == other)
  watcher.alive = false
  hook.Run("PlayerDeath", watcher)
  assert(tracked(watcher) == NULL and tracked(second) == other)
end)

for _, event in ipairs({"PlayerDeath", "PlayerSilentDeath", "PlayerDisconnected"}) do
  test(event .. " clears Watcher state and target visibility", function()
    local watcher, target = fixture()
    stare(watcher, target, 2.8)
    hook.Run(event, watcher)
    assert(tracked(watcher) == NULL)
    hook.Run("SetupPlayerVisibility", watcher)
    assert(#pvs == 0)
  end)
  test(event .. " clears a tracked target without restoring on revival", function()
    local watcher, target = fixture()
    stare(watcher, target, 2.8)
    watcher.attacking = false
    target.alive = false
    hook.Run(event, target)
    assert(tracked(watcher) == NULL)
    target.alive = true
    tick(0.2)
    assert(tracked(watcher) == NULL)
  end)
end

test("spectating clears tracking even without a death hook", function()
  local watcher, target = fixture()
  stare(watcher, target, 2.8)
  watcher.spec = true
  tick(0.1)
  assert(tracked(watcher) == NULL)
  hook.Run("SetupPlayerVisibility", watcher)
  assert(#pvs == 0)
end)

test("role removal restores Holstered and clears tracking", function()
  local watcher, target = fixture()
  stare(watcher, target, 2.8)
  watcher.role = ROLE_INNOCENT
  hook.Run("TTT2UpdateSubrole", watcher, ROLE_WATCHER, ROLE_INNOCENT)
  ROLE:RemoveRoleLoadout(watcher, true)
  assert(tracked(watcher) == NULL and not watcher:HasWeapon(WATCHER_ROLE.STARE_CLASS))
  assert(watcher:HasWeapon("weapon_ttt_unarmed") and watcher:HasWeapon("weapon_zm_pistol"))
end)

test("TTT2 reassigning the same role does not remove its tool or track", function()
  local watcher, target = fixture()
  stare(watcher, target, 2.8)
  ROLE:GiveRoleLoadout(watcher, true)
  ROLE:RemoveRoleLoadout(watcher, true)
  tick(0.2)
  assert(watcher:HasWeapon(WATCHER_ROLE.STARE_CLASS) and tracked(watcher) == target)
end)

for _, event in ipairs({"TTTEndRound", "TTTPrepareRound"}) do
  test(event .. " clears completed and partial tracking", function()
    local watcher, target, other = fixture()
    stare(watcher, target, 2.8)
    stare(watcher, other, 1.2)
    roundState = event == "TTTEndRound" and ROUND_POST or ROUND_PREP
    hook.Run(event)
    assert(tracked(watcher) == NULL and progress(watcher) == 0)
    hook.Run("SetupPlayerVisibility", watcher)
    assert(#pvs == 0)
    roundState = ROUND_ACTIVE
    hook.Run("TTTBeginRound")
    watcher.attacking = false
    tick(0.2)
    assert(tracked(watcher) == NULL)
  end)
end

test("loadout retries give failures without removing guns", function()
  local watcher = fixture()
  watcher:StripWeapon(WATCHER_ROLE.STARE_CLASS)
  watcher.failures = 2
  ROLE:GiveRoleLoadout(watcher, true)
  tick(0.5)
  assert(watcher:HasWeapon(WATCHER_ROLE.STARE_CLASS) and watcher:HasWeapon("weapon_zm_pistol"))
  assert(next(timers) == nil)
end)

test("late Holstered gives are replaced without changing an equipped gun", function()
  local watcher = fixture()
  watcher:SelectWeapon("weapon_zm_pistol")
  watcher:Give("weapon_ttt_unarmed")
  tick(0.2)
  assert(not watcher:HasWeapon("weapon_ttt_unarmed"))
  assert(watcher:GetActiveWeapon():GetClass() == "weapon_zm_pistol")
end)

test("respawning starts with no previous track", function()
  local watcher, target = fixture()
  stare(watcher, target, 2.8)
  watcher.attacking = false
  hook.Run("PlayerSpawn", watcher)
  tick(0.2)
  assert(tracked(watcher) == NULL and watcher:HasWeapon(WATCHER_ROLE.STARE_CLASS))
end)

-- Test the client realm separately, retaining the same fake player entities.
SERVER, CLIENT = false, true
callbacks = {}
halo = {Add = function(...) halos[#halos + 1] = {...} end}
draw = {
  RoundedBox = function(...) drawings[#drawings + 1] = {...} end,
  SimpleTextOutlined = function(...) drawings[#drawings + 1] = {...} end
}
local translations = {}
LANG = {
  GetLanguageTableReference = function() return translations end,
  GetTranslation = function(key) return assert(translations[key], "missing translation " .. key) end
}
WATCHER = {name = "watcher", abbr = "wtch"}
dofile("lua/terrortown/lang/en/watcher.lua")
dofile("lua/terrortown/autorun/shared/sh_watcher.lua")
SWEP = {}
dofile("lua/weapons/weapon_ttt2_watcher_stare.lua")
function SWEP:DoDrawCrosshair() end

local function deliver(target, aimedAt, amount)
  incoming = {target or NULL, aimedAt or NULL, amount or 0}
  net.receivers.ttt2_watcher_state()
end

test("client draws Barclay-style through-wall halos with another weapon selected", function()
  players = {}
  localPlayer = newPlayer(ROLE_WATCHER)
  local target = newPlayer()
  localPlayer:SelectWeapon("weapon_zm_pistol")
  roundState = ROUND_ACTIVE
  deliver(target)
  hook.Run("PreDrawHalos")
  assert(#halos == 1 and #halos[1][1] == 1 and halos[1][1][1] == target)
  assert(halos[1][2].r == 255 and halos[1][2].g == 0)
  assert(halos[1][7] == true, "halo must ignore depth")
end)

test("the stare HUD keeps progress and hides idle and tracking messages", function()
  local target = players[2]
  target.nick = "Alex"
  deliver(nil, target, 0.5)
  SWEP:DrawHUD()
  assert(#drawings == 3 and drawings[3][1] == "Staring at Alex 50%")
  drawings = {}
  deliver(target)
  SWEP:DrawHUD()
  assert(#drawings == 0)
  drawings = {}
  deliver()
  SWEP:DrawHUD()
  assert(#drawings == 0)
end)

test("client never draws outlines for dead, spectating or non-Watcher viewers", function()
  deliver(players[2])
  halos = {}
  localPlayer.alive = false
  hook.Run("PreDrawHalos")
  localPlayer.alive, localPlayer.spec = true, true
  hook.Run("PreDrawHalos")
  localPlayer.spec, localPlayer.role = false, ROLE_INNOCENT
  hook.Run("PreDrawHalos")
  assert(#halos == 0)
  hook.Run("Think")
  localPlayer.role = ROLE_WATCHER
  hook.Run("PreDrawHalos")
  assert(#halos == 0, "old tracks must not reappear after regaining the role")
end)

test("client clears on round cleanup and rejects dead targets", function()
  local target = players[2]
  deliver(target)
  target.alive = false
  hook.Run("PreDrawHalos")
  assert(#halos == 0)
  target.alive = true
  for _, event in ipairs({"TTTEndRound", "TTTPrepareRound"}) do
    deliver(target)
    hook.Run(event)
    hook.Run("PreDrawHalos")
    assert(#halos == 0)
  end
  deliver(target)
  roundState = ROUND_POST
  hook.Run("Think")
  hook.Run("PreDrawHalos")
  assert(#halos == 0)
end)

print("Watcher: " .. passed .. " behavior tests passed.")
