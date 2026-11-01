-- luarules/gadgets/arpg_save_persistence.lua
-- Campaign & Modular Assembly Save/Load Persistence Engine for BAR Sci-Fi ARPG ("WRECKAGE PROTOCOL")
-- Addresses Muse Letter 011 Risk #3: serializes & restores runSeed, zoneDepth, unlockedTechTier,
-- bolted-on modular loadout, salvaged material stockpile, and machined part inventory across sessions.

function gadget:GetInfo()
	return {
		name = "ARPG Campaign Save & Persistence",
		desc = "Deterministic serialization and persistence for modular assembly, materials, and zone progression",
		author = "Argon",
		date = "2026-11-01",
		license = "GNU GPL, v2 or later",
		layer = 30,
		enabled = true,
	}
end

if gadgetHandler and not gadgetHandler:IsSyncedCode() then
	return false
end

local savedSlots = {} -- In-memory & config-backed store: [slotName] = serializedString

local function sortedKeys(tbl)
	local keys = {}
	for k, _ in pairs(tbl or {}) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- Deterministic key=value serializer safe for config strings and save files
local function SerializePlayerRunState(heroUnitID)
	local asm = GG and GG.ARPG_Assembly and GG.ARPG_Assembly.GetHeroState(heroUnitID)
	local zm = GG and GG.ARPG_ZoneManager and GG.ARPG_ZoneManager.GetRunState()
	if not asm then
		return nil, "NO_HERO_STATE"
	end

	local tokens = {}
	tokens[#tokens + 1] = "v=1"
	tokens[#tokens + 1] = "seed=" .. tostring((zm and zm.runSeed) or 424242)
	tokens[#tokens + 1] = "depth=" .. tostring((zm and zm.zoneDepth) or 1)
	tokens[#tokens + 1] = "tech=" .. tostring(asm.unlockedTechTier or 1)

	for _, slotKey in ipairs(sortedKeys(asm.loadout)) do
		tokens[#tokens + 1] = "slot." .. slotKey .. "=" .. tostring(asm.loadout[slotKey])
	end

	for _, matKey in ipairs(sortedKeys(asm.materials)) do
		tokens[#tokens + 1] = "mat." .. matKey .. "=" .. tostring(math.floor(asm.materials[matKey] or 0))
	end

	local invList = {}
	for _, partId in ipairs(sortedKeys(asm.inventoryParts)) do
		if asm.inventoryParts[partId] then
			invList[#invList + 1] = partId
		end
	end
	tokens[#tokens + 1] = "inv=" .. table.concat(invList, ",")

	return table.concat(tokens, ";")
end

local function DeserializePlayerRunState(serializedStr)
	if not serializedStr or serializedStr == "" then
		return nil, "EMPTY_SAVE_STRING"
	end

	local state = {
		runSeed = 424242,
		zoneDepth = 1,
		unlockedTechTier = 1,
		loadout = {},
		materials = {},
		inventoryParts = {},
	}

	for pair in string.gmatch(serializedStr, "[^;]+") do
		local eqPos = string.find(pair, "=", 1, true)
		if eqPos then
			local k = string.sub(pair, 1, eqPos - 1)
			local v = string.sub(pair, eqPos + 1)
			if k == "seed" then
				state.runSeed = tonumber(v) or 424242
			elseif k == "depth" then
				state.zoneDepth = tonumber(v) or 1
			elseif k == "tech" then
				state.unlockedTechTier = tonumber(v) or 1
			elseif string.sub(k, 1, 5) == "slot." then
				local slotName = string.sub(k, 6)
				state.loadout[slotName] = v
			elseif string.sub(k, 1, 4) == "mat." then
				local matName = string.sub(k, 5)
				state.materials[matName] = tonumber(v) or 0
			elseif k == "inv" then
				for partId in string.gmatch(v, "[^,]+") do
					state.inventoryParts[partId] = true
				end
			end
		end
	end

	return state
end

local function SaveCampaignSlot(slotName, heroUnitID)
	slotName = slotName or "slot_1"
	local payload, err = SerializePlayerRunState(heroUnitID)
	if not payload then
		return false, err
	end
	savedSlots[slotName] = payload
	if Spring and Spring.SetConfigString then
		Spring.SetConfigString("arpg_save_" .. slotName, payload)
	end
	return true, payload
end

local function LoadCampaignSlot(slotName, heroUnitID)
	slotName = slotName or "slot_1"
	local payload = savedSlots[slotName]
	if not payload and Spring and Spring.GetConfigString then
		payload = Spring.GetConfigString("arpg_save_" .. slotName, "")
	end
	local parsed, err = DeserializePlayerRunState(payload)
	if not parsed then
		return false, err
	end

	if heroUnitID and GG and GG.ARPG_Assembly then
		GG.ARPG_Assembly.InitHeroAssembly(heroUnitID, parsed)
	end
	if GG and GG.ARPG_ZoneManager then
		local rs = GG.ARPG_ZoneManager.GetRunState()
		if rs then
			rs.runSeed = parsed.runSeed
			rs.zoneDepth = parsed.zoneDepth
		end
	end
	return true, parsed
end

GG = GG or {}
GG.ARPG_Persistence = {
	SerializePlayerRunState = SerializePlayerRunState,
	DeserializePlayerRunState = DeserializePlayerRunState,
	SaveCampaignSlot = SaveCampaignSlot,
	LoadCampaignSlot = LoadCampaignSlot,
}

return GG.ARPG_Persistence
