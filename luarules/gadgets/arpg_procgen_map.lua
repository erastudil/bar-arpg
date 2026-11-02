-- luarules/gadgets/arpg_procgen_map.lua
-- Seeded Procedural Map Generation Engine for BAR Sci-Fi ARPG ("WRECKAGE PROTOCOL")
-- Supports 8 Scrap Frontier zone archetypes, topology-aware room placement,
-- Setpiece Vaults (Locked Armory, Constructor Bay, Overclocked Reactor Wreck),
-- slope-bounded corridors, cover pillars, and pre-seeded BAR wreck fields.

function gadget:GetInfo()
	return {
		name = "ARPG Procedural Map Generator",
		desc = "Deterministic 8-biome heightmap, corridor ramp, setpiece vault, wreck field, and boss arena generator",
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
local SetpieceTypes = BiomeConfig.SetpieceTypes
local ZoneModifiers = BiomeConfig.ZoneModifiers or {}
local ZoneModifierSequence = BiomeConfig.ZoneModifierSequence or { "lazarus_nanite_reanimation" }

local function loadPrecompiledAtlas()
	if VFS and VFS.Include then
		local ok, data = pcall(VFS.Include, "luarules/configs/arpg_map_atlas_blueprints.lua")
		if ok and type(data) == "table" then
			return data
		end
	end
	if dofile then
		local ok, data = pcall(dofile, "luarules/configs/arpg_map_atlas_blueprints.lua")
		if ok and type(data) == "table" then
			return data
		end
	end
	return nil
end

local PrecompiledAtlas = loadPrecompiledAtlas()

local function GetPrecompiledAtlas()
	return PrecompiledAtlas
end

local function GetPrecompiledZoneBlueprint(zoneDepth)
	if not PrecompiledAtlas or type(PrecompiledAtlas.zones) ~= "table" then
		return nil
	end
	local idx = ((math.max(1, tonumber(zoneDepth) or 1) - 1) % 8) + 1
	return PrecompiledAtlas.zones[idx]
end

if gadgetHandler and not gadgetHandler:IsSyncedCode() then
	return false
end

-- ============================================================================
-- Deterministic PRNG (Bit-exact across Lua 5.1 / LuaJIT / Lua 5.3)
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
	t = math.max(0.0, math.min(1.0, t))
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
-- Topology-Aware Coordinate Generator across the 8 Archetypes
-- ============================================================================
local function computeRoomPosition(topology, idx, middleCount, margin, mapSizeX, mapSizeZ, rng)
	local progress = (idx - 1) / (middleCount + 2)
	local spanX = mapSizeX - 2 * margin
	local spanZ = mapSizeZ - 2 * margin
	local baseX = margin + progress * spanX
	local baseZ = margin + progress * spanZ
	local minDim = math.min(mapSizeX, mapSizeZ)

	if topology == "orthogonal_bays" then
		-- Quantized grid-bay coordinates for Derelict Factory
		local gridStep = 360.0
		local orthoSign = (idx % 2 == 0) and 1 or -1
		local rawX = baseX + orthoSign * 0.18 * minDim
		local rawZ = baseZ - orthoSign * 0.18 * minDim
		local qx = math.floor(rawX / gridStep + 0.5) * gridStep
		local qz = math.floor(rawZ / gridStep + 0.5) * gridStep
		return math.max(margin, math.min(mapSizeX - margin, qx)), math.max(margin, math.min(mapSizeZ - margin, qz))
	elseif topology == "linear_spine_flanks" then
		-- Tight central rail spine with service tunnel bays alongside it
		local orthoSign = (idx % 2 == 0) and 1 or -1
		local flankOffset = (idx % 3 == 0) and 0.04 or 0.14
		local nx = baseX + orthoSign * flankOffset * minDim
		local nz = baseZ - orthoSign * flankOffset * minDim
		return math.max(margin, math.min(mapSizeX - margin, nx)), math.max(margin, math.min(mapSizeZ - margin, nz))
	elseif topology == "switchback_canyons" then
		-- Wide S-curve switchbacks across the badlands
		local wave = math.sin(progress * math.pi * 2.5) * 0.28 * minDim
		local nx = baseX + wave
		local nz = baseZ - wave * 0.75
		return math.max(margin, math.min(mapSizeX - margin, nx)), math.max(margin, math.min(mapSizeZ - margin, nz))
	else
		local orthoSign = (idx % 2 == 0) and 1 or -1
		local orthoMag = rng:rangeFloat(0.12, 0.26) * minDim
		local nx = baseX + orthoSign * orthoMag
		local nz = baseZ - orthoSign * orthoMag
		return math.max(margin, math.min(mapSizeX - margin, nx)), math.max(margin, math.min(mapSizeZ - margin, nz))
	end
end

-- ============================================================================
-- Pure Blueprint & Heightfield Synthesis
-- ============================================================================
local function BuildZoneBlueprint(seed, zoneDepth, mapSizeX, mapSizeZ, biomeIdOverride, modifierIdOverride)
	zoneDepth = math.max(1, tonumber(zoneDepth) or 1)
	mapSizeX = tonumber(mapSizeX) or 4096
	mapSizeZ = tonumber(mapSizeZ) or 4096

	local rng = ProcRNG.new(seed + zoneDepth * 7919)
	local biomeId = biomeIdOverride or BiomeSequence[((zoneDepth - 1) % #BiomeSequence) + 1]
	local biome = Biomes[biomeId] or Biomes.salvage_yard
	local topology = biome.topology or "open_scrapyard_bowls"
	local modifierId = modifierIdOverride or ZoneModifierSequence[((zoneDepth - 1) % #ZoneModifierSequence) + 1]
	local zoneModifier = ZoneModifiers[modifierId] or ZoneModifiers.lazarus_nanite_reanimation

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

	local middleCount = roomCount - 3
	local roomKinds = {
		"salvage_field",
		"choke_point",
		"foundry_cache",
		"salvage_field",
		"hazard_gauntlet",
		"setpiece_vault",
	}

	for i = 2, middleCount + 1 do
		local kind = roomKinds[((i - 2) % #roomKinds) + 1]
		local nx, nz = computeRoomPosition(topology, i, middleCount, margin, mapSizeX, mapSizeZ, rng)

		local radius = 255
		if kind == "salvage_field" then
			radius = rng:rangeFloat(280, 340)
		elseif kind == "choke_point" then
			radius = rng:rangeFloat(195, 235)
		elseif kind == "foundry_cache" or kind == "setpiece_vault" then
			radius = rng:rangeFloat(245, 295)
		elseif kind == "hazard_gauntlet" then
			radius = rng:rangeFloat(250, 310)
		end

		local prevElev = nodes[i - 1].elevation
		local elevDelta = rng:rangeFloat(-15.0, 18.0)
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
			hasGarage = (kind == "foundry_cache" or kind == "setpiece_vault"),
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
			radius = 40,
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
		shieldSubnodes = (topology == "citadel_shield_nodes") and 3 or 0,
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

	local atan2 = math.atan2 or math.atan
	local corridorWidthBase = (topology == "catwalk_bridges") and 115 or 135

	-- Primary Backbone Spine (Guarantees 100% connectivity)
	for i = 1, roomCount - 1 do
		local u = nodes[i]
		local v = nodes[i + 1]
		local dist = math.sqrt((v.x - u.x) ^ 2 + (v.z - u.z) ^ 2)
		local elevDiff = math.abs(v.elevation - u.elevation)
		local slopeDeg = math.deg(atan2(elevDiff, math.max(120.0, dist)))
		edges[#edges + 1] = {
			from = i,
			to = i + 1,
			width = (v.kind == "boss_arena") and 165 or corridorWidthBase,
			length = dist,
			slopeDeg = slopeDeg,
			isPrimary = true,
		}
	end

	-- Secondary Loop Corridors
	for i = 2, roomCount - 3 do
		if rng:nextFloat() < 0.65 then
			local u = nodes[i]
			local v = nodes[i + 2]
			local dist = math.sqrt((v.x - u.x) ^ 2 + (v.z - u.z) ^ 2)
			local elevDiff = math.abs(v.elevation - u.elevation)
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

	-- Pre-compute Planned Wrecks, Setpiece Vaults, Hazard Telegraphs, and Encounter Packs
	local plannedWrecks = {}
	local hazardZones = {}
	local encounterPacks = {}
	local setpieces = {}
	local setpieceCycle = {
		"locked_armory_vault",
		"live_constructor_bay",
		"overclocked_reactor_wreck",
	}

	for i = 1, roomCount do
		local node = nodes[i]
		if
			node.kind == "salvage_field"
			or node.kind == "foundry_cache"
			or node.kind == "choke_point"
			or node.kind == "setpiece_vault"
		then
			local baseWrecks = (node.kind == "salvage_field") and 18
				or ((node.kind == "foundry_cache" or node.kind == "setpiece_vault") and 14 or 8)
			local count = math.floor(baseWrecks * biome.wreckDensity)
			for w = 1, count do
				local angle = rng:rangeFloat(0, math.pi * 2.0)
				local r = rng:rangeFloat(35, node.radius * 0.82)
				local wx = node.x + math.cos(angle) * r
				local wz = node.z + math.sin(angle) * r
				local isJackpot = ((node.kind == "foundry_cache" or node.kind == "setpiece_vault") and w <= 3)
					or (w == 1 and rng:nextFloat() < 0.45)
				local isOverclockedReactor = (node.kind == "setpiece_vault" and w == 1)
				local featureName = isJackpot and rng:choice(biome.jackpotWreckPool) or rng:choice(biome.wreckPool)
				plannedWrecks[#plannedWrecks + 1] = {
					nodeId = node.id,
					featureName = featureName,
					x = wx,
					z = wz,
					heading = rng:rangeInt(0, 65535),
					isJackpot = isJackpot,
					isOverclockedReactor = isOverclockedReactor,
					metal = isJackpot and biome.ambientMetalPerWreck.max * 2.0
						or rng:rangeInt(biome.ambientMetalPerWreck.min, biome.ambientMetalPerWreck.max),
					energy = isJackpot and biome.ambientEnergyPerWreck.max * 2.0
						or rng:rangeInt(biome.ambientEnergyPerWreck.min, biome.ambientEnergyPerWreck.max),
					tier = biome.tier,
				}
			end
		end

		-- Assign deterministic Setpieces (Locked Armory, Constructor Repair Bay, Overclocked Reactor Wreck)
		if node.kind == "foundry_cache" or node.kind == "setpiece_vault" then
			local spKind = setpieceCycle[(#setpieces % #setpieceCycle) + 1]
			local spDef = SetpieceTypes and SetpieceTypes[spKind]
			setpieces[#setpieces + 1] = {
				id = #setpieces + 1,
				nodeId = node.id,
				kind = spKind,
				name = (spDef and spDef.name) or spKind,
				x = node.x,
				z = node.z,
				radius = node.radius * 0.65,
				completed = false,
			}
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
				hasFabricatorGantry = (topology == "foundry_caldera" and node.kind == "foundry_cache"),
				hasLockdownDoor = (topology == "orthogonal_bays" and node.kind == "choke_point"),
			}
		end
	end

	-- Wave 6: Procedural Armored Supply Convoy / Scrap Train Route
	local convoyWaypoints = {}
	for i = 2, math.max(2, roomCount - 2) do
		convoyWaypoints[#convoyWaypoints + 1] = {
			nodeId = nodes[i].id,
			x = nodes[i].x,
			z = nodes[i].z,
			elevation = nodes[i].elevation,
		}
	end
	local convoyRoute = {
		id = "scrap_train_" .. tostring(zoneDepth),
		name = "Armored Scrap-Train Convoy",
		crawlerUnit = (biome.eliteUnits and biome.eliteUnits[1]) or "corgol",
		escortUnit = (biome.swarmUnits and biome.swarmUnits[1]) or "armpw",
		crawlerCount = 2 + math.floor(zoneDepth / 3),
		speed = 42.0,
		jackpotMetal = (biome.ambientMetalPerWreck and biome.ambientMetalPerWreck.max or 600) * 3.0,
		waypoints = convoyWaypoints,
	}

	-- Wave 6: Destructible Choke Bridges & Collapsible Canyon Overhangs
	local destructibleBridges = {}
	for i = 1, #edges do
		local edge = edges[i]
		local u = nodes[edge.from]
		local v = nodes[edge.to]
		if (u.kind == "choke_point" or v.kind == "choke_point" or (#destructibleBridges == 0 and i == 2)) and #destructibleBridges < 2 then
			local bx = (u.x + v.x) * 0.5
			local bz = (u.z + v.z) * 0.5
			destructibleBridges[#destructibleBridges + 1] = {
				id = #destructibleBridges + 1,
				fromNode = edge.from,
				toNode = edge.to,
				name = (topology == "switchback_canyons") and "Collapsible Canyon Overhang" or "Destructible Choke Bridge",
				x = bx,
				z = bz,
				radius = 125.0,
				dropDepth = 110.0,
				crushDamage = 1800 + zoneDepth * 450,
				collapsed = false,
			}
		end
	end

	return {
		seed = seed,
		zoneDepth = zoneDepth,
		biomeId = biomeId,
		biome = biome,
		topology = topology,
		modifierId = modifierId,
		zoneModifier = zoneModifier,
		mapSizeX = mapSizeX,
		mapSizeZ = mapSizeZ,
		nodes = nodes,
		edges = edges,
		dropZone = nodes[1],
		bossArena = nodes[bossIdx],
		extractionGate = nodes[extIdx],
		plannedWrecks = plannedWrecks,
		setpieces = setpieces,
		hazardZones = hazardZones,
		encounterPacks = encounterPacks,
		convoyRoute = convoyRoute,
		destructibleBridges = destructibleBridges,
	}
end

local function SampleZoneHeight(blueprint, x, z)
	local biome = blueprint.biome
	local nodes = blueprint.nodes
	local edges = blueprint.edges

	local nVal = domainWarpedNoise2D(x, z, biome.noiseFrequency, biome.domainWarpStrength, blueprint.seed)
	local wallElev = biome.wallHeight + nVal * biome.noiseAmplitude

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

	local floorMicro = nVal * (biome.noiseAmplitude * 0.14)
	local h = lerp(bestFloorElev + floorMicro, wallElev, minWallBlend)

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

	-- Wave 6: Apply terrain chasm drop for collapsed Destructible Choke Bridges
	local bridges = blueprint.destructibleBridges
	if bridges then
		for b = 1, #bridges do
			local br = bridges[b]
			if br.collapsed then
				local bd = math.sqrt((x - br.x) ^ 2 + (z - br.z) ^ 2)
				if bd <= br.radius then
					local cBlend = 1.0 - smoothstep(bd / math.max(1.0, br.radius))
					h = h - br.dropDepth * cBlend
				end
			end
		end
	end

	return h
end

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

		GG.ARPG_Map.wreckRegistry = {}
		if spGetAllFeatures and spDestroyFeature then
			local existing = spGetAllFeatures()
			if existing then
				for i = 1, #existing do
					spDestroyFeature(existing[i])
				end
			end
		end

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
							isOverclockedReactor = w.isOverclockedReactor or false,
							isBossWreck = false,
							metal = w.metal,
							energy = w.energy,
							tier = w.tier,
							biomeId = blueprint.biomeId,
							x = w.x,
							z = w.z,
						}
					end
				end
			end
		end

		if spSetGameRulesParam then
			spSetGameRulesParam("arpg_zone_seed", blueprint.seed)
			spSetGameRulesParam("arpg_zone_depth", blueprint.zoneDepth)
			spSetGameRulesParam("arpg_zone_biome", blueprint.biomeId)
			spSetGameRulesParam("arpg_zone_topology", blueprint.topology)
			spSetGameRulesParam("arpg_zone_title", blueprint.biome.name)
			spSetGameRulesParam("arpg_drop_x", math.floor(blueprint.dropZone.x))
			spSetGameRulesParam("arpg_drop_z", math.floor(blueprint.dropZone.z))
			spSetGameRulesParam("arpg_boss_x", math.floor(blueprint.bossArena.x))
			spSetGameRulesParam("arpg_boss_z", math.floor(blueprint.bossArena.z))
			spSetGameRulesParam("arpg_extract_x", math.floor(blueprint.extractionGate.x))
			spSetGameRulesParam("arpg_extract_z", math.floor(blueprint.extractionGate.z))
			spSetGameRulesParam("arpg_wreck_count", #blueprint.plannedWrecks)
			spSetGameRulesParam("arpg_setpiece_count", #blueprint.setpieces)
			spSetGameRulesParam("arpg_zone_modifier", blueprint.modifierId or "lazarus_nanite_reanimation")
			spSetGameRulesParam("arpg_bridge_count", #(blueprint.destructibleBridges or {}))
		end

		if spEcho then
			spEcho(
				string.format(
					"[ARPG ProcGen] Generated Zone #%d (%s / %s | Mod=%s) | Seed=%d | Rooms=%d | Wrecks=%d | Setpieces=%d",
					blueprint.zoneDepth,
					blueprint.biome.name,
					blueprint.topology,
					blueprint.modifierId or "none",
					blueprint.seed,
					#blueprint.nodes,
					#blueprint.plannedWrecks,
					#blueprint.setpieces
				)
			)
		end
	end

	function GG.ARPG_Map.DetonateDestructibleBridge(bridgeId, attackerID)
		local bp = GG.ARPG_Map.currentBlueprint
		if not bp or not bp.destructibleBridges then
			return false, "NO_ACTIVE_BRIDGES"
		end
		local targetBridge = nil
		for i = 1, #bp.destructibleBridges do
			if bp.destructibleBridges[i].id == bridgeId then
				targetBridge = bp.destructibleBridges[i]
				break
			end
		end
		if not targetBridge or targetBridge.collapsed then
			return false, "BRIDGE_ALREADY_COLLAPSED"
		end
		targetBridge.collapsed = true

		-- Dynamically drop the terrain heightfield around the bridge in-place!
		if spSetHeightMapFunc and spSetHeightMap then
			local step = (Game and Game.squareSize or 8)
			local minX = math.max(0, math.floor((targetBridge.x - targetBridge.radius) / step) * step)
			local maxX = math.min(bp.mapSizeX, math.ceil((targetBridge.x + targetBridge.radius) / step) * step)
			local minZ = math.max(0, math.floor((targetBridge.z - targetBridge.radius) / step) * step)
			local maxZ = math.min(bp.mapSizeZ, math.ceil((targetBridge.z + targetBridge.radius) / step) * step)
			spSetHeightMapFunc(function()
				for z = minZ, maxZ, step do
					for x = minX, maxX, step do
						spSetHeightMap(x, z, SampleZoneHeight(bp, x, z))
					end
				end
			end)
		end

		-- Crush any units inside the bridge collapse radius
		local crushedCount = 0
		if Spring and Spring.GetUnitsInCylinder and Spring.AddUnitDamage then
			local units = Spring.GetUnitsInCylinder(targetBridge.x, targetBridge.z, targetBridge.radius)
			if units then
				for i = 1, #units do
					local uID = units[i]
					if uID ~= attackerID then
						Spring.AddUnitDamage(uID, targetBridge.crushDamage, 0, attackerID or -1, -1)
						crushedCount = crushedCount + 1
					end
				end
			end
		end
		return true, crushedCount
	end

	function GG.ARPG_Map.GenerateZone(seed, zoneDepth, biomeIdOverride, modifierIdOverride)
		local mapSizeX = (Game and Game.mapSizeX) or 4096
		local mapSizeZ = (Game and Game.mapSizeZ) or 4096
		local bp = BuildZoneBlueprint(seed, zoneDepth, mapSizeX, mapSizeZ, biomeIdOverride, modifierIdOverride)
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
	GG.ARPG_Map.GetPrecompiledAtlas = GetPrecompiledAtlas
	GG.ARPG_Map.GetPrecompiledZoneBlueprint = GetPrecompiledZoneBlueprint

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
	GetPrecompiledAtlas = GetPrecompiledAtlas,
	GetPrecompiledZoneBlueprint = GetPrecompiledZoneBlueprint,
}
