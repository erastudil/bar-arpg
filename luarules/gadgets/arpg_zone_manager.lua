-- luarules/gadgets/arpg_zone_manager.lua
-- Series-of-Maps Campaign & Zone Progression Manager for BAR Sci-Fi ARPG ("WRECKAGE PROTOCOL")
-- Manages zone transitions from Salvage Yards -> Derelict Factories -> Automated War-Foundries
-- -> Experimental Gantry Citadels while preserving modular assembly & material stockpiles.

function gadget:GetInfo()
	return {
		name = "ARPG Zone Progression Manager",
		desc = "Manages the procedural map series, boss jackpot objectives, and warp gate extraction transitions",
		author = "Argon",
		date = "2026-11-01",
		license = "GNU GPL, v2 or later",
		layer = 25,
		enabled = true,
	}
end

if gadgetHandler and not gadgetHandler:IsSyncedCode() then
	return false
end

local runState = {
	runSeed = 424242,
	zoneDepth = 1,
	stage = "STAGE_HUNTING_BOSS", -- STAGE_HUNTING_BOSS | STAGE_STRIPPING_BOSS_JACKPOT | STAGE_EXTRACTION_READY
	extractionUnlocked = false,
	bossDefeated = false,
	bossWreckSalvaged = false,
}

local function syncZoneManagerRulesParams()
	if not Spring or not Spring.SetGameRulesParam then
		return
	end
	Spring.SetGameRulesParam("arpg_run_seed", runState.runSeed)
	Spring.SetGameRulesParam("arpg_zone_depth", runState.zoneDepth)
	Spring.SetGameRulesParam("arpg_zone_stage", runState.stage)
	Spring.SetGameRulesParam("arpg_extraction_unlocked", runState.extractionUnlocked and 1 or 0)
	Spring.SetGameRulesParam("arpg_boss_wreck_salvaged", runState.bossWreckSalvaged and 1 or 0)
end

local function startZone(seed, depth, preserveHeroState)
	runState.runSeed = tonumber(seed) or runState.runSeed
	runState.zoneDepth = math.max(1, tonumber(depth) or 1)
	runState.stage = "STAGE_HUNTING_BOSS"
	runState.extractionUnlocked = false
	runState.bossDefeated = false
	runState.bossWreckSalvaged = false

	local bp = nil
	if GG and GG.ARPG_Map and GG.ARPG_Map.GenerateZone then
		bp = GG.ARPG_Map.GenerateZone(runState.runSeed, runState.zoneDepth, nil)
	end
	if GG and GG.ARPG_Hero and GG.ARPG_Hero.SpawnOrRelocateHero then
		GG.ARPG_Hero.SpawnOrRelocateHero(0, preserveHeroState)
	end
	if bp and GG and GG.ARPG_Director and GG.ARPG_Director.SpawnZoneEncounters then
		GG.ARPG_Director.SpawnZoneEncounters(bp)
	end

	syncZoneManagerRulesParams()
	return bp
end

local function onBossDefeated(bossUnitID, bossWreckFeatureID)
	runState.bossDefeated = true
	runState.stage = "STAGE_STRIPPING_BOSS_JACKPOT"
	-- Extraction unlocks once boss is dead, but stripping the Boss Wreck Jackpot yields the core prize!
	runState.extractionUnlocked = true
	syncZoneManagerRulesParams()
	if Spring and Spring.Echo then
		Spring.Echo("[ARPG Objective] Experimental Boss destroyed! Reclaim its Wreckage Jackpot for Singularity Cores, then head to the Warp Extraction Gate!")
	end
end

local function onBossWreckSalvaged(heroUnitID, bossWreckFeatureID)
	runState.bossWreckSalvaged = true
	runState.extractionUnlocked = true
	runState.stage = "STAGE_EXTRACTION_READY"
	syncZoneManagerRulesParams()
	if Spring and Spring.Echo then
		Spring.Echo("[ARPG Objective] Boss Jackpot stripped clean! Orbital Warp Extraction Gate ready for next frontier sector!")
	end
end

local function advanceToNextZone()
	if not runState.extractionUnlocked then
		return false, "EXTRACTION_LOCKED_DEFEAT_BOSS_FIRST"
	end
	local nextDepth = runState.zoneDepth + 1
	local bp = startZone(runState.runSeed, nextDepth, true)
	return true, bp
end

function gadget:GameStart()
	local modOpts = (Spring and Spring.GetModOptions and Spring.GetModOptions()) or {}
	local seed = tonumber(modOpts.arpg_seed) or 424242
	startZone(seed, 1, false)
end

function gadget:GameFrame(frame)
	-- Check if Hero has entered the Extraction Gate circle while extraction is unlocked
	if frame % 30 == 0 and runState.extractionUnlocked then
		local zone = GG and GG.ARPG_Map and GG.ARPG_Map.GetCurrentZone and GG.ARPG_Map.GetCurrentZone()
		local heroID = GG and GG.ARPG_Hero and GG.ARPG_Hero.GetHeroUnitID and GG.ARPG_Hero.GetHeroUnitID(0)
		if zone and zone.extractionGate and heroID and Spring and Spring.GetUnitPosition then
			local hx, _, hz = Spring.GetUnitPosition(heroID)
			if hx then
				local dx = hx - zone.extractionGate.x
				local dz = hz - zone.extractionGate.z
				local dist = math.sqrt(dx * dx + dz * dz)
				if dist <= (zone.extractionGate.radius * 0.75) then
					advanceToNextZone()
				end
			end
		end
	end
end

function gadget:RecvLuaMsg(msg, playerID)
	if msg == "arpg:extract_now" then
		advanceToNextZone()
	end
end

GG = GG or {}
GG.ARPG_ZoneManager = {
	StartZone = startZone,
	OnBossDefeated = onBossDefeated,
	OnBossWreckSalvaged = onBossWreckSalvaged,
	AdvanceToNextZone = advanceToNextZone,
	GetRunState = function()
		return runState
	end,
}

return GG.ARPG_ZoneManager
