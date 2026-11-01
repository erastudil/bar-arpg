-- luarules/gadgets/arpg_procgen_map.lua
-- Seeded Procedural Map Generation Engine for BAR Sci-Fi ARPG ("WRECKAGE PROTOCOL")
-- Transforms any BAR canvas map into a deterministic series of Scrap Frontier zones:
-- Salvage Yards -> Derelict Factories -> Automated War-Foundries -> Experimental Gantry Citadels.

function gadget:GetInfo()
	return {
		name = "ARPG Procedural Map Generator",
		desc = "Deterministic multi-biome heightmap, corridor ramp, wreck field, and boss arena generator",
		author = "Argon",
		date = "2026-11-01",
		license = "GNU GPL, v2 or later",
		layer = -95,
		enabled = true,
	}
end

local BiomeConfig = VFS and VFS.Include and VFS.Include("luarules/configs/arpg_biomes.lua")
	or require("luarules/configs/arpg_biomes")

local Biomes = BiomeConfig.Biomes
local BiomeSequence = BiomeConfig.BiomeSequence

-- ============================================================================
-- Deterministic PRNG (Bit-exact across Lua 5.1 / LuaJIT)
-- ============================================================================
local ProcRNG = {}
ProcRNG.__index = ProcRNG

function ProcRNG.new(seed)
	local s = math.floor(math.abs(tonumber(seed) or 1337)) % 2147483647
	if s == 0 then
		s = 1337
	end
	return setmetatable({ state = s }, ProcRNG)
end

function ProcRNG:nextInt()
	-- Park-Miller LCG (modulus 2^31 - 1, multiplier 48271) - exact in IEEE 754 double
	self.state = (self.state * 48271) % 2147483647
	return self.state
end

function ProcRNG:nextFloat()
	return self:nextInt() / 2147483647.0
end

function ProcRNG:rangeFloat(minVal, maxVal)
	return minVal + (maxVal - minVal) * self:nextFloat()
end

function ProcRNG:rangeInt(minVal, maxVal)
	if maxVal <= minVal then
		return minVal
	end
	return minVal + (self:nextInt() % (maxVal - minVal + 1))
end

function ProcRNG:choice(list)
	if not list or #list == 0 then
		return nil
	end
	return list[self:rangeInt(1, #list)]
end

-- ============================================================================
-- 2D Value Noise + FBM + Domain Warping
-- ============================================================================
local function hash2D(ix, iz, seed)
	local n = ix * 374761393 + iz * 668265263 + seed * 1442695041
	n = (n % 2147483647 + 2147483647) % 2147483647
	n = (n * 1103515245 + 12345) % 2147483647
	return (n / 2147483647.0) * 2.0 - 1.0
end

local function smoothstep(t)
	return t * t * (3.0 - 2.0 * t)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function valueNoise2D(x, z, seed)
	local ix = math.floor(x)
	local iz = math.floor(z)
	local fx = smoothstep(x - ix)
	local fz = smoothstep(z - iz)

	local v00 = hash2D(ix, iz, seed)
	local v10 = hash2D(ix + 1, iz, seed)
	local v01 = hash2D(ix, iz + 1, seed)
	local v11 = hash2D(ix + 1, iz + 1, seed)

	local vx0 = lerp(v00, v10, fx)
	local vx1 = lerp(v01, v11, fx)
	return lerp(vx0, vx1, fz)
end

local function fbm2D(x, z, seed, octaves)
	octaves = octaves or 4
	local total = 0.0
	local amplitude = 0.5
	local frequency = 1.0
	local norm = 0.0
	for i = 1, octaves do
		total = total + valueNoise2D(x * frequency, z * frequency, seed + i * 101) * amplitude
		norm = norm + amplitude
		amplitude = amplitude * 0.5
		frequency = frequency * 2.03
	end
	return total / math.max(0.0001, norm)
end

local function domainWarpedNoise2D(x, z, freq, warpStrength, seed)
	local qx = fbm2D(x * freq, z * freq, seed + 17, 3)
	local qz = fbm2D(x * freq + 5.2, z * freq + 1.3, seed + 53, 3)
	local wx = x + qx * warpStrength
	local wz = z + qz * warpStrength
	return fbm2D(wx * freq, wz * freq, seed + 97, 4)
end

-- ============================================================================
-- Point-to-Segment Distance for Corridor & Ramp Carving
-- ============================================================================
local function pointToSegmentProjection(px, pz, ax, az, bx, bz)
	local dx = bx - ax
	local dz = bz - az
	local lenSq = dx * dx + dz * dz
	if lenSq <= 0.0001 then
		local dist = math.sqrt((px - ax) ^ 2 + (pz - az) ^ 2)
		return dist, 0.0
	end
	local t = ((px - ax) * dx + (pz - az) * dz) / lenSq
	t = math.max(0.0, math.min(1.0, t))
	local projX = ax + t * dx
	local projZ = az + t * dz
	local dist = math.sqrt((px - projX) ^ 2 + (pz - projZ) ^ 2)
	return dist, t
end

-- ============================================================================
-- Pure Blueprint & Heightfield Synthesis (Usable in Synced Engine & Test Runner)
-- ============================================================================
local function BuildZoneBlueprint(seed, zoneDepth, mapSizeX, mapSizeZ, biomeIdOverride)
	zoneDepth = math.max(1, tonumber(zoneDepth) or 1)
	mapSizeX = tonumber(mapSizeX) or 4096
	mapSizeZ = tonumber(mapSizeZ) or 4096

	local rng = ProcRNG.new(seed + zoneDepth * 7919)
	local biomeId = biomeIdOverride or BiomeSequence[((zoneDepth - 1) % #BiomeSequence) + 1]
	local biome = Biomes[biomeId] or Biomes.salvage_yard

	local roomCount = rng:rangeInt(biome.roomCount.min, biome.roomCount.max)
	local margin = math.min(mapSizeX, mapSizeZ) * 0.12

	local nodes = {}
	local edges = {}

	-- Node 1: Drop Zone & Mobile Garage Pad
	nodes[1] = {
		id = 1,
		kind = "drop_zone",
		name = "Drop Pad & Mobile Garage",
		x = margin + rng:rangeFloat(40, 140),
		z = margin + rng:rangeFloat(40, 140),
		radius = 280,
		elevation = biome.baseHeight,
		hasGarage = true,
		pillars = {},
	}

	-- Intermediate Nodes arranged in progressive depth bands with lateral variance
	local middleCount = roomCount - 3
	local roomKinds = {
		"salvage_field",
		"choke_point",
		"foundry_cache",
		"salvage_field",
		"hazard_gauntlet",
	}

	for i = 2, middleCount + 1 do
		local progress = (i - 1) / (middleCount + 2)
		local kind = roomKinds[((i - 2) % #roomKinds) + 1]
		local baseX = margin + progress * (mapSizeX - 2 * margin)
		local baseZ = margin + progress * (mapSizeZ - 2 * margin)

		-- Alternate lateral offset across the diagonal spine for branching exploration
		local orthoSign = (i % 2 == 0) and 1 or -1
		local orthoMag = rng:rangeFloat(0.12, 0.28) * math.min(mapSizeX, mapSizeZ)
		local nx = math.max(margin, math.min(mapSizeX - margin, baseX + orthoSign * orthoMag))
		local nz = math.max(margin, math.min(mapSizeZ - margin, baseZ - orthoSign * orthoMag))

		local radius = 250
		if kind == "salvage_field" then
			radius = rng:rangeFloat(280, 340)
		elseif kind == "choke_point" then
			radius = rng:rangeFloat(190, 230)
		elseif kind == "foundry_cache" then
			radius = rng:rangeFloat(240, 290)
		elseif kind == "hazard_gauntlet" then
			radius = rng:rangeFloat(250, 310)
		end

		-- Keep elevation transitions gentle so ramp slopes stay well below maxWalkableSlope
		local prevElev = nodes[i - 1].elevation
		local elevDelta = rng:rangeFloat(-16.0, 20.0)
		local elevation = math.max(biome.baseHeight - 30.0, math.min(biome.baseHeight + 50.0, prevElev + elevDelta))

		local pillars = {}
		if kind == "choke_point" then
			local pAngle = rng:rangeFloat(0, math.pi * 2.0)
			pillars[1] = {
				x = nx + math.cos(pAngle) * 70,
				z = nz + math.sin(pAngle) * 70,
				radius = 34,
				height = elevation + 95,
			}
		end

		nodes[i] = {
			id = i,
			kind = kind,
			name = string.upper(kind) .. " #" .. tostring(i),
			x = nx,
			z = nz,
			radius = radius,
			elevation = elevation,
			hasGarage = (kind == "foundry_cache"),
			pillars = pillars,
		}
	end

	-- Node N-1: Experimental Boss Arena
	local bossIdx = roomCount - 1
	local bossX = mapSizeX - margin - rng:rangeFloat(220, 320)
	local bossZ = mapSizeZ - margin - rng:rangeFloat(220, 320)
	local bossRadius = 420
	local bossElev = biome.baseHeight + 24.0
	local bossPillars = {}
	for p = 1, 4 do
		local angle = (p - 1) * (math.pi * 0.5) + (math.pi * 0.25)
		bossPillars[p] = {
			x = bossX + math.cos(angle) * 195,
			z = bossZ + math.sin(angle) * 195,
			radius = 42,
			height = bossElev + 115,
		}
	end

	nodes[bossIdx] = {
		id = bossIdx,
		kind = "boss_arena",
		name = biome.bossTitle .. " ARENA",
		x = bossX,
		z = bossZ,
		radius = bossRadius,
		elevation = bossElev,
		hasGarage = false,
		pillars = bossPillars,
	}

	-- Node N: Extraction / Warp Gate
	local extIdx = roomCount
	nodes[extIdx] = {
		id = extIdx,
		kind = "extraction_gate",
		name = "Orbital Warp Extraction Gate",
		x = math.min(mapSizeX - margin * 0.75, bossX + 260),
		z = math.min(mapSizeZ - margin * 0.75, bossZ + 260),
		radius = 210,
		elevation = bossElev,
		hasGarage = true,
		pillars = {},
	}

	-- Primary Backbone Spine (Guarantees 100% connectivity from DropZone -> BossArena -> ExtractionGate)
	for i = 1, roomCount - 1 do
		local u = nodes[i]
		local v = nodes[i + 1]
		local dist = math.sqrt((v.x - u.x) ^ 2 + (v.z - u.z) ^ 2)
		local elevDiff = math.abs(v.elevation - u.elevation)
		local atan2 = math.atan2 or math.atan
		local slopeDeg = math.deg(atan2(elevDiff, math.max(120.0, dist)))
		edges[#edges + 1] = {
			from = i,
			to = i + 1,
			width = (v.kind == "boss_arena") and 165 or 135,
			length = dist,
			slopeDeg = slopeDeg,
			isPrimary = true,
		}
	end

	-- Secondary Loop Corridors (Provides tactical flanking & alternate salvage routes)
	for i = 2, roomCount - 3 do
		if rng:nextFloat() < 0.65 then
			local u = nodes[i]
			local v = nodes[i + 2]
			local dist = math.sqrt((v.x - u.x) ^ 2 + (v.z - u.z) ^ 2)
			local elevDiff = math.abs(v.elevation - u.elevation)
			local atan2 = math.atan2 or math.atan
			local slopeDeg = math.deg(atan2(elevDiff, math.max(120.0, dist)))
			if slopeDeg <= biome.maxWalkableSlope then
				edges[#edges + 1] = {
					from = i,
					to = i + 2,
					width = 115,
					length = dist,
					slopeDeg = slopeDeg,
					isPrimary = false,
				}
			end
		end
	end

	-- Pre-compute Planned Wrecks, Hazard Telegraphs, and Encounter Spawns
	local plannedWrecks = {}
	local hazardZones = {}
	local encounterPacks = {}

	for i = 1, roomCount do
		local node = nodes[i]
		if node.kind == "salvage_field" or node.kind == "foundry_cache" or node.kind == "choke_point" then
			local baseWrecks = (node.kind == "salvage_field") and 18 or ((node.kind == "foundry_cache") and 14 or 8)
			local count = math.floor(baseWrecks * biome.wreckDensity)
			for w = 1, count do
				local angle = rng:rangeFloat(0, math.pi * 2.0)
				local r = rng:rangeFloat(35, node.radius * 0.82)
				local wx = node.x + math.cos(angle) * r
				local wz = node.z + math.sin(angle) * r
				local isJackpot = (node.kind == "foundry_cache" and w <= 3) or (w == 1 and rng:nextFloat() < 0.45)
				local featureName = isJackpot and rng:choice(biome.jackpotWreckPool) or rng:choice(biome.wreckPool)
				plannedWrecks[#plannedWrecks + 1] = {
					nodeId = node.id,
					featureName = featureName,
					x = wx,
					z = wz,
					heading = rng:rangeInt(0, 65535),
					isJackpot = isJackpot,
					metal = isJackpot and biome.ambientMetalPerWreck.max * 2.0
						or rng:rangeInt(biome.ambientMetalPerWreck.min, biome.ambientMetalPerWreck.max),
					energy = isJackpot and biome.ambientEnergyPerWreck.max * 2.0
						or rng:rangeInt(biome.ambientEnergyPerWreck.min, biome.ambientEnergyPerWreck.max),
					tier = biome.tier,
				}
			end
		end

		if node.kind == "hazard_gauntlet" or node.kind == "boss_arena" then
			local hCount = (node.kind == "boss_arena") and 3 or 2
			for h = 1, hCount do
				local angle = (h - 1) * (2.0 * math.pi / hCount) + rng:rangeFloat(0, 0.6)
				local r = node.radius * 0.45
				hazardZones[#hazardZones + 1] = {
					nodeId = node.id,
					hazardType = biome.hazardType,
					x = node.x + math.cos(angle) * r,
					z = node.z + math.sin(angle) * r,
					radius = biome.hazardRadius,
					damage = biome.hazardDamagePerTick,
					telegraphFrames = biome.hazardTelegraphFrames,
					periodFrames = rng:rangeInt(180, 270),
					phaseOffset = rng:rangeInt(0, 150),
				}
			end
		end

		if node.kind ~= "drop_zone" and node.kind ~= "extraction_gate" and node.kind ~= "boss_arena" then
			encounterPacks[#encounterPacks + 1] = {
				nodeId = node.id,
				kind = node.kind,
				x = node.x,
				z = node.z,
				radius = node.radius * 0.70,
				swarmCount = rng:rangeInt(6 + zoneDepth * 2, 11 + zoneDepth * 3),
				eliteCount = rng:rangeInt(1, 2 + math.floor(zoneDepth / 2)),
				turretCount = (node.kind == "choke_point") and rng:rangeInt(2, 3) or 0,
			}
		end
	end

	return {
		seed = seed,
		zoneDepth = zoneDepth,
		biomeId = biomeId,
		biome = biome,
		mapSizeX = mapSizeX,
		mapSizeZ = mapSizeZ,
		nodes = nodes,
		edges = edges,
		dropZone = nodes[1],
		bossArena = nodes[bossIdx],
		extractionGate = nodes[extIdx],
		plannedWrecks = plannedWrecks,
		hazardZones = hazardZones,
		encounterPacks = encounterPacks,
	}
end

-- Evaluates height at world coordinate (x, z) for a generated ZoneBlueprint
local function SampleZoneHeight(blueprint, x, z)
	local biome = blueprint.biome
	local nodes = blueprint.nodes
	local edges = blueprint.edges

	-- 1. Baseline cliff / canyon wall modulated by domain-warped noise
	local nVal = domainWarpedNoise2D(x, z, biome.noiseFrequency, biome.domainWarpStrength, blueprint.seed)
	local wallElev = biome.wallHeight + nVal * biome.noiseAmplitude

	-- 2. Minimum blend factor across all Room Plateaus and Corridors (0.0 = flat walkable floor, 1.0 = cliff wall)
	local bestFloorElev = biome.baseHeight
	local minWallBlend = 1.0
	local weightedElevSum = 0.0
	local weightSum = 0.0

	for i = 1, #nodes do
		local node = nodes[i]
		local dx = x - node.x
		local dz = z - node.z
		local dist = math.sqrt(dx * dx + dz * dz)
		local innerR = node.radius * 0.78
		local outerR = node.radius * 1.18
		if dist <= outerR then
			local blend = 0.0
			if dist > innerR then
				blend = smoothstep((dist - innerR) / math.max(1.0, outerR - innerR))
			end
			if blend < minWallBlend then
				minWallBlend = blend
			end
			local w = math.max(0.001, (1.0 - blend) ^ 2)
			weightedElevSum = weightedElevSum + node.elevation * w
			weightSum = weightSum + w
		end
	end

	for i = 1, #edges do
		local edge = edges[i]
		local u = nodes[edge.from]
		local v = nodes[edge.to]
		local dist, t = pointToSegmentProjection(x, z, u.x, u.z, v.x, v.z)
		local innerW = edge.width * 0.65
		local outerW = edge.width * 1.25
		if dist <= outerW then
			local blend = 0.0
			if dist > innerW then
				blend = smoothstep((dist - innerW) / math.max(1.0, outerW - innerW))
			end
			if blend < minWallBlend then
				minWallBlend = blend
			end
			local rampElev = lerp(u.elevation, v.elevation, smoothstep(t))
			local w = math.max(0.001, (1.0 - blend) ^ 2)
			weightedElevSum = weightedElevSum + rampElev * w
			weightSum = weightSum + w
		end
	end

	if weightSum > 0.0 then
		bestFloorElev = weightedElevSum / weightSum
	end

	-- Add subtle micro-surface texture on walkable floors
	local floorMicro = nVal * (biome.noiseAmplitude * 0.14)
	local h = lerp(bestFloorElev + floorMicro, wallElev, minWallBlend)

	-- 3. Apply tactical cover pillars inside Boss Arena & Choke Points
	for i = 1, #nodes do
		local pillars = nodes[i].pillars
		if pillars then
			for p = 1, #pillars do
				local pil = pillars[p]
				local pd = math.sqrt((x - pil.x) ^ 2 + (z - pil.z) ^ 2)
				if pd <= pil.radius * 1.25 then
					local pBlend = 1.0 - smoothstep(math.max(0.0, (pd - pil.radius * 0.65) / (pil.radius * 0.60)))
					h = lerp(h, pil.height, pBlend)
				end
			end
		end
	end

	return h
end

-- ============================================================================
-- Graph Connectivity & Slope Verification Gate
-- ============================================================================
local function VerifyConnectivity(blueprint)
	local nodes = blueprint.nodes
	local edges = blueprint.edges
	local maxSlope = blueprint.biome.maxWalkableSlope or 22.0

	if not nodes or #nodes < 3 then
		return false, "INSUFFICIENT_NODES"
	end

	local adj = {}
	for i = 1, #nodes do
		adj[i] = {}
	end
	for i = 1, #edges do
		local e = edges[i]
		if e.slopeDeg <= maxSlope + 0.01 then
			adj[e.from][#adj[e.from] + 1] = e.to
			adj[e.to][#adj[e.to] + 1] = e.from
		end
	end

	local visited = { [1] = true }
	local queue = { 1 }
	local head = 1
	local reachedCount = 0

	while head <= #queue do
		local curr = queue[head]
		head = head + 1
		reachedCount = reachedCount + 1
		for _, nxt in ipairs(adj[curr]) do
			if not visited[nxt] then
				visited[nxt] = true
				queue[#queue + 1] = nxt
			end
		end
	end

	if reachedCount ~= #nodes then
		return false, string.format("DISCONNECTED_NODES (%d/%d)", reachedCount, #nodes)
	end
	return true, "CONNECTED_100_PERCENT"
end

-- ============================================================================
-- Synced Engine Execution (Spring.SetHeightMapFunc & Spring.CreateFeature)
-- ============================================================================
if gadgetHandler and gadgetHandler:IsSyncedCode() then
	local spSetHeightMap = Spring.SetHeightMap
	local spSetHeightMapFunc = Spring.SetHeightMapFunc
	local spGetAllFeatures = Spring.GetAllFeatures
	local spDestroyFeature = Spring.DestroyFeature
	local spCreateFeature = Spring.CreateFeature
	local spGetGroundHeight = Spring.GetGroundHeight
	local spSetGameRulesParam = Spring.SetGameRulesParam
	local spEcho = Spring.Echo

	GG.ARPG_Map = GG.ARPG_Map or {
		currentBlueprint = nil,
		wreckRegistry = {},
	}

	local function resolveValidFeatureDefName(candidateName)
		if not FeatureDefNames then
			return candidateName
		end
		if candidateName and FeatureDefNames[candidateName] then
			return candidateName
		end
		local fallbacks = {
			"armcom_dead",
			"corcom_dead",
			"armpw_dead",
			"corak_dead",
			"armmex_dead",
		}
		for i = 1, #fallbacks do
			if FeatureDefNames[fallbacks[i]] then
				return fallbacks[i]
			end
		end
		for name, _ in pairs(FeatureDefNames) do
			return name
		end
		return nil
	end

	local function applyBlueprintToSpringMap(blueprint)
		local mapSizeX = Game.mapSizeX or blueprint.mapSizeX
		local mapSizeZ = Game.mapSizeZ or blueprint.mapSizeZ
		local step = (Game.squareSize or 8) * 2

		-- 1. Reshape entire terrain heightmap in a single batched engine pass
		if spSetHeightMapFunc and spSetHeightMap then
			spSetHeightMapFunc(function()
				for z = 0, mapSizeZ, step do
					for x = 0, mapSizeX, step do
						local h = SampleZoneHeight(blueprint, x, z)
						spSetHeightMap(x, z, h)
						if step > (Game.squareSize or 8) then
							local sq = Game.squareSize or 8
							if x + sq <= mapSizeX then
								spSetHeightMap(x + sq, z, h)
							end
							if z + sq <= mapSizeZ then
								spSetHeightMap(x, z + sq, h)
							end
							if x + sq <= mapSizeX and z + sq <= mapSizeZ then
								spSetHeightMap(x + sq, z + sq, h)
							end
						end
					end
				end
			end)
		end

		-- 2. Clear old features/wrecks on zone regeneration
		GG.ARPG_Map.wreckRegistry = {}
		if spGetAllFeatures and spDestroyFeature then
			local existing = spGetAllFeatures()
			if existing then
				for i = 1, #existing do
					spDestroyFeature(existing[i])
				end
			end
		end

		-- 3. Spawn Pre-Seeded BAR Wreck Fields & Salvage Jackpots
		local gaiaTeamID = Spring.GetGaiaTeamID and Spring.GetGaiaTeamID() or 0
		if spCreateFeature then
			for i = 1, #blueprint.plannedWrecks do
				local w = blueprint.plannedWrecks[i]
				local defName = resolveValidFeatureDefName(w.featureName)
				if defName then
					local y = spGetGroundHeight and spGetGroundHeight(w.x, w.z) or blueprint.biome.baseHeight
					local fID = spCreateFeature(defName, w.x, y, w.z, w.heading, gaiaTeamID)
					if fID then
						if Spring.SetFeatureResources then
							Spring.SetFeatureResources(fID, w.metal, w.metal, w.energy, w.energy, 1.0, w.metal * 0.5)
						end
						GG.ARPG_Map.wreckRegistry[fID] = {
							featureID = fID,
							featureName = defName,
							nodeId = w.nodeId,
							isJackpot = w.isJackpot,
							isBossWreck = false,
							metal = w.metal,
							energy = w.energy,
							tier = w.tier,
							biomeId = blueprint.biomeId,
						}
					end
				end
			end
		end

		-- 4. Publish Zone Metadata to GameRulesParams for LuaUI HUD & Minimap Radar
		if spSetGameRulesParam then
			spSetGameRulesParam("arpg_zone_seed", blueprint.seed)
			spSetGameRulesParam("arpg_zone_depth", blueprint.zoneDepth)
			spSetGameRulesParam("arpg_zone_biome", blueprint.biomeId)
			spSetGameRulesParam("arpg_zone_title", blueprint.biome.name)
			spSetGameRulesParam("arpg_drop_x", math.floor(blueprint.dropZone.x))
			spSetGameRulesParam("arpg_drop_z", math.floor(blueprint.dropZone.z))
			spSetGameRulesParam("arpg_boss_x", math.floor(blueprint.bossArena.x))
			spSetGameRulesParam("arpg_boss_z", math.floor(blueprint.bossArena.z))
			spSetGameRulesParam("arpg_extract_x", math.floor(blueprint.extractionGate.x))
			spSetGameRulesParam("arpg_extract_z", math.floor(blueprint.extractionGate.z))
			spSetGameRulesParam("arpg_wreck_count", #blueprint.plannedWrecks)
		end

		if spEcho then
			spEcho(
				string.format(
					"[ARPG ProcGen] Generated Zone #%d (%s) | Seed=%d | Rooms=%d | Wrecks=%d",
					blueprint.zoneDepth,
					blueprint.biome.name,
					blueprint.seed,
					#blueprint.nodes,
					#blueprint.plannedWrecks
				)
			)
		end
	end

	function GG.ARPG_Map.GenerateZone(seed, zoneDepth, biomeIdOverride)
		local mapSizeX = (Game and Game.mapSizeX) or 4096
		local mapSizeZ = (Game and Game.mapSizeZ) or 4096
		local bp = BuildZoneBlueprint(seed, zoneDepth, mapSizeX, mapSizeZ, biomeIdOverride)
		local ok, status = VerifyConnectivity(bp)
		bp.connectivityVerified = ok
		bp.connectivityStatus = status
		GG.ARPG_Map.currentBlueprint = bp
		applyBlueprintToSpringMap(bp)
		return bp
	end

	function GG.ARPG_Map.GetCurrentZone()
		return GG.ARPG_Map.currentBlueprint
	end

	GG.ARPG_Map.BuildZoneBlueprint = BuildZoneBlueprint
	GG.ARPG_Map.SampleZoneHeight = SampleZoneHeight
	GG.ARPG_Map.VerifyConnectivity = VerifyConnectivity

	function gadget:GamePreload()
		local modOpts = Spring.GetModOptions and Spring.GetModOptions() or {}
		local initialSeed = tonumber(modOpts.arpg_seed) or 424242
		GG.ARPG_Map.GenerateZone(initialSeed, 1, nil)
	end
end

return {
	ProcRNG = ProcRNG,
	BuildZoneBlueprint = BuildZoneBlueprint,
	SampleZoneHeight = SampleZoneHeight,
	VerifyConnectivity = VerifyConnectivity,
}
