-- luarules/gadgets/arpg_modular_assembly.lua
-- Armored Core Modular Character Assembly, Engineering Budget (Mass/Heat/Power),
-- Deterministic Crafting Bench, and Signature Unique Weapon Mechanics.

function gadget:GetInfo()
	return {
		name = "ARPG Modular Assembly & Crafting",
		desc = "Armored Core modular chassis/core/loco/weapon/module assembly, Mass/Heat/Power budget, and deterministic crafting",
		author = "Argon",
		date = "2026-11-01",
		license = "GNU GPL, v2 or later",
		layer = 5,
		enabled = true,
	}
end

local PartsDB = VFS and VFS.Include and VFS.Include("luarules/configs/arpg_parts_db.lua")
	or require("luarules/configs/arpg_parts_db")

local Parts = PartsDB.Parts
local Materials = PartsDB.Materials
local DefaultLoadout = PartsDB.DefaultLoadout
local ComputeAssemblyBudget = PartsDB.ComputeAssemblyBudget
local CanCraftPart = PartsDB.CanCraftPart

if gadgetHandler and not gadgetHandler:IsSyncedCode() then
	return false
end

local SOURCE_ASSEMBLY = "arpg_modular_assembly"
local SOURCE_UNIQUE_WPN = "arpg_unique_weapon"

local heroAssemblies = {} -- [unitID] = { loadout, budget, inventoryParts, materials, unlockedTechTier, heat, maxHeat }
local activeUniqueEffects = {
	massless = {}, -- [unitID] = { expireFrame, origMass }
	scrambled = {}, -- [unitID] = { expireFrame, origTeam, attackerID }
	neutron = {}, -- [unitID] = { expireFrame, stacks, origMass }
}

local function copyTable(src)
	local out = {}
	if src then
		for k, v in pairs(src) do
			out[k] = v
		end
	end
	return out
end

local function syncAssemblyRulesParams(unitID, state)
	if not Spring or not Spring.SetUnitRulesParam then
		return
	end
	local b = state.budget
	Spring.SetUnitRulesParam(unitID, "arpg_mass", b.totalMass)
	Spring.SetUnitRulesParam(unitID, "arpg_mass_limit", b.massLimit)
	Spring.SetUnitRulesParam(unitID, "arpg_mass_state", b.massState)
	Spring.SetUnitRulesParam(unitID, "arpg_heat", math.floor(state.heat or 0))
	Spring.SetUnitRulesParam(unitID, "arpg_heat_cap", b.heatCapacity)
	Spring.SetUnitRulesParam(unitID, "arpg_heat_diss", b.heatDissipation)
	Spring.SetUnitRulesParam(unitID, "arpg_power_out", b.powerOutput)
	Spring.SetUnitRulesParam(unitID, "arpg_power_draw", b.powerDraw)
	Spring.SetUnitRulesParam(unitID, "arpg_power_net", b.netPower)
	Spring.SetUnitRulesParam(unitID, "arpg_power_state", b.powerState)
	Spring.SetUnitRulesParam(unitID, "arpg_build_power", b.buildPower)
	Spring.SetUnitRulesParam(unitID, "arpg_reclaim_speed", b.reclaimSpeed)
	Spring.SetUnitRulesParam(unitID, "arpg_tech_tier", state.unlockedTechTier or 1)

	-- Sync mounted part IDs
	for slotName, partId in pairs(state.loadout) do
		Spring.SetUnitRulesParam(unitID, "arpg_slot_" .. slotName, partId)
	end

	-- Sync material stockpile
	for matKey, _ in pairs(Materials) do
		Spring.SetUnitRulesParam(unitID, "arpg_mat_" .. matKey, math.floor(state.materials[matKey] or 0))
	end

	-- Sync module-derived active abilities
	for idx = 1, 4 do
		local entry = b.activeAbilities[idx]
		if entry and entry.ability then
			Spring.SetUnitRulesParam(unitID, "arpg_ability_" .. idx .. "_id", entry.ability.id)
			Spring.SetUnitRulesParam(unitID, "arpg_ability_" .. idx .. "_name", entry.ability.name)
		else
			Spring.SetUnitRulesParam(unitID, "arpg_ability_" .. idx .. "_id", "none")
			Spring.SetUnitRulesParam(unitID, "arpg_ability_" .. idx .. "_name", "EMPTY_MOUNT")
		end
	end
end

local function applyAssemblyToUnit(unitID, state)
	local b = ComputeAssemblyBudget(state.loadout)
	state.budget = b
	state.maxHeat = b.heatCapacity

	-- Apply via BAR's GG.UnitAttributes if loaded
	if GG and GG.UnitAttributes then
		local ua = GG.UnitAttributes
		ua.SetUnitAttribute(unitID, "maxHealth", b.maxHealth, SOURCE_ASSEMBLY)
		ua.SetUnitAttribute(unitID, "speed", b.effectiveSpeed, SOURCE_ASSEMBLY)
		ua.SetUnitAttribute(unitID, "turnRate", b.turnRate, SOURCE_ASSEMBLY)
		ua.SetUnitAttribute(unitID, "buildSpeed", b.reclaimSpeed, SOURCE_ASSEMBLY)
		ua.SetUnitAttribute(unitID, "mass", b.totalMass, SOURCE_ASSEMBLY)
		ua.SetUnitAttribute(unitID, "radarRadius", b.radarRadius, SOURCE_ASSEMBLY)
		ua.SetUnitAttribute(unitID, "losRadius", b.losRadius, SOURCE_ASSEMBLY)

		ua.SetUnitWeaponModifier(unitID, ua.WEAPON_ALL, "damage", b.weaponDamageMult, SOURCE_ASSEMBLY)
		ua.SetUnitWeaponModifier(unitID, ua.WEAPON_ALL, "reloadTime", b.weaponReloadMult, SOURCE_ASSEMBLY)
		if b.primaryWeapon and b.primaryWeapon.stats and b.primaryWeapon.stats.range then
			ua.SetUnitWeaponAttribute(unitID, 1, "maxWeaponRange", b.primaryWeapon.stats.range, SOURCE_ASSEMBLY)
		end
	end

	-- Direct engine setters as immediate guarantee
	if Spring then
		if Spring.SetUnitMaxHealth and Spring.GetUnitHealth then
			local curH, oldMax = Spring.GetUnitHealth(unitID)
			local ratio = (oldMax and oldMax > 0) and (curH / oldMax) or 1.0
			Spring.SetUnitMaxHealth(unitID, b.maxHealth)
			Spring.SetUnitHealth(unitID, math.min(b.maxHealth, math.max(1, b.maxHealth * ratio)))
		end
		if Spring.SetUnitBuildSpeed then
			Spring.SetUnitBuildSpeed(unitID, b.buildPower, b.buildPower, b.reclaimSpeed, b.buildPower, b.buildPower)
		end
		if Spring.SetUnitMass then
			Spring.SetUnitMass(unitID, b.totalMass)
		end
	end

	syncAssemblyRulesParams(unitID, state)
	return b
end

local function initHeroAssembly(unitID, initialState)
	local loadout = copyTable((initialState and initialState.loadout) or DefaultLoadout)
	local materials = copyTable((initialState and initialState.materials) or {
		reclaimed_alloy = 60,
		servo_actuators = 35,
		reactor_conductors = 20,
		optics_lenses = 15,
		experimental_cores = 0,
	})
	local inventoryParts = copyTable((initialState and initialState.inventoryParts) or {
		frame_scout_strider = true,
		frame_constructor_rig = true,
		core_fission_mk1 = true,
		loco_servo_biped = true,
		wpn_pulse_laser = true,
		wpn_plasma_howitzer = true,
		mod_vectored_dash = true,
		mod_pile_bunker = true,
		mod_radar_scanner = true,
		mod_thermal_purge = true,
	})

	local state = {
		unitID = unitID,
		loadout = loadout,
		materials = materials,
		inventoryParts = inventoryParts,
		unlockedTechTier = (initialState and initialState.unlockedTechTier) or 1,
		heat = 0.0,
		maxHeat = 130.0,
		overheatedUntilFrame = 0,
	}
	heroAssemblies[unitID] = state
	applyAssemblyToUnit(unitID, state)
	return state
end

local function addMaterials(unitID, matDelta)
	local state = heroAssemblies[unitID]
	if not state or not matDelta then
		return false
	end
	for k, amount in pairs(matDelta) do
		if Materials[k] and amount > 0 then
			state.materials[k] = (state.materials[k] or 0) + amount
		end
	end
	syncAssemblyRulesParams(unitID, state)
	return true
end

local function grantPartDrop(unitID, partId)
	local state = heroAssemblies[unitID]
	if not state or not Parts[partId] then
		return false
	end
	state.inventoryParts[partId] = true
	if Spring and Spring.Echo then
		Spring.Echo(string.format("[ARPG Salvage] Recovered intact machine part: %s (%s)", Parts[partId].name, partId))
	end
	return true
end

local function equipPart(unitID, slotName, partId)
	local state = heroAssemblies[unitID]
	if not state then
		return false, "NO_HERO_STATE"
	end
	local part = Parts[partId]
	if not part then
		return false, "UNKNOWN_PART"
	end
	if not state.inventoryParts[partId] then
		return false, "PART_NOT_IN_INVENTORY"
	end

	-- Validate slot compatibility
	local validSlot = false
	if slotName == "frame" and part.slot == "frame" then
		validSlot = true
	elseif slotName == "core" and part.slot == "core" then
		validSlot = true
	elseif slotName == "locomotion" and part.slot == "locomotion" then
		validSlot = true
	elseif (slotName == "weapon_primary" or slotName == "weapon_secondary") and part.slot == "weapon" then
		validSlot = true
	elseif string.sub(slotName, 1, 7) == "module_" and part.slot == "module" then
		validSlot = true
	end

	if not validSlot then
		return false, "INVALID_SLOT_MOUNT"
	end

	state.loadout[slotName] = partId
	applyAssemblyToUnit(unitID, state)
	return true, "MOUNTED_" .. partId
end

local function craftPart(unitID, partId)
	local state = heroAssemblies[unitID]
	if not state then
		return false, "NO_HERO_STATE"
	end
	local part = Parts[partId]
	if not part then
		return false, "UNKNOWN_PART"
	end

	local canCraft, reason = CanCraftPart(partId, {
		unlockedTechTier = state.unlockedTechTier,
		buildPower = state.budget and state.budget.buildPower or 250,
		materials = state.materials,
	})
	if not canCraft then
		return false, reason
	end

	-- Deduct deterministic Bill of Materials
	for matKey, reqAmount in pairs(part.recipe) do
		if Materials[matKey] then
			state.materials[matKey] = state.materials[matKey] - reqAmount
		end
	end

	state.inventoryParts[partId] = true
	syncAssemblyRulesParams(unitID, state)
	if Spring and Spring.Echo then
		Spring.Echo(string.format("[ARPG Garage] Machined part deterministically: %s", part.name))
	end
	return true, "MACHINED_" .. partId
end

-- ============================================================================
-- Owner Signature Unique Weapons Execution (Massless Recoil, Scrambler, Neutron)
-- ============================================================================
local function applyUniqueWeaponEffect(mechanic, attackerID, targetID, frame)
	if not targetID or targetID == attackerID then
		return
	end
	if mechanic == "massless_recoil" then
		local origMass = (Spring and Spring.GetUnitMass and Spring.GetUnitMass(targetID)) or 400
		if not activeUniqueEffects.massless[targetID] then
			activeUniqueEffects.massless[targetID] = {
				origMass = origMass,
				expireFrame = frame + 150, -- 5s massless state
			}
		else
			activeUniqueEffects.massless[targetID].expireFrame = frame + 150
		end
		-- Reduce target mass by 99.99%
		local masslessVal = math.max(0.05, origMass * 0.0001)
		if Spring and Spring.SetUnitMass then
			Spring.SetUnitMass(targetID, masslessVal)
		end
		-- Invert original heavy encumbrance into violent recoil knockback
		if Spring and Spring.GetUnitPosition and Spring.AddUnitImpulse then
			local ax, _, az = Spring.GetUnitPosition(attackerID)
			local tx, _, tz = Spring.GetUnitPosition(targetID)
			if ax and tx then
				local dx = tx - ax
				local dz = tz - az
				local dist = math.max(1.0, math.sqrt(dx * dx + dz * dz))
				-- Heavier original armor suffers stronger inertial shear velocity
				local encumbranceFactor = math.min(4.5, math.max(1.0, origMass / 250.0))
				local impulseMag = 14.0 * encumbranceFactor
				Spring.AddUnitImpulse(targetID, (dx / dist) * impulseMag, 4.5 * encumbranceFactor, (dz / dist) * impulseMag)
			end
		end
	elseif mechanic == "topological_scrambler" then
		-- Rearrange robot circuits topologically: invert targeting matrix to attack nearby pack members
		activeUniqueEffects.scrambled[targetID] = {
			expireFrame = frame + 240, -- 8s topological inversion
			attackerID = attackerID,
		}
		if Spring and Spring.GetUnitPosition and Spring.GetUnitsInCylinder and Spring.GiveOrderToUnit then
			local tx, ty, tz = Spring.GetUnitPosition(targetID)
			if tx then
				local nearby = Spring.GetUnitsInCylinder(tx, tz, 280)
				if nearby then
					for i = 1, #nearby do
						local otherID = nearby[i]
						if otherID ~= targetID and otherID ~= attackerID then
							-- Force topologically scrambled machine to attack its own packmate
							if CMD and CMD.ATTACK then
								Spring.GiveOrderToUnit(targetID, CMD.ATTACK, { otherID }, {})
							end
							-- Arc topological logic feedback damage
							if Spring.AddUnitDamage then
								Spring.AddUnitDamage(otherID, 165, 0, attackerID, -1)
							end
							break
						end
					end
				end
			end
		end
	elseif mechanic == "neutron_mass_pulse" then
		-- Briefly make enemy weapon/chassis weigh as much as a neutron star
		local masslessEntry = activeUniqueEffects.massless[targetID]
		local origMass = (masslessEntry and masslessEntry.origMass)
			or (Spring and Spring.GetUnitMass and Spring.GetUnitMass(targetID))
			or 500
		local entry = activeUniqueEffects.neutron[targetID]
		if not entry then
			entry = {
				origMass = origMass,
				stacks = 1,
				expireFrame = frame + 120,
			}
			activeUniqueEffects.neutron[targetID] = entry
		else
			entry.stacks = entry.stacks + 1
			entry.expireFrame = frame + 120
		end

		if Spring and Spring.SetUnitMass then
			Spring.SetUnitMass(targetID, origMass * 100000.0)
		end
		-- Pin speed and disarm turret rotation during neutron-star density pulse
		if GG and GG.UnitAttributes then
			GG.UnitAttributes.SetUnitModifier(targetID, "speed", 0.05, SOURCE_UNIQUE_WPN)
			GG.UnitAttributes.SetUnitWeaponModifier(
				targetID,
				GG.UnitAttributes.WEAPON_ALL,
				"reloadTime",
				10.0,
				SOURCE_UNIQUE_WPN
			)
		end

		-- If pulse stacks reach collapse threshold (3), trigger gravitational implosion AoE
		if entry.stacks >= 3 then
			entry.stacks = 0
			if Spring and Spring.GetUnitPosition and Spring.GetUnitsInCylinder and Spring.AddUnitDamage then
				local tx, _, tz = Spring.GetUnitPosition(targetID)
				if tx then
					local victims = Spring.GetUnitsInCylinder(tx, tz, 220)
					if victims then
						for i = 1, #victims do
							local vID = victims[i]
							if vID ~= attackerID then
								Spring.AddUnitDamage(vID, 1850, 0, attackerID, -1)
							end
						end
					end
				end
			end
		end
	end
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, projectileID, attackerID)
	if attackerID and heroAssemblies[attackerID] then
		local state = heroAssemblies[attackerID]
		local frame = (Spring and Spring.GetGameFrame and Spring.GetGameFrame()) or 0
		local wpn1 = state.budget and state.budget.primaryWeapon
		local wpn2 = state.budget and state.budget.secondaryWeapon

		-- Add weapon shot heat to chassis thermal budget
		local heatAdded = (wpn1 and wpn1.heatPerShot or 2.5) * 0.5
		state.heat = math.min(state.maxHeat * 1.25, state.heat + heatAdded)

		-- Trigger Unique Weapon physics/circuit/gravity mechanics
		if wpn1 and wpn1.isUnique and wpn1.uniqueMechanic then
			applyUniqueWeaponEffect(wpn1.uniqueMechanic, attackerID, unitID, frame)
		end
		if wpn2 and wpn2.isUnique and wpn2.uniqueMechanic then
			applyUniqueWeaponEffect(wpn2.uniqueMechanic, attackerID, unitID, frame)
		end
	end
	return damage, 1.0
end

function gadget:GameFrame(frame)
	-- Update Hero Thermal Dissipation & Passive Heat every 15 frames (0.5s)
	if frame % 15 == 0 then
		for unitID, state in pairs(heroAssemblies) do
			local b = state.budget
			if b then
				local netCool = (b.heatDissipation - b.passiveHeatGen) * 0.5
				state.heat = math.max(0.0, state.heat - netCool)
				syncAssemblyRulesParams(unitID, state)
			end
		end

		-- Clean up expired Unique Weapon states
		for targetID, data in pairs(activeUniqueEffects.massless) do
			if frame >= data.expireFrame then
				if Spring and Spring.SetUnitMass then
					Spring.SetUnitMass(targetID, data.origMass)
				end
				activeUniqueEffects.massless[targetID] = nil
			end
		end
		for targetID, data in pairs(activeUniqueEffects.neutron) do
			if frame >= data.expireFrame then
				if Spring and Spring.SetUnitMass then
					Spring.SetUnitMass(targetID, data.origMass)
				end
				if GG and GG.UnitAttributes then
					GG.UnitAttributes.SetUnitModifier(targetID, "speed", nil, SOURCE_UNIQUE_WPN)
					GG.UnitAttributes.SetUnitWeaponModifier(
						targetID,
						GG.UnitAttributes.WEAPON_ALL,
						"reloadTime",
						nil,
						SOURCE_UNIQUE_WPN
					)
				end
				activeUniqueEffects.neutron[targetID] = nil
			end
		end
		for targetID, data in pairs(activeUniqueEffects.scrambled) do
			if frame >= data.expireFrame then
				activeUniqueEffects.scrambled[targetID] = nil
			end
		end
	end
end

GG = GG or {}
GG.ARPG_Assembly = {
	InitHeroAssembly = initHeroAssembly,
	GetHeroState = function(unitID)
		return heroAssemblies[unitID]
	end,
	AddMaterials = addMaterials,
	GrantPartDrop = grantPartDrop,
	EquipPart = equipPart,
	CraftPart = craftPart,
	ApplyAssemblyToUnit = applyAssemblyToUnit,
	ApplyUniqueWeaponEffect = applyUniqueWeaponEffect,
}

return GG.ARPG_Assembly
