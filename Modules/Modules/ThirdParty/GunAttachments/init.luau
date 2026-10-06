--!nonstrict
--[[
	GunAttachments — standalone weapon attachment system for Roblox.

	Self-contained: requires nothing outside this folder. Game-specific behaviour is
	supplied through options and hooks. See README.md for the full API.

	    local GunAttachments = require(path.to.GunAttachments)
	    local attachments = GunAttachments.new({
	        contentRoot = ReplicatedStorage.Assets.GunAttachments,
	    })
	    attachments:Equip(gunModel, tool, "Optics", "RedDot", player)
]]

local Defaults = require(script.Defaults)
local Loadout = require(script.Loadout)
local Stats = require(script.Stats)
local System = require(script.System)
local Types = require(script.Types)

export type Options = Types.Options
export type Record = Types.Record
export type Loadout = Types.Loadout
export type SlotDef = Types.SlotDef
export type AttachmentConfig = Types.AttachmentConfig
export type GripData = Types.GripData

local GunAttachments = {}

GunAttachments.Version = "1.0.0"

-- Default slot table / options / attribute names (read-only copies).
GunAttachments.Defaults = table.freeze({
	slots = Defaults.slots,
	options = Defaults.options,
	attributes = Defaults.attributes,
})

-- Pure helpers usable without a system.
GunAttachments.deepCopy = Stats.deepCopy
GunAttachments.applyModifiers = Stats.applyModifiers
GunAttachments.readLoadout = Loadout.read

-- Creates an independent attachment system.
function GunAttachments.new(options: Options?)
	return System.new(options)
end

return GunAttachments
