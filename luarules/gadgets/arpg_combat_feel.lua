-- luarules/gadgets/arpg_combat_feel.lua
-- Combat Feel & Hit Feedback Engine for BAR Sci-Fi ARPG ("WRECKAGE PROTOCOL")
-- Addresses Muse Letter 011 Risk #2: directional impact knockback, elite micro-stagger,
-- death pop CEGs, floating combat/salvage telemetry, and camera shake impulses.

function gadget:GetInfo()
	return {
		name = "ARPG Combat Feel & Hit Feedback",
		desc = "Directional knockback, hit-stop micro-stagger, death pop CEGs, floating numbers, and screen shake",
		author = "Argon",
		date = "2026-11-01",
		license = "GNU GPL, v2 or later",
		layer = 18,
		enabled = true,
	}
end

if gadgetHandler and not gadgetHandler:IsSyncedCode() then
	return false
end

local recentEvents = {} -- Ring buffer of { id, kind, x, y, z, value, label, frame }
local nextEventId = 1
local MAX_EVENTS = 32
local currentShakeIntensity = 0.0

local function pushCombatEvent(kind, x, y, z, value, label)
	local frame = (Spring and Spring.GetGameFrame and Spring.GetGameFrame()) or 0
	local ev = {
		id = nextEventId,
		kind = kind,
		x = x or 2048,
		y = y or 140,
		z = z or 2048,
		value = math.floor(tonumber(value) or 0),
		label = tostring(label or ""),
		frame = frame,
	}
	nextEventId = nextEventId + 1
	recentEvents[#recentEvents + 1] = ev
	if #recentEvents > MAX_EVENTS then
		table.remove(recentEvents, 1)
	end

	if Spring and Spring.SetGameRulesParam then
		Spring.SetGameRulesParam("arpg_last_event_id", ev.id)
		Spring.SetGameRulesParam("arpg_last_event_kind", ev.kind)
		Spring.SetGameRulesParam("arpg_last_event_x", math.floor(ev.x))
		Spring.SetGameRulesParam("arpg_last_event_y", math.floor(ev.y))
		Spring.SetGameRulesParam("arpg_last_event_z", math.floor(ev.z))
		Spring.SetGameRulesParam("arpg_last_event_val", ev.value)
		Spring.SetGameRulesParam("arpg_last_event_label", ev.label)
	end
	return ev
end

local function addScreenShake(intensity)
	currentShakeIntensity = math.min(25.0, currentShakeIntensity + (tonumber(intensity) or 2.0))
	if Spring and Spring.SetGameRulesParam then
		Spring.SetGameRulesParam("arpg_screen_shake", math.floor(currentShakeIntensity * 10))
	end
end

function gadget:UnitDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID, attackerDefID, attackerTeam)
	if not damage or damage < 15 then
		return
	end

	local ux, uy, uz = 2048, 140, 2048
	if Spring and Spring.GetUnitPosition then
		local px, py, pz = Spring.GetUnitPosition(unitID)
		if px then
			ux, uy, uz = px, py, pz
		end
	end

	-- 1. Directional Kinetic Knockback & Hit-Stop Micro-Stagger on Heavy Hits
	if damage >= 180 and attackerID and Spring and Spring.GetUnitPosition and Spring.AddUnitImpulse then
		local ax, _, az = Spring.GetUnitPosition(attackerID)
		if ax then
			local dx = ux - ax
			local dz = uz - az
			local dist = math.max(1.0, math.sqrt(dx * dx + dz * dz))
			local knockbackMag = math.min(9.5, (damage / 220.0) * 2.2)
			Spring.AddUnitImpulse(unitID, (dx / dist) * knockbackMag, 1.4, (dz / dist) * knockbackMag)
		end
	end

	-- 2. Emit Floating Damage Number & Camera Shake for Heavy Strikes
	local isCrit = (damage >= 600)
	pushCombatEvent(isCrit and "crit_damage" or "damage", ux, uy + 24, uz, damage, isCrit and "CRIT!" or "HIT")
	if isCrit then
		addScreenShake(math.min(12.0, damage / 180.0))
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID)
	local ux, uy, uz = 2048, 140, 2048
	if Spring and Spring.GetUnitPosition then
		local px, py, pz = Spring.GetUnitPosition(unitID)
		if px then
			ux, uy, uz = px, py, pz
		end
	end

	-- Spawn crisp death pop CEG and micro screen-shake
	if Spring and Spring.SpawnCEG then
		Spring.SpawnCEG("custom:barrelshot-medium", ux, uy + 16, uz, 0, 1, 0, 20, 0)
	end
	pushCombatEvent("kill_pop", ux, uy + 32, uz, 0, "WRECKED!")
	addScreenShake(2.5)
end

function gadget:GameFrame(frame)
	if frame % 5 == 0 and currentShakeIntensity > 0 then
		currentShakeIntensity = math.max(0.0, currentShakeIntensity * 0.72 - 0.25)
		if Spring and Spring.SetGameRulesParam then
			Spring.SetGameRulesParam("arpg_screen_shake", math.floor(currentShakeIntensity * 10))
		end
	end
end

GG = GG or {}
GG.ARPG_CombatFeel = {
	PushCombatEvent = pushCombatEvent,
	AddScreenShake = addScreenShake,
	GetRecentEvents = function()
		return recentEvents
	end,
	GetShakeIntensity = function()
		return currentShakeIntensity
	end,
}

return GG.ARPG_CombatFeel
