if SERVER then
  AddCSLuaFile()
end

-- Inherit the normal holstered pose, hidden viewmodel and harmless attacks.
SWEP.Base = "weapon_ttt_unarmed"
SWEP.PrintName = "watcher_stare_name"
SWEP.HoldType = "normal"
SWEP.Kind = WEAPON_UNARMED
SWEP.Slot = 5
SWEP.SlotPos = 0
SWEP.InLoadoutFor = {}
SWEP.CanBuy = {}
SWEP.Spawnable = false
SWEP.AutoSpawnable = false
SWEP.AllowDrop = false
SWEP.AllowDelete = false
SWEP.builtin = false
SWEP.silentPickup = true
SWEP.NoSights = true
SWEP.UseHands = false
SWEP.DrawAmmo = false
SWEP.ShowDefaultViewModel = false

SWEP.Primary = {
  ClipSize = -1,
  DefaultClip = -1,
  Automatic = true,
  Ammo = "none"
}

SWEP.Secondary = {
  ClipSize = -1,
  DefaultClip = -1,
  Automatic = false,
  Ammo = "none"
}

-- Older versions of unarmed override GetClass; never inherit that identity.
function SWEP:GetClass()
  return "weapon_ttt2_watcher_stare"
end

function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end
function SWEP:Reload() end
function SWEP:DrawWorldModel() end
function SWEP:DrawWorldModelTranslucent() end

if CLIENT then
  SWEP.Icon = "vgui/ttt/icon_unarmed"

  function SWEP:DrawHUD()
    -- Keep TTT2's normal crosshair while adding the stare progress beneath it.
    self:DoDrawCrosshair(math.ceil(ScrW() * 0.5), math.ceil(ScrH() * 0.5), true)

    if WATCHER_ROLE then
      WATCHER_ROLE.DrawStareHUD()
    end
  end
end
