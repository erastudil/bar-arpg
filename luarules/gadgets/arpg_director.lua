-- luarules/gadgets/arpg_director.lua
-- Horde Pack Director, Physical Elite Affixes, Experimental Superunit Bosses,
-- and "Map-Never-Lies" Telegraphed Heavy Attack Engine (Zero Random One-Shot Deaths).

function gadget:GetInfo()
	return {
		name = "ARPG Horde Director & Telegraph Engine",
		desc = "Spawns horde packs, elites, and experimental bosses; enforces telegraphed heavy damage & anti-oneshot gate",
		author = "Argon",
		date = "2026-11-01",
		license = "GNU GPL, v2 or later",
		layer = 20,
		enabled = true,
	}
end

local BiomeConfig = VFS and VFS.Include and VFS.Include("luarules/configs/arpg_biomes.lua")
	or require("luarules/configs/arpg_biomes")
local Biomes = BiomeConfig.Biomes

if gadgetHandler and not gadgetHandler:IsSyncedCode() then
	return false
end

local SOURCE_AFFIX = "arpg_elite_affix"

local EliteAffixes = {
	OVERCLOCKED = {
		name = "Overclocked Servos",
		speedMult = 1.35,
		reloadMult = 0.75,
		healthMult = 1.40,
	},
	REACTIVE_PLATING = {
		name = "Reactive Tungsten Plating",
		speedMult = 0.90,
		reloadMult = 1.00,
		healthMult = 2.40,
	},
	THERMAL_PROJECTOR = {
		name = "Thermal Vent Projector",
		speedMult = 1.10,
		reloadMult = 0.85,
		healthMult = 1.65,
		addsHeatOnHit = 8.0,
	},
	SIEGE_MORTAR = {
		name = "Telegraphed Siege Mortar",
		speedMult = 0.95,
		reloadMult = 1.10,
		healthMult = 1.80,
		periodicTelegraph = true,
	},
}

local AffixKeys = {
	"OVERCLOCKED",
	"REACTIVE_PLATING",
	"THERMAL_PROJECTOR",
	"SIEGE_MORTAR",
}

local activeEnemies = {} -- [unitID] = { isElite, affixKey, isBoss, biomeId }
local activeBossID = nil
local activeTelegraphs = {} -- list of { id, kind, x, z, radius, startFrame, detonateFrame, damage, sourceUnitID }
local nextTelegraphId = 1

local function getEnemyTeamID()
	if Spring and Spring.GetGaiaTeamID then
		return Spring.GetGaiaTeamID()
	end
	return 1
end

local function resolveValidUnitDefName(candidate, fallback)
	if not UnitDefNames then
		return candidate or fallback or "armpw"
	end
	if candidate and UnitDefNames[candidate] then
		return candidate
	end
	if fallback and UnitDefNames[fallback] then
		return fallback
	end
	local defaults = { "armpw", "corak", "armzeus", "armbanth", "corkorg" }
	for i = 1, #defaults do
		if UnitDefNames[defaults[i]] then
			return defaults[i]
		end
	end
	for name, _ in pairs(UnitDefNames) do
		return name
	end
	return "armpw"
end

-- ============================================================================
-- "Map-Never-Lies" Ground Telegraph Scheduling & Execution
-- ============================================================================
local function scheduleTelegraph(kind, x, z, radius, windupFrames, damage, sourceUnitID)
	local frame = (Spring and Spring.GetGameFrame and Spring.GetGameFrame()) or 0
	windupFrames = math.max(36, tonumber(windupFrames) or 50) -- Minimum 1.2s clear warning!
	local entry = {
		id = nextTelegraphId,
		kind = kind or "heavy_strike",
		x = x,
		z = z,
		radius = radius or 135,
		startFrame = frame,
		detonateFrame = frame + windupFrames,
		damage = damage or 450,
		sourceUnitID = sourceUnitID,
	}
	nextTelegraphId = nextTelegraphId + 1
	activeTelegraphs[#activeTelegraphs + 1] = entry

	if Spring and Spring.SetGameRulesParam then
		Spring.SetGameRulesParam("arpg_telegraph_count", #activeTelegraphs)
		local idx = #activeTelegraphs
		Spring.SetGameRulesParam("arpg_tele_" .. idx .. "_x", math.floor(entry.x))
		Spring.SetGameRulesParam("arpg_tele_" .. idx .. "_z", math.floor(entry.z))
		Spring.SetGameRulesParam("arpg_tele_" .. idx .. "_r", math.floor(entry.radius))
		Spring.SetGameRulesParam("arpg_tele_" .. idx .. "_det", entry.detonateFrame)
		Spring.SetGameRulesParam("arpg_tele_" .. idx .. "_kind", entry.kind)
	end

	return entry
end

local function spawnZoneEncounters(blueprint)
	if not blueprint then
		return
	end
	-- Clear prior enemies
	if Spring and Spring.DestroyUnit then
		for uID, _ in pairs(activeEnemies) do
			if Spring.ValidUnitID and Spring.ValidUnitID(uID) then
				Spring.DestroyUnit(uID, false, true)
			end
		end
	end
	activeEnemies = {}
	activeBossID = nil
	activeTelegraphs = {}

	local biome = blueprint.biome or Biomes.salvage_yard
	local enemyTeam = getEnemyTeamID()

	-- 1. Spawn Swarm Packs, Physical-Affix Elites, and Choke Turrets
	for i = 1, #blueprint.encounterPacks do
		local pack = blueprint.encounterPacks[i]
		for s = 1, pack.swarmCount do
			local angle = (s / math.max(1, pack.swarmCount)) * math.pi * 2.0
			local r = 45 + (s % 4) * 35
			local ux = pack.x + math.cos(angle) * r
			local uz = pack.z + math.sin(angle) * r
			local uy = (Spring and Spring.GetGroundHeight and Spring.GetGroundHeight(ux, uz)) or biome.baseHeight
			local rawName = biome.swarmUnits[((s - 1) % #biome.swarmUnits) + 1]
			local defName = resolveValidUnitDefName(rawName, "armpw")
			if Spring and Spring.CreateUnit then
				local uID = Spring.CreateUnit(defName, ux, uy, uz, s % 4, enemyTeam)
				if uID then
					activeEnemies[uID] = { isElite = false, isBoss = false, biomeId = blueprint.biomeId }
				end
			end
		end

		for e = 1, pack.eliteCount do
			local angle = (e / math.max(1, pack.eliteCount)) * math.pi * 2.0 + 0.5
			local ux = pack.x + math.cos(angle) * 65
			local uz = pack.z + math.sin(angle) * 65
			local uy = (Spring and Spring.GetGroundHeight and Spring.GetGroundHeight(ux, uz)) or biome.baseHeight
			local rawName = biome.eliteUnits[((e - 1) % #biome.eliteUnits) + 1]
			local defName = resolveValidUnitDefName(rawName, "armzeus")
			local affixKey = AffixKeys[((i + e) % #AffixKeys) + 1]
			local affix = EliteAffixes[affixKey]

			if Spring and Spring.CreateUnit then
				local uID = Spring.CreateUnit(defName, ux, uy, uz, 0, enemyTeam)
				if uID then
					activeEnemies[uID] = {
						isElite = true,
						affixKey = affixKey,
						affix = affix,
						isBoss = false,
						biomeId = blueprint.biomeId,
					}
					if GG and GG.UnitAttributes and affix then
						GG.UnitAttributes.SetUnitModifier(uID, "maxHealth", affix.healthMult, SOURCE_AFFIX)
						GG.UnitAttributes.SetUnitModifier(uID, "speed", affix.speedMult, SOURCE_AFFIX)
					end
					if Spring.SetUnitRulesParam then
						Spring.SetUnitRulesParam(uID, "arpg_elite_affix", affixKey)
					end
				end
			end
		end

		for t = 1, (pack.turretCount or 0) do
			local angle = (t - 1) * math.pi + 0.25
			local ux = pack.x + math.cos(angle) * 110
			local uz = pack.z + math.sin(angle) * 110
			local uy = (Spring and Spring.GetGroundHeight and Spring.GetGroundHeight(ux, uz)) or biome.baseHeight
			local rawName = biome.turretUnits[((t - 1) % #biome.turretUnits) + 1]
			local defName = resolveValidUnitDefName(rawName, "armllt")
			if Spring and Spring.CreateUnit then
				local uID = Spring.CreateUnit(defName, ux, uy, uz, 0, enemyTeam)
				if uID then
					activeEnemies[uID] = { isElite = false, isBoss = false, biomeId = blueprint.biomeId }
				end
			end
		end
	end

	-- 2. Spawn Zone Experimental Superunit Boss in Boss Arena
	local bossArena = blueprint.bossArena
	if bossArena then
		local bossDef = resolveValidUnitDefName(biome.bossUnit, biome.bossFallbackUnit)
		local by = (Spring and Spring.GetGroundHeight and Spring.GetGroundHeight(bossArena.x, bossArena.z)) or bossArena.elevation
		local bossID = nil
		if Spring and Spring.CreateUnit then
			bossID = Spring.CreateUnit(bossDef, bossArena.x, by, bossArena.z, 0, enemyTeam)
		end
		if not bossID then
			bossID = 9000 + blueprint.zoneDepth
		end
		activeBossID = bossID
		activeEnemies[bossID] = {
			isElite = true,
			isBoss = true,
			bossTitle = biome.bossTitle,
			biomeId = blueprint.biomeId,
			x = bossArena.x,
			z = bossArena.z,
		}
		if Spring and Spring.SetGameRulesParam then
			Spring.SetGameRulesParam("arpg_boss_unit_id", bossID)
			Spring.SetGameRulesParam("arpg_boss_alive", 1)
			Spring.SetGameRulesParam("arpg_boss_title", biome.bossTitle)
		end
	end
end

-- Spawns converging scavenger ambush packs when the player channels reclaim on a Boss Jackpot Wreck
local function spawnSalvageDefenseWave(wreckX, wreckZ, builderID)
	local zone = GG and GG.ARPG_Map and GG.ARPG_Map.GetCurrentZone and GG.ARPG_Map.GetCurrentZone()
	local biome = (zone and zone.biome) or Biomes.salvage_yard
	local enemyTeam = getEnemyTeamID()
	local spawned = {}

	for pod = 1, 3 do
		local podAngle = (pod - 1) * (2.0 * math.pi / 3.0)
		local podX = wreckX + math.cos(podAngle) * 380
		local podZ = wreckZ + math.sin(podAngle) * 380
		for u = 1, 4 do
			local ux = podX + (u - 2) * 28
			local uz = podZ + (u % 2) * 28
			local uy = (Spring and Spring.GetGroundHeight and Spring.GetGroundHeight(ux, uz)) or biome.baseHeight
			local rawName = biome.swarmUnits[((u - 1) % #biome.swarmUnits) + 1]
			local defName = resolveValidUnitDefName(rawName, "armpw")
			if Spring and Spring.CreateUnit then
				local uID = Spring.CreateUnit(defName, ux, uy, uz, 0, enemyTeam)
				if uID then
					activeEnemies[uID] = { isElite = false, isBoss = false, biomeId = biome.id }
					spawned[#spawned + 1] = uID
					if builderID and Spring.GiveOrderToUnit and CMD and CMD.ATTACK then
						Spring.GiveOrderToUnit(uID, CMD.ATTACK, { builderID }, {})
					end
				end
			end
		end
	end

	return spawned
end

-- Anti-One-Shot Doctrine: Un-telegraphed hits can never remove > 35% of Hero maxHealth in a single frame
function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	if GG and GG.ARPG_Hero and unitID == GG.ARPG_Hero.GetHeroUnitID(unitTeam) then
		local asm = GG.ARPG_Assembly and GG.ARPG_Assembly.GetHeroState(unitID)
		local maxH = (asm and asm.budget and asm.budget.maxHealth) or 3500
		local maxUnTelegraphedBurst = maxH * 0.35
		if damage > maxUnTelegraphedBurst then
			damage = maxUnTelegraphedBurst
		end
		-- Apply Thermal Projector elite affix heat transfer
		if attackerID and activeEnemies[attackerID] and activeEnemies[attackerID].affixKey == "THERMAL_PROJECTOR" and asm then
			asm.heat = math.min(asm.maxHeat * 1.25, asm.heat + 8.0)
		end
	end
	return damage, 1.0
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID)
	local info = activeEnemies[unitID]
	if not info then
		return
	end

	if info.isBoss then
		activeBossID = nil
		if Spring and Spring.SetGameRulesParam then
			Spring.SetGameRulesParam("arpg_boss_alive", 0)
		end
		-- Spawn or register Experimental Boss Wreckage Jackpot on the battlefield!
		local bx, bz = info.x or 3200, info.z or 3200
		if Spring and Spring.GetUnitPosition then
			local px, _, pz = Spring.GetUnitPosition(unitID)
			if px then
				bx, bz = px, pz
			end
		end
		local by = (Spring and Spring.GetGroundHeight and Spring.GetGroundHeight(bx, bz)) or 160
		local wreckID = nil
		if Spring and Spring.CreateFeature then
			local corpseDef = (FeatureDefNames and FeatureDefNames["corkorg_dead"] and "corkorg_dead")
				or (FeatureDefNames and FeatureDefNames["armcom_dead"] and "armcom_dead")
				or "armcom_dead"
			wreckID = Spring.CreateFeature(corpseDef, bx, by, bz, 0, getEnemyTeamID())
		end
		if not wreckID then
			wreckID = 50000 + unitID
		end
		if GG and GG.ARPG_Salvage and GG.ARPG_Salvage.RegisterBossWreck then
			GG.ARPG_Salvage.RegisterBossWreck(wreckID, info.biomeId, bx, bz)
		end
		if GG and GG.ARPG_ZoneManager and GG.ARPG_ZoneManager.OnBossDefeated then
			GG.ARPG_ZoneManager.OnBossDefeated(unitID, wreckID)
		end
	end

	activeEnemies[unitID] = nil
end

function gadget:GameFrame(frame)
	-- 1. Resolve Telegraphed Heavy Attacks upon reaching detonateFrame
	for i = #activeTelegraphs, 1, -1 do
		local t = activeTelegraphs[i]
		if frame >= t.detonateFrame then
			if Spring and Spring.GetUnitsInCylinder and Spring.AddUnitDamage then
				local victims = Spring.GetUnitsInCylinder(t.x, t.z, t.radius)
				if victims then
					for v = 1, #victims do
						local vID = victims[v]
						if vID ~= t.sourceUnitID then
							Spring.AddUnitDamage(vID, t.damage, 0, t.sourceUnitID or -1, -1)
						end
					end
				end
			end
			table.remove(activeTelegraphs, i)
		end
	end

	-- 2. Schedule Periodic Environmental Hazard Telegraphs & Boss Heavy Salvo Telegraphs
	if frame % 60 == 0 then
		local zone = GG and GG.ARPG_Map and GG.ARPG_Map.GetCurrentZone and GG.ARPG_Map.GetCurrentZone()
		if zone and zone.hazardZones then
			for i = 1, #zone.hazardZones do
				local hz = zone.hazardZones[i]
				if ((frame + hz.phaseOffset) % hz.periodFrames) < 60 then
					scheduleTelegraph(hz.hazardType, hz.x, hz.z, hz.radius, hz.telegraphFrames, hz.damage, nil)
				end
			end
		end

		if activeBossID and GG and GG.ARPG_Hero then
			local heroID = GG.ARPG_Hero.GetHeroUnitID(0)
			if heroID and Spring and Spring.GetUnitPosition then
				local hx, _, hz = Spring.GetUnitPosition(heroID)
				local bx, _, bz = Spring.GetUnitPosition(activeBossID)
				if hx and bx then
					local dist = math.sqrt((hx - bx) ^ 2 + (hz - bz) ^ 2)
					if dist <= 750 then
						local biome = (zone and zone.biome) or Biomes.salvage_yard
						scheduleTelegraph(
							"boss_siege_salvo",
							hx,
							hz,
							biome.hazardRadius or 140,
							biome.hazardTelegraphFrames or 55,
							(biome.hazardDamagePerTick or 120) * 1.6,
							activeBossID
						)
					end
				end
			end
		end
	end
end

GG = GG or {}
GG.ARPG_Director = {
	SpawnZoneEncounters = spawnZoneEncounters,
	SpawnSalvageDefenseWave = spawnSalvageDefenseWave,
	ScheduleTelegraph = scheduleTelegraph,
	GetActiveTelegraphs = function()
		return activeTelegraphs
	end,
	GetActiveBossID = function()
		return activeBossID
	end,
}

return GG.ARPG_Director
