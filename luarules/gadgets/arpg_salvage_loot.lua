-- luarules/gadgets/arpg_salvage_loot.lua
-- Engine-Native Reclaim-as-Loot System for BAR Sci-Fi ARPG ("WRECKAGE PROTOCOL")
-- Kills leave physical wrecks; salvaging is an exposed channel yielding Metal, Energy,
-- Crafting Materials, and intact Machine Parts. Boss wrecks are Jackpots defended while stripping.

function gadget:GetInfo()
	return {
		name = "ARPG Salvage & Reclaim Jackpot Loot",
		desc = "Hooks AllowFeatureBuildStep & FeatureDestroyed to turn BAR reclaim into the ARPG loot & material economy",
		author = "Argon",
		date = "2026-11-01",
		license = "GNU GPL, v2 or later",
		layer = 10,
		enabled = true,
	}
end

local BiomeConfig = VFS and VFS.Include and VFS.Include("luarules/configs/arpg_biomes.lua")
	or require("luarules/configs/arpg_biomes")
local PartsDB = VFS and VFS.Include and VFS.Include("luarules/configs/arpg_parts_db.lua")
	or require("luarules/configs/arpg_parts_db")

local Biomes = BiomeConfig.Biomes
local Parts = PartsDB.Parts

if gadgetHandler and not gadgetHandler:IsSyncedCode() then
	return false
end

local activeReclaims = {} -- [featureID] = { builderID, builderTeam, maxMetal, lastMetal, lastFrame, isBossWreck, isJackpot, defenseTriggered, accumFraction }
local bossWrecks = {} -- [featureID] = { biomeId, title, jackpotMaterials, x, z }

-- Sorted part drop pools by Tech Tier so Boss & Jackpot wrecks award tangible hardware
local TierPartPools = {
	[1] = { "mod_pile_bunker", "mod_radar_scanner", "wpn_pulse_laser", "frame_scout_strider" },
	[2] = {
		"wpn_gauss_repeater",
		"wpn_plasma_howitzer",
		"wpn_emp_paralyzer",
		"loco_hover_thrusters",
		"loco_spider_allterrain",
		"core_cryo_sink",
		"mod_thermal_purge",
		"mod_magnetic_salvage",
		"frame_siege_goliath",
	},
	[3] = {
		"wpn_dgun_condenser",
		"wpn_unique_massless_recoil",
		"wpn_unique_topological_scrambler",
		"core_overclock_tokamak",
		"core_siphon_capacitor",
		"loco_boost_treads",
		"mod_siege_bastion",
	},
	[4] = {
		"wpn_unique_neutron_mass_pulse",
		"frame_experimental_archon",
	},
}

local function computeMaterialYieldFromMetal(metalExtracted, biome, isJackpot)
	local weights = (biome and biome.materialWeights) or Biomes.salvage_yard.materialWeights
	local scale = (metalExtracted / 22.0) * (isJackpot and 1.75 or 1.0)
	local yield = {}
	for matKey, w in pairs(weights) do
		local raw = scale * w
		local whole = math.floor(raw + 0.45)
		if whole > 0 then
			yield[matKey] = whole
		end
	end
	if isJackpot and (yield.reclaimed_alloy or 0) < 2 then
		yield.reclaimed_alloy = 2
	end
	return yield
end

local function registerBossWreck(featureID, biomeId, x, z)
	local biome = Biomes[biomeId] or Biomes.salvage_yard
	bossWrecks[featureID] = {
		featureID = featureID,
		biomeId = biomeId,
		title = biome.bossTitle .. " WRECKAGE JACKPOT",
		jackpotMaterials = biome.bossJackpotMaterials,
		x = x,
		z = z,
	}
	if GG and GG.ARPG_Map and GG.ARPG_Map.wreckRegistry then
		GG.ARPG_Map.wreckRegistry[featureID] = {
			featureID = featureID,
			isJackpot = true,
			isBossWreck = true,
			metal = 3500 * (biome.tier or 1),
			energy = 2500 * (biome.tier or 1),
			tier = biome.tier or 1,
			biomeId = biomeId,
		}
	end
	if Spring and Spring.SetFeatureResources then
		local m = 3500 * (biome.tier or 1)
		local e = 2500 * (biome.tier or 1)
		-- Longer reclaimTime so stripping a Boss Jackpot is a high-stakes tactical channel
		Spring.SetFeatureResources(featureID, m, m, e, e, 1.0, 900 * (biome.tier or 1))
	end
	if Spring and Spring.SetGameRulesParam then
		Spring.SetGameRulesParam("arpg_boss_wreck_id", featureID)
		Spring.SetGameRulesParam("arpg_boss_wreck_progress", 0)
	end
end

function gadget:AllowFeatureBuildStep(builderID, builderTeam, featureID, featureDefID, step)
	-- Positive step is construction/resurrection; negative step is Reclaim!
	if step >= 0 then
		return true
	end

	local frame = (Spring and Spring.GetGameFrame and Spring.GetGameFrame()) or 0
	local metalLeft, maxMetal, energyLeft, maxEnergy, reclaimLeft = 100, 100, 50, 50, 0.5
	if Spring and Spring.GetFeatureResources then
		local m, mm, e, me, rl = Spring.GetFeatureResources(featureID)
		if m then
			metalLeft, maxMetal, energyLeft, maxEnergy, reclaimLeft = m, mm, e, me, rl
		end
	end

	local mapReg = (GG and GG.ARPG_Map and GG.ARPG_Map.wreckRegistry and GG.ARPG_Map.wreckRegistry[featureID]) or nil
	local bossReg = bossWrecks[featureID]
	local isBossWreck = (bossReg ~= nil) or (mapReg and mapReg.isBossWreck) or false
	local isOverclockedReactor = (mapReg and mapReg.isOverclockedReactor) or false
	local isJackpot = isBossWreck or isOverclockedReactor or (mapReg and mapReg.isJackpot) or false

	local rec = activeReclaims[featureID]
	if not rec then
		rec = {
			builderID = builderID,
			builderTeam = builderTeam,
			maxMetal = math.max(1, maxMetal or 100),
			lastMetal = metalLeft or 100,
			lastFrame = frame,
			isBossWreck = isBossWreck,
			isOverclockedReactor = isOverclockedReactor,
			isJackpot = isJackpot,
			defenseTriggered = false,
			accumMetal = 0,
		}
		activeReclaims[featureID] = rec
	end

	local deltaMetal = math.max(0, rec.lastMetal - metalLeft)
	rec.lastMetal = metalLeft
	rec.lastFrame = frame
	rec.builderID = builderID
	rec.accumMetal = rec.accumMetal + deltaMetal

	-- Trigger Overclocked Reactor Wreck Telegraphed Plasma Shockwave on first reclaim step!
	if isOverclockedReactor and not rec.defenseTriggered then
		rec.defenseTriggered = true
		local rx = (mapReg and mapReg.x) or 2048
		local rz = (mapReg and mapReg.z) or 2048
		if GG and GG.ARPG_Director and GG.ARPG_Director.ScheduleTelegraph then
			GG.ARPG_Director.ScheduleTelegraph("overclocked_reactor_discharge", rx, rz, 165, 45, 190, nil)
		end
	end

	-- Trigger Boss Wreck Salvage Defense Wave on first reclaim step!
	if isBossWreck and not rec.defenseTriggered then
		rec.defenseTriggered = true
		local fx, _, fz = 2048, 0, 2048
		if Spring and Spring.GetFeaturePosition then
			local px, py, pz = Spring.GetFeaturePosition(featureID)
			if px then
				fx, fz = px, pz
			end
		elseif bossReg then
			fx, fz = bossReg.x, bossReg.z
		end
		if GG and GG.ARPG_Director and GG.ARPG_Director.SpawnSalvageDefenseWave then
			GG.ARPG_Director.SpawnSalvageDefenseWave(fx, fz, builderID)
		end
		if Spring and Spring.Echo then
			Spring.Echo("[ARPG SALVAGE ALERT] Stripping Experimental Boss Wreck! Horde Packs converging on your lathe signal!")
		end
	end

	-- Stream materials every ~30 metal reclaimed during the channel (shared across Co-Op party)
	if rec.accumMetal >= 30 and GG and GG.ARPG_Assembly then
		local zone = GG.ARPG_Map and GG.ARPG_Map.GetCurrentZone and GG.ARPG_Map.GetCurrentZone()
		local biome = (zone and zone.biome) or Biomes.salvage_yard
		local matYield = computeMaterialYieldFromMetal(rec.accumMetal, biome, isJackpot)
		local partyHeroes = (GG.ARPG_Hero and GG.ARPG_Hero.GetAllHeroUnitIDs and GG.ARPG_Hero.GetAllHeroUnitIDs()) or { builderID }
		if #partyHeroes == 0 then
			partyHeroes = { builderID }
		end
		for i = 1, #partyHeroes do
			GG.ARPG_Assembly.AddMaterials(partyHeroes[i], matYield)
		end

		-- Apply Lazarus Reclaim-Siphon healing if mounted
		local heroState = GG.ARPG_Assembly.GetHeroState(builderID)
		if heroState and heroState.budget and Spring and Spring.GetUnitHealth and Spring.SetUnitHealth then
			local healRatio = heroState.budget.reclaimHealRatio or 0.12
			local curH, maxH = Spring.GetUnitHealth(builderID)
			if curH and maxH and curH < maxH then
				Spring.SetUnitHealth(builderID, math.min(maxH, curH + rec.accumMetal * healRatio))
			end
		end
		rec.accumMetal = 0
	end

	-- Publish active salvage channel progress for LuaUI HUD
	if Spring and Spring.SetUnitRulesParam then
		local progress = math.max(0.0, math.min(1.0, 1.0 - (reclaimLeft or (metalLeft / rec.maxMetal))))
		Spring.SetUnitRulesParam(builderID, "arpg_salvage_active", 1)
		Spring.SetUnitRulesParam(builderID, "arpg_salvage_progress", math.floor(progress * 100))
		Spring.SetUnitRulesParam(builderID, "arpg_salvage_is_boss", isBossWreck and 1 or 0)
		if isBossWreck and Spring.SetGameRulesParam then
			Spring.SetGameRulesParam("arpg_boss_wreck_progress", math.floor(progress * 100))
		end
	end

	return true
end

function gadget:FeatureDestroyed(featureID)
	local rec = activeReclaims[featureID]
	local frame = (Spring and Spring.GetGameFrame and Spring.GetGameFrame()) or 0

	if rec and (frame - rec.lastFrame <= 3) then
		local builderID = rec.builderID
		local zone = GG and GG.ARPG_Map and GG.ARPG_Map.GetCurrentZone and GG.ARPG_Map.GetCurrentZone()
		local biome = (zone and zone.biome) or Biomes.salvage_yard
		local tier = (biome and biome.tier) or 1

		if GG and GG.ARPG_Assembly then
			-- Flush any remaining metal materials
			local leftover = math.max(25, rec.lastMetal + rec.accumMetal)
			local finalMats = computeMaterialYieldFromMetal(leftover, biome, rec.isJackpot)
			GG.ARPG_Assembly.AddMaterials(builderID, finalMats)

			if rec.isBossWreck then
				-- Award Full Experimental Boss Jackpot Materials + Unlock Next Tech Tier + Machine Part
				local bossData = bossWrecks[featureID]
				local jackpotMats = (bossData and bossData.jackpotMaterials) or biome.bossJackpotMaterials
				GG.ARPG_Assembly.AddMaterials(builderID, jackpotMats)

				local heroState = GG.ARPG_Assembly.GetHeroState(builderID)
				if heroState then
					heroState.unlockedTechTier = math.min(4, math.max(heroState.unlockedTechTier or 1, tier + 1))
				end

				local pool = TierPartPools[math.min(4, tier + 1)] or TierPartPools[tier] or TierPartPools[1]
				local rewardPart = pool[((featureID or 1) % #pool) + 1]
				GG.ARPG_Assembly.GrantPartDrop(builderID, rewardPart)

				if GG.ARPG_ZoneManager and GG.ARPG_ZoneManager.OnBossWreckSalvaged then
					GG.ARPG_ZoneManager.OnBossWreckSalvaged(builderID, featureID)
				end
			elseif rec.isJackpot then
				-- High-value Foundry Cache / Elite Wreck drops a part from current tier
				local pool = TierPartPools[tier] or TierPartPools[1]
				local rewardPart = pool[((featureID or 1) % #pool) + 1]
				GG.ARPG_Assembly.GrantPartDrop(builderID, rewardPart)
			end
		end

		if Spring and Spring.SetUnitRulesParam then
			Spring.SetUnitRulesParam(builderID, "arpg_salvage_active", 0)
			Spring.SetUnitRulesParam(builderID, "arpg_salvage_progress", 100)
		end
	end

	activeReclaims[featureID] = nil
	bossWrecks[featureID] = nil
	if GG and GG.ARPG_Map and GG.ARPG_Map.wreckRegistry then
		GG.ARPG_Map.wreckRegistry[featureID] = nil
	end
end

GG = GG or {}
GG.ARPG_Salvage = {
	RegisterBossWreck = registerBossWreck,
	ComputeMaterialYieldFromMetal = computeMaterialYieldFromMetal,
	GetActiveReclaim = function(featureID)
		return activeReclaims[featureID]
	end,
}

return GG.ARPG_Salvage
