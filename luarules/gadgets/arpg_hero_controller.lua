-- luarules/gadgets/arpg_hero_controller.lua
-- Single-Unit Modular Hero Controller, WASD / Click-to-Move Bridge,
-- Module-Derived Active Abilities (No Skill Tree), and Dodge/Bastion Damage Mitigation.

function gadget:GetInfo()
	return {
		name = "ARPG Hero Controller",
		desc = "Controls the player's rogue modular machine, WASD/mouse input, and bolted-on module abilities",
		author = "Argon",
		date = "2026-11-01",
		license = "GNU GPL, v2 or later",
		layer = 15,
		enabled = true,
	}
end

if gadgetHandler and not gadgetHandler:IsSyncedCode() then
	return false
end

local heroByTeam = {} -- [teamID] = unitID
local heroRuntime = {} -- [unitID] = { teamID, cooldowns = {}, iframeUntilFrame = 0, bastionUntilFrame = 0, salvageOverdriveUntil = 0 }
local markedVulnerable = {} -- [enemyUnitID] = expireFrame

local function isNearGaragePad(unitID)
	local zone = GG and GG.ARPG_Map and GG.ARPG_Map.GetCurrentZone and GG.ARPG_Map.GetCurrentZone()
	if not zone or not Spring or not Spring.GetUnitPosition then
		return true
	end
	local ux, _, uz = Spring.GetUnitPosition(unitID)
	if not ux then
		return false
	end
	for i = 1, #zone.nodes do
		local n = zone.nodes[i]
		if n.hasGarage then
			local d = math.sqrt((ux - n.x) ^ 2 + (uz - n.z) ^ 2)
			if d <= (n.radius + 90) then
				return true
			end
		end
	end
	return false
end

local function spawnOrRelocateHero(teamID, preserveState)
	local zone = GG and GG.ARPG_Map and GG.ARPG_Map.GetCurrentZone and GG.ARPG_Map.GetCurrentZone()
	local dropX = (zone and zone.dropZone and zone.dropZone.x) or 600
	local dropZ = (zone and zone.dropZone and zone.dropZone.z) or 600
	local dropY = (Spring and Spring.GetGroundHeight and Spring.GetGroundHeight(dropX, dropZ)) or 140

	local existingID = heroByTeam[teamID]
	local savedAssemblyState = nil
	if preserveState and existingID and GG and GG.ARPG_Assembly then
		savedAssemblyState = GG.ARPG_Assembly.GetHeroState(existingID)
	end

	if existingID and Spring and Spring.ValidUnitID and Spring.ValidUnitID(existingID) then
		if Spring.SetUnitPosition then
			Spring.SetUnitPosition(existingID, dropX, dropY, dropZ)
		end
		if GG and GG.ARPG_Assembly then
			GG.ARPG_Assembly.InitHeroAssembly(existingID, savedAssemblyState)
		end
		return existingID
	end

	local unitDefName = "armcom"
	if savedAssemblyState and savedAssemblyState.loadout and savedAssemblyState.loadout.frame == "frame_siege_goliath" then
		unitDefName = "corcom"
	end

	local unitID = nil
	if Spring and Spring.CreateUnit then
		unitID = Spring.CreateUnit(unitDefName, dropX, dropY, dropZ, 0, teamID)
	end
	if not unitID then
		unitID = 1001 + (teamID or 0)
	end

	heroByTeam[teamID] = unitID
	heroRuntime[unitID] = {
		unitID = unitID,
		teamID = teamID,
		cooldowns = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 },
		iframeUntilFrame = 0,
		bastionUntilFrame = 0,
		salvageOverdriveUntil = 0,
	}

	if GG and GG.ARPG_Assembly then
		GG.ARPG_Assembly.InitHeroAssembly(unitID, savedAssemblyState)
	end

	if Spring and Spring.SetGameRulesParam then
		Spring.SetGameRulesParam("arpg_hero_unit_id", unitID)
	end
	if Spring and Spring.SetUnitRulesParam then
		Spring.SetUnitRulesParam(unitID, "arpg_is_hero", 1)
		Spring.SetUnitRulesParam(unitID, "arpg_near_garage", 1)
	end

	return unitID
end

-- Executes the hardware ability bolted onto module slot `slotIdx` (1..4)
local function activateModuleAbility(unitID, slotIdx, targetX, targetZ)
	local rt = heroRuntime[unitID]
	local asm = GG and GG.ARPG_Assembly and GG.ARPG_Assembly.GetHeroState(unitID)
	if not rt or not asm or not asm.budget then
		return false, "NO_HERO_RUNTIME"
	end

	local entry = asm.budget.activeAbilities[slotIdx]
	if not entry or not entry.ability then
		return false, "EMPTY_MODULE_SLOT"
	end

	local ab = entry.ability
	local frame = (Spring and Spring.GetGameFrame and Spring.GetGameFrame()) or 0
	local readyFrame = rt.cooldowns[slotIdx] or 0
	if frame < readyFrame then
		return false, "ABILITY_ON_COOLDOWN"
	end

	-- Thermal lockout check (except Thermal Purge which vents heat!)
	if (ab.heatCost or 0) > 0 and asm.heat >= asm.maxHeat then
		return false, "THERMAL_OVERLOAD_LOCKOUT"
	end

	local ux, uy, uz = 600, 140, 600
	if Spring and Spring.GetUnitPosition then
		local px, py, pz = Spring.GetUnitPosition(unitID)
		if px then
			ux, uy, uz = px, py, pz
		end
	end
	targetX = tonumber(targetX) or (ux + 120)
	targetZ = tonumber(targetZ) or uz

	-- Apply cooldown and thermal cost
	rt.cooldowns[slotIdx] = frame + (ab.cooldownFrames or 120)
	asm.heat = math.max(0.0, math.min(asm.maxHeat * 1.25, asm.heat + (ab.heatCost or 0)))

	if ab.id == "vectored_dash" then
		local dx = targetX - ux
		local dz = targetZ - uz
		local dist = math.max(1.0, math.sqrt(dx * dx + dz * dz))
		local stepDist = math.min(ab.dashDistance or 240, dist)
		local nx = ux + (dx / dist) * stepDist
		local nz = uz + (dz / dist) * stepDist
		local ny = (Spring and Spring.GetGroundHeight and Spring.GetGroundHeight(nx, nz)) or uy
		if Spring and Spring.SetUnitPosition then
			Spring.SetUnitPosition(unitID, nx, ny, nz)
		end
		rt.iframeUntilFrame = frame + (ab.iframeFrames or 18)
	elseif ab.id == "pile_bunker_strike" then
		if Spring and Spring.GetUnitsInCylinder and Spring.AddUnitDamage then
			local dx = targetX - ux
			local dz = targetZ - uz
			local dist = math.max(1.0, math.sqrt(dx * dx + dz * dz))
			local strikeX = ux + (dx / dist) * 85
			local strikeZ = uz + (dz / dist) * 85
			local targets = Spring.GetUnitsInCylinder(strikeX, strikeZ, ab.range or 175)
			if targets then
				for i = 1, #targets do
					local tid = targets[i]
					if tid ~= unitID then
						Spring.AddUnitDamage(tid, ab.damage or 1450, 0, unitID, -1)
						markedVulnerable[tid] = frame + 150
						if Spring.AddUnitImpulse then
							Spring.AddUnitImpulse(tid, (dx / dist) * 12.0, 3.5, (dz / dist) * 12.0)
						end
					end
				end
			end
		end
	elseif ab.id == "deep_salvage_ping" then
		if Spring and Spring.GetUnitsInCylinder then
			local targets = Spring.GetUnitsInCylinder(ux, uz, ab.radius or 750)
			if targets then
				for i = 1, #targets do
					local tid = targets[i]
					if tid ~= unitID then
						markedVulnerable[tid] = frame + (ab.durationFrames or 180)
					end
				end
			end
		end
	elseif ab.id == "thermal_purge_nova" then
		local vented = math.min(asm.heat + 65, 65)
		local totalDamage = (ab.baseDamage or 650) + vented * (ab.damagePerHeatVented or 18)
		if Spring and Spring.GetUnitsInCylinder and Spring.AddUnitDamage then
			local targets = Spring.GetUnitsInCylinder(ux, uz, ab.radius or 260)
			if targets then
				for i = 1, #targets do
					local tid = targets[i]
					if tid ~= unitID then
						Spring.AddUnitDamage(tid, totalDamage, 0, unitID, -1)
					end
				end
			end
		end
	elseif ab.id == "overdrive_salvage_beam" then
		rt.salvageOverdriveUntil = frame + (ab.durationFrames or 180)
		if Spring and Spring.SetUnitBuildSpeed and asm.budget then
			local boosted = asm.budget.reclaimSpeed * (ab.reclaimSpeedMultiplier or 3.0)
			Spring.SetUnitBuildSpeed(unitID, asm.budget.buildPower, asm.budget.buildPower, boosted, asm.budget.buildPower, asm.budget.buildPower)
		end
	elseif ab.id == "siege_bastion_field" then
		rt.bastionUntilFrame = frame + (ab.durationFrames or 150)
	elseif ab.id == "resurrect_wreck_toggle" then
		if Spring and Spring.GetFeaturesInCylinder and GG and GG.ARPG_Salvage and GG.ARPG_Salvage.RaiseWreck then
			local nearFeatures = Spring.GetFeaturesInCylinder(ux, uz, ab.radius or 340)
			if nearFeatures and #nearFeatures > 0 then
				local okR, resR = GG.ARPG_Salvage.RaiseWreck(unitID, nearFeatures[1])
				if not okR then
					return false, resR
				end
			else
				return false, "NO_WRECK_IN_RANGE"
			end
		end
	end

	if Spring and Spring.SetUnitRulesParam then
		Spring.SetUnitRulesParam(unitID, "arpg_cd_" .. slotIdx, rt.cooldowns[slotIdx])
		Spring.SetUnitRulesParam(unitID, "arpg_heat", math.floor(asm.heat))
	end

	return true, "EXECUTED_" .. ab.id
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	local frame = (Spring and Spring.GetGameFrame and Spring.GetGameFrame()) or 0

	-- 1. Hero Dodge I-Frames & Siege Bastion Damage Reduction
	local rt = heroRuntime[unitID]
	if rt then
		if frame < rt.iframeUntilFrame then
			return 0, 0
		end
		if frame < rt.bastionUntilFrame then
			damage = damage * 0.40
		end
	end

	-- 2. Marked Vulnerable Target Bonus (+30% damage from Deep Salvage & Threat Ping or Pile Bunker)
	if markedVulnerable[unitID] and frame < markedVulnerable[unitID] then
		damage = damage * 1.30
	end

	return damage, 1.0
end

function gadget:RecvLuaMsg(msg, playerID)
	if not msg or string.sub(msg, 1, 5) ~= "arpg:" then
		return
	end
	local teamID = 0
	if Spring and Spring.GetPlayerInfo then
		local _, _, _, tID = Spring.GetPlayerInfo(playerID)
		if tID then
			teamID = tID
		end
	end
	local heroID = heroByTeam[teamID]
	if not heroID then
		return
	end

	local parts = {}
	for token in string.gmatch(msg, "[^:]+") do
		parts[#parts + 1] = token
	end

	local cmd = parts[2]
	if cmd == "move" then
		local dx = tonumber(parts[3]) or 0
		local dz = tonumber(parts[4]) or 0
		if Spring and Spring.GetUnitPosition and Spring.GiveOrderToUnit and CMD and CMD.MOVE then
			local ux, uy, uz = Spring.GetUnitPosition(heroID)
			if ux then
				Spring.GiveOrderToUnit(heroID, CMD.MOVE, { ux + dx * 180, uy, uz + dz * 180 }, {})
			end
		end
	elseif cmd == "reclaim_nearest" then
		if Spring and Spring.GetUnitPosition and Spring.GetFeaturesInCylinder and Spring.GiveOrderToUnit and CMD and CMD.RECLAIM then
			local ux, _, uz = Spring.GetUnitPosition(heroID)
			if ux then
				local features = Spring.GetFeaturesInCylinder(ux, uz, 340)
				if features and #features > 0 then
					Spring.GiveOrderToUnit(heroID, CMD.RECLAIM, { Game.maxUnits + features[1] }, {})
				end
			end
		end
	elseif cmd == "raise_nearest" then
		if Spring and Spring.GetUnitPosition and Spring.GetFeaturesInCylinder and GG and GG.ARPG_Salvage and GG.ARPG_Salvage.RaiseWreck then
			local ux, _, uz = Spring.GetUnitPosition(heroID)
			if ux then
				local nearFeatures = Spring.GetFeaturesInCylinder(ux, uz, 340)
				if nearFeatures and #nearFeatures > 0 then
					GG.ARPG_Salvage.RaiseWreck(heroID, nearFeatures[1])
				end
			end
		end
	elseif cmd == "ability" then
		local slotIdx = tonumber(parts[3]) or 1
		local tx = tonumber(parts[4])
		local tz = tonumber(parts[5])
		activateModuleAbility(heroID, slotIdx, tx, tz)
	elseif cmd == "craft" then
		local partId = parts[3]
		if isNearGaragePad(heroID) and GG and GG.ARPG_Assembly then
			GG.ARPG_Assembly.CraftPart(heroID, partId)
		end
	elseif cmd == "equip" then
		local slotName = parts[3]
		local partId = parts[4]
		if isNearGaragePad(heroID) and GG and GG.ARPG_Assembly then
			GG.ARPG_Assembly.EquipPart(heroID, slotName, partId)
		end
	end
end

function gadget:GameStart()
	spawnOrRelocateHero(0, false)
end

function gadget:GameFrame(frame)
	if frame % 15 == 0 then
		for unitID, rt in pairs(heroRuntime) do
			if Spring and Spring.SetUnitRulesParam then
				Spring.SetUnitRulesParam(unitID, "arpg_near_garage", isNearGaragePad(unitID) and 1 or 0)
			end
			if rt.salvageOverdriveUntil > 0 and frame >= rt.salvageOverdriveUntil then
				rt.salvageOverdriveUntil = 0
				local asm = GG and GG.ARPG_Assembly and GG.ARPG_Assembly.GetHeroState(unitID)
				if asm and asm.budget and Spring and Spring.SetUnitBuildSpeed then
					local b = asm.budget
					Spring.SetUnitBuildSpeed(unitID, b.buildPower, b.buildPower, b.reclaimSpeed, b.buildPower, b.buildPower)
				end
			end
		end
	end
end

GG = GG or {}
GG.ARPG_Hero = {
	SpawnOrRelocateHero = spawnOrRelocateHero,
	SpawnCoopParty = function(teamIDs, preserveState)
		local spawned = {}
		for i = 1, #(teamIDs or { 0 }) do
			spawned[#spawned + 1] = spawnOrRelocateHero(teamIDs[i], preserveState)
		end
		return spawned
	end,
	GetAllHeroUnitIDs = function()
		local list = {}
		for _, uID in pairs(heroByTeam) do
			list[#list + 1] = uID
		end
		return list
	end,
	GetHeroUnitID = function(teamID)
		return heroByTeam[teamID or 0]
	end,
	ActivateModuleAbility = activateModuleAbility,
	IsNearGaragePad = isNearGaragePad,
}

return GG.ARPG_Hero
