-- luarules/configs/arpg_parts_db.lua
-- Armored Core Modular Character Assembly, Engineering Budget Solver & Deterministic Crafting DB
-- Design: "What you bolted on IS what you can do." Zero skill tree behind the assembly.
-- Every modifier is a physical tradeoff across Mass, Heat, and Power.

local Materials = {
	reclaimed_alloy = {
		id = "reclaimed_alloy",
		name = "Reclaimed Structural Alloy",
		tier = 1,
		desc = "High-tensile war-stock chassis plating stripped from battlefield wrecks.",
	},
	servo_actuators = {
		id = "servo_actuators",
		name = "Myomer Servo Actuators",
		tier = 1,
		desc = "Precision locomotion joints and recoil-absorbing hydraulic cylinders.",
	},
	reactor_conductors = {
		id = "reactor_conductors",
		name = "Superconducting Bus Coils",
		tier = 2,
		desc = "Zero-resistance power routing conduits and magnetic containment rings.",
	},
	optics_lenses = {
		id = "optics_lenses",
		name = "Coherent Focusing Optics",
		tier = 2,
		desc = "Crystalline beam collimators and multi-spectrum targeting arrays.",
	},
	experimental_cores = {
		id = "experimental_cores",
		name = "Experimental Singularity Cores",
		tier = 3,
		desc = "Intact quantum/gravitational logic cores salvaged from Gantry superunits.",
	},
}

local Parts = {
	-- =========================================================================
	-- 1. FRAMES (CHASSIS LINES: Scout, Constructor, Siege, Experimental)
	-- =========================================================================
	frame_scout_strider = {
		id = "frame_scout_strider",
		slot = "frame",
		name = "Valkyrie-7 Scout Strider Frame",
		family = "scout",
		unitDefName = "armcom",
		techTier = 1,
		requiredBuildPower = 200,
		mass = 180,
		massLimit = 620,
		heatCapacity = 100,
		heatDissipation = 14,
		powerOutput = 0,
		powerDraw = 15,
		stats = {
			maxHealth = 2800,
			baseSpeed = 52.0,
			turnRate = 1450,
			reclaimSpeed = 260,
			buildPower = 260,
			radarRadius = 850,
		},
		recipe = {
			metal = 300,
			energy = 600,
			reclaimed_alloy = 30,
			servo_actuators = 25,
		},
		desc = "Lightweight reconnaissance chassis. High base speed and agility, tight mass and thermal tolerances.",
	},

	frame_constructor_rig = {
		id = "frame_constructor_rig",
		slot = "frame",
		name = "Hephaestus-IV Salvage & Constructor Rig",
		family = "constructor",
		unitDefName = "armcom",
		techTier = 1,
		requiredBuildPower = 200,
		mass = 260,
		massLimit = 820,
		heatCapacity = 135,
		heatDissipation = 16,
		powerOutput = 25,
		powerDraw = 20,
		stats = {
			maxHealth = 3900,
			baseSpeed = 40.0,
			turnRate = 1180,
			reclaimSpeed = 520,
			buildPower = 520,
			radarRadius = 700,
		},
		recipe = {
			metal = 450,
			energy = 900,
			reclaimed_alloy = 45,
			servo_actuators = 20,
			reactor_conductors = 15,
		},
		desc = "Industrial war-salvage chassis. Dual heavy nano-lathes double wreck stripping speed and unlock mid-tier machining.",
	},

	frame_siege_goliath = {
		id = "frame_siege_goliath",
		slot = "frame",
		name = "Bastion-IX Siege Frame",
		family = "siege",
		unitDefName = "corcom",
		techTier = 2,
		requiredBuildPower = 350,
		mass = 420,
		massLimit = 1150,
		heatCapacity = 185,
		heatDissipation = 18,
		powerOutput = 0,
		powerDraw = 35,
		stats = {
			maxHealth = 6400,
			baseSpeed = 31.0,
			turnRate = 920,
			reclaimSpeed = 340,
			buildPower = 380,
			radarRadius = 650,
		},
		recipe = {
			metal = 900,
			energy = 1800,
			reclaimed_alloy = 110,
			servo_actuators = 45,
			reactor_conductors = 30,
		},
		desc = "Heavy assault hull engineered to carry high-recoil ordnance and survive sustained foundry fire.",
	},

	frame_experimental_archon = {
		id = "frame_experimental_archon",
		slot = "frame",
		name = "Archon-Omega Gantry Frame",
		family = "experimental",
		unitDefName = "armcom",
		techTier = 4,
		requiredBuildPower = 650,
		mass = 520,
		massLimit = 1500,
		heatCapacity = 240,
		heatDissipation = 26,
		powerOutput = 60,
		powerDraw = 45,
		stats = {
			maxHealth = 9200,
			baseSpeed = 42.0,
			turnRate = 1280,
			reclaimSpeed = 750,
			buildPower = 800,
			radarRadius = 1100,
		},
		recipe = {
			metal = 2400,
			energy = 6000,
			reclaimed_alloy = 280,
			servo_actuators = 120,
			reactor_conductors = 110,
			optics_lenses = 80,
			experimental_cores = 3,
		},
		desc = "Experimental command chassis machined from superunit salvage. Massive mass allowance and integrated field fabrication.",
	},

	-- =========================================================================
	-- 2. CORES (POWER PLANTS & THERMAL REGULATORS)
	-- =========================================================================
	core_fission_mk1 = {
		id = "core_fission_mk1",
		slot = "core",
		name = "pile-79 Compact Fission Core",
		techTier = 1,
		requiredBuildPower = 200,
		mass = 95,
		heatCapacity = 30,
		heatDissipation = 8,
		passiveHeatGen = 2,
		powerOutput = 160,
		powerDraw = 0,
		stats = {
			energyStorage = 600,
			buildPowerBonus = 40,
		},
		recipe = {
			metal = 250,
			energy = 500,
			reclaimed_alloy = 20,
			reactor_conductors = 15,
		},
		desc = "Reliable baseline fission plant with predictable thermal curve and steady bus voltage.",
	},

	core_cryo_sink = {
		id = "core_cryo_sink",
		slot = "core",
		name = "Sub-Zero Helium Cryo-Core",
		techTier = 2,
		requiredBuildPower = 300,
		mass = 130,
		heatCapacity = 90,
		heatDissipation = 24,
		passiveHeatGen = 0,
		powerOutput = 145,
		powerDraw = 0,
		stats = {
			energyStorage = 550,
			buildPowerBonus = 60,
		},
		recipe = {
			metal = 550,
			energy = 1400,
			reclaimed_alloy = 45,
			reactor_conductors = 40,
		},
		desc = "Trades peak power output for massive liquid-helium heat dissipation, enabling nonstop thermal weapon fire.",
	},

	core_overclock_tokamak = {
		id = "core_overclock_tokamak",
		slot = "core",
		name = "Sunburst Overclocked Tokamak",
		techTier = 3,
		requiredBuildPower = 450,
		mass = 165,
		heatCapacity = 45,
		heatDissipation = 10,
		passiveHeatGen = 7,
		powerOutput = 290,
		powerDraw = 0,
		stats = {
			energyStorage = 1200,
			buildPowerBonus = 150,
			weaponDamageBonus = 0.22,
		},
		recipe = {
			metal = 1100,
			energy = 3200,
			reclaimed_alloy = 80,
			reactor_conductors = 85,
			optics_lenses = 35,
			experimental_cores = 1,
		},
		desc = "Magnetic fusion plant delivering surplus megawatts (+22% weapon output) at the cost of high ambient reactor heat.",
	},

	core_siphon_capacitor = {
		id = "core_siphon_capacitor",
		slot = "core",
		name = "Lazarus Reclaim-Siphon Reactor",
		techTier = 3,
		requiredBuildPower = 420,
		mass = 140,
		heatCapacity = 65,
		heatDissipation = 15,
		passiveHeatGen = 3,
		powerOutput = 220,
		powerDraw = 0,
		stats = {
			energyStorage = 1000,
			buildPowerBonus = 220,
			reclaimHealRatio = 0.35,
		},
		recipe = {
			metal = 950,
			energy = 2600,
			reclaimed_alloy = 70,
			reactor_conductors = 70,
			experimental_cores = 1,
		},
		desc = "Routes nano-lathe reclaim streams directly through the core bus, repairing hull integrity while stripping wrecks.",
	},

	-- =========================================================================
	-- 3. LOCOMOTION ASSEMBLIES
	-- =========================================================================
	loco_servo_biped = {
		id = "loco_servo_biped",
		slot = "locomotion",
		name = "Actuated Biped Striders",
		techTier = 1,
		requiredBuildPower = 200,
		mass = 80,
		heatCapacity = 0,
		heatDissipation = 2,
		powerOutput = 0,
		powerDraw = 20,
		stats = {
			speedMult = 1.05,
			turnRateMult = 1.10,
			maxSlope = 22,
			dashCooldownMult = 0.90,
		},
		recipe = {
			metal = 200,
			energy = 400,
			reclaimed_alloy = 20,
			servo_actuators = 25,
		},
		desc = "Balanced bipedal leg assembly with responsive pivot gyros and low mass overhead.",
	},

	loco_hover_thrusters = {
		id = "loco_hover_thrusters",
		slot = "locomotion",
		name = "Vectored Mag-Lev Hover Skirts",
		techTier = 2,
		requiredBuildPower = 300,
		mass = 65,
		heatCapacity = 0,
		heatDissipation = 0,
		passiveHeatGen = 3,
		powerOutput = 0,
		powerDraw = 48,
		stats = {
			speedMult = 1.28,
			turnRateMult = 1.25,
			maxSlope = 24,
			dashCooldownMult = 0.75,
		},
		recipe = {
			metal = 480,
			energy = 1200,
			reclaimed_alloy = 35,
			servo_actuators = 30,
			reactor_conductors = 35,
		},
		desc = "High-velocity ground-effect thrusters. Exceptional strafing speed and dash recovery at the cost of continuous power draw.",
	},

	loco_spider_allterrain = {
		id = "loco_spider_allterrain",
		slot = "locomotion",
		name = "Arachnid 6-Limb Cliff Walkers",
		techTier = 2,
		requiredBuildPower = 320,
		mass = 135,
		heatCapacity = 15,
		heatDissipation = 3,
		powerOutput = 0,
		powerDraw = 28,
		stats = {
			speedMult = 0.94,
			turnRateMult = 1.30,
			maxSlope = 42,
			dashCooldownMult = 1.05,
			bonusMassLimit = 180,
		},
		recipe = {
			metal = 520,
			energy = 1100,
			reclaimed_alloy = 50,
			servo_actuators = 55,
		},
		desc = "Multi-jointed climbing legs capable of scaling steep scrap heaps and carrying +180 mass without frame sag.",
	},

	loco_boost_treads = {
		id = "loco_boost_treads",
		slot = "locomotion",
		name = "Goliath Armored Siege Tracks",
		techTier = 3,
		requiredBuildPower = 450,
		mass = 190,
		heatCapacity = 30,
		heatDissipation = 4,
		powerOutput = 0,
		powerDraw = 35,
		stats = {
			speedMult = 1.12,
			turnRateMult = 0.85,
			maxSlope = 20,
			dashCooldownMult = 1.15,
			bonusMassLimit = 360,
			bonusMaxHealth = 1800,
		},
		recipe = {
			metal = 880,
			energy = 1900,
			reclaimed_alloy = 120,
			servo_actuators = 70,
		},
		desc = "Reinforced torsion-bar treads adding +360 mass capacity and +1800 structural integrity at the cost of turn rate.",
	},

	-- =========================================================================
	-- 4. WEAPON MOUNTS (BAR ARSENAL + 3 OWNER SIGNATURE UNIQUES)
	-- =========================================================================
	wpn_pulse_laser = {
		id = "wpn_pulse_laser",
		slot = "weapon",
		name = "Helios Dual Pulse Laser",
		barWeaponDef = "ARMCOMLASER",
		techTier = 1,
		requiredBuildPower = 200,
		mass = 55,
		powerDraw = 18,
		heatPerShot = 2.2,
		stats = {
			damageMult = 1.00,
			reloadMult = 0.85,
			range = 340,
			dpsEstimate = 220,
		},
		recipe = {
			metal = 180,
			energy = 400,
			reclaimed_alloy = 15,
			optics_lenses = 12,
		},
		desc = "Standard BAR close-quarters beam laser re-homed onto a stabilized shoulder gimbal. Low heat, zero ammunition.",
	},

	wpn_gauss_repeater = {
		id = "wpn_gauss_repeater",
		slot = "weapon",
		name = "Viper-9 Gauss Rail Repeater",
		barWeaponDef = "ARMCOMLASER",
		techTier = 2,
		requiredBuildPower = 300,
		mass = 110,
		powerDraw = 32,
		heatPerShot = 5.5,
		stats = {
			damageMult = 1.65,
			reloadMult = 1.10,
			range = 440,
			impulseMult = 2.2,
			dpsEstimate = 360,
		},
		recipe = {
			metal = 420,
			energy = 950,
			reclaimed_alloy = 45,
			reactor_conductors = 30,
			optics_lenses = 20,
		},
		desc = "High-velocity electromagnetic slug thrower. Punches through medium bot armor with high kinetic knockback.",
	},

	wpn_plasma_howitzer = {
		id = "wpn_plasma_howitzer",
		slot = "weapon",
		name = "Thumper Siege Plasma Cannon",
		barWeaponDef = "ARMCOMLASER",
		techTier = 2,
		requiredBuildPower = 320,
		mass = 145,
		powerDraw = 24,
		heatPerShot = 7.8,
		stats = {
			damageMult = 2.10,
			reloadMult = 1.45,
			range = 480,
			aoeRadius = 96,
			dpsEstimate = 390,
		},
		recipe = {
			metal = 480,
			energy = 1100,
			reclaimed_alloy = 60,
			servo_actuators = 30,
			reactor_conductors = 25,
		},
		desc = "Heavy ballistic plasma cannon salvaged from Cortex siege stock. High mass and recoil, devastating pack AoE.",
	},

	wpn_emp_paralyzer = {
		id = "wpn_emp_paralyzer",
		slot = "weapon",
		name = "tesla-Arc Paralyzer Projector",
		barWeaponDef = "ARMCOMLASER",
		techTier = 2,
		requiredBuildPower = 300,
		mass = 75,
		powerDraw = 45,
		heatPerShot = 4.0,
		stats = {
			damageMult = 0.85,
			paralyzeMult = 3.0,
			reloadMult = 0.90,
			range = 380,
			dpsEstimate = 260,
		},
		recipe = {
			metal = 390,
			energy = 1300,
			reclaimed_alloy = 25,
			reactor_conductors = 45,
			optics_lenses = 25,
		},
		desc = "High-voltage EMP beam that locks enemy actuators in place, letting you safely channel salvage in combat.",
	},

	wpn_dgun_condenser = {
		id = "wpn_dgun_condenser",
		slot = "weapon",
		name = "Annihilator D-Gun Condenser",
		barWeaponDef = "DISINTEGRATOR",
		techTier = 3,
		requiredBuildPower = 500,
		mass = 175,
		powerDraw = 75,
		heatPerShot = 18.0,
		stats = {
			damageMult = 3.20,
			reloadMult = 1.60,
			range = 360,
			dpsEstimate = 680,
		},
		recipe = {
			metal = 1200,
			energy = 3800,
			reclaimed_alloy = 95,
			reactor_conductors = 90,
			optics_lenses = 65,
			experimental_cores = 2,
		},
		desc = "Miniaturized BAR Commander Disintegrator. Vaporizes standard hulls instantly at extreme thermal and power cost.",
	},

	-- =========================================================================
	-- OWNER SIGNATURE UNIQUE WEAPONS (Letter 011 Oct 31 / Nov 1 Brainstorm)
	-- =========================================================================
	wpn_unique_massless_recoil = {
		id = "wpn_unique_massless_recoil",
		slot = "weapon",
		name = "UNIQUE: Zero-Higgs 99.99% Massless Recoil Cannon",
		barWeaponDef = "ARMCOMLASER",
		isUnique = true,
		uniqueMechanic = "massless_recoil",
		techTier = 3,
		requiredBuildPower = 480,
		mass = 115,
		powerDraw = 58,
		heatPerShot = 8.5,
		stats = {
			damageMult = 1.85,
			reloadMult = 1.00,
			range = 460,
			massReductionFactor = 0.0001, -- Reduces target mass by 99.99%
			recoilLaunchImpulse = 1850.0,
		},
		recipe = {
			metal = 1400,
			energy = 4200,
			reclaimed_alloy = 110,
			reactor_conductors = 95,
			optics_lenses = 75,
			experimental_cores = 2,
		},
		desc = "Suppresses target Higgs coupling on impact, making the target 99.99% massless so weapon recoil launches them across the map. Heavy armor encumbrance inverts into kinetic collision trauma.",
	},

	wpn_unique_topological_scrambler = {
		id = "wpn_unique_topological_scrambler",
		slot = "weapon",
		name = "UNIQUE: Möbius Quantum Topological Scrambler",
		barWeaponDef = "ARMCOMLASER",
		isUnique = true,
		uniqueMechanic = "topological_scrambler",
		techTier = 3,
		requiredBuildPower = 500,
		mass = 95,
		powerDraw = 68,
		heatPerShot = 9.0,
		stats = {
			damageMult = 1.40,
			reloadMult = 1.05,
			range = 420,
			scrambleDurationFrames = 240, -- 8 seconds of topological circuit inversion
			chainArcRadius = 190,
		},
		recipe = {
			metal = 1500,
			energy = 4800,
			reclaimed_alloy = 85,
			reactor_conductors = 120,
			optics_lenses = 95,
			experimental_cores = 2,
		},
		desc = "Rearranges robot circuits topologically instead of destroying them: non-boss machines invert friend-or-foe matrices to attack their own pack while bosses suffer recursive logic-gate arcs.",
	},

	wpn_unique_neutron_mass_pulse = {
		id = "wpn_unique_neutron_mass_pulse",
		slot = "weapon",
		name = "UNIQUE: Chandrasekhar Neutron-Star Mass Dial",
		barWeaponDef = "ARMCOMLASER",
		isUnique = true,
		uniqueMechanic = "neutron_mass_pulse",
		techTier = 4,
		requiredBuildPower = 650,
		mass = 210,
		powerDraw = 88,
		heatPerShot = 14.5,
		stats = {
			damageMult = 2.65,
			reloadMult = 1.35,
			range = 430,
			neutronMassMultiplier = 100000.0,
			disarmDurationFrames = 120,
			collapseThresholdStacks = 3,
		},
		recipe = {
			metal = 2200,
			energy = 6500,
			reclaimed_alloy = 190,
			servo_actuators = 90,
			reactor_conductors = 150,
			optics_lenses = 110,
			experimental_cores = 4,
		},
		desc = "Briefly makes an enemy's weapon weigh as much as a neutron star: short pulses disarm and pin enemy turrets to the ground; sustained pulses collapse the target in a gravitational implosion.",
	},

	-- =========================================================================
	-- 5. MODULE SLOTS (BOLTED HARDWARE = ACTIVE ABILITIES; ZERO SKILL TREE)
	-- =========================================================================
	mod_vectored_dash = {
		id = "mod_vectored_dash",
		slot = "module",
		name = "Icarus Vectored Burst Thrusters",
		techTier = 1,
		requiredBuildPower = 200,
		mass = 40,
		powerDraw = 12,
		stats = {
			speedMult = 1.04,
		},
		ability = {
			id = "vectored_dash",
			name = "Vectored Thruster Dash",
			hotkey = "SPACE / Q",
			cooldownFrames = 90, -- 3.0s
			heatCost = 16,
			energyCost = 85,
			dashDistance = 240,
			iframeFrames = 18, -- 0.6s invulnerability during burst displacement
			desc = "Fires lateral plasma thrusters for instant directional displacement and 0.6s dodge immunity against telegraphed strikes.",
		},
		recipe = {
			metal = 160,
			energy = 350,
			reclaimed_alloy = 15,
			servo_actuators = 20,
		},
		desc = "Bolts lateral burst nozzles to the hip assembly. Grants active Vectored Thruster Dash ability.",
	},

	mod_pile_bunker = {
		id = "mod_pile_bunker",
		slot = "module",
		name = "Krupp-9 Hydraulic Pile Bunker Arm",
		techTier = 1,
		requiredBuildPower = 220,
		mass = 85,
		powerDraw = 10,
		stats = {
			bonusMaxHealth = 450,
		},
		ability = {
			id = "pile_bunker_strike",
			name = "Pile Bunker Strike",
			hotkey = "W",
			cooldownFrames = 135, -- 4.5s
			heatCost = 24,
			energyCost = 110,
			range = 175,
			damage = 1450,
			armorShatterMult = 1.35,
			knockbackImpulse = 950,
			desc = "Drives a solid tungsten-carbide spike into close-range targets for 1450 kinetic damage and shatters armor.",
		},
		recipe = {
			metal = 260,
			energy = 500,
			reclaimed_alloy = 35,
			servo_actuators = 30,
		},
		desc = "Arm-mounted explosive kinetic stake. If your arm is a pile bunker, your heavy attack IS a pile bunker.",
	},

	mod_radar_scanner = {
		id = "mod_radar_scanner",
		slot = "module",
		name = "Argus Deep-Spectrum Radar Array",
		techTier = 1,
		requiredBuildPower = 200,
		mass = 35,
		powerDraw = 22,
		stats = {
			bonusRadarRadius = 600,
			bonusLosRadius = 180,
		},
		ability = {
			id = "deep_salvage_ping",
			name = "Deep Salvage & Threat Ping",
			hotkey = "E",
			cooldownFrames = 210, -- 7.0s
			heatCost = 10,
			energyCost = 140,
			radius = 750,
			vulnerabilityMult = 1.30,
			durationFrames = 180,
			desc = "Sweeps a 750-elmo radius, highlighting high-yield jackpot wrecks and marking enemy structural weakpoints (+30% damage taken).",
		},
		recipe = {
			metal = 210,
			energy = 600,
			reclaimed_alloy = 15,
			optics_lenses = 25,
		},
		desc = "Back-mounted phased-array radar dome. Grants active Deep Salvage & Threat Ping utility.",
	},

	mod_thermal_purge = {
		id = "mod_thermal_purge",
		slot = "module",
		name = "Vulcan Emergency Thermal Vent Manifold",
		techTier = 2,
		requiredBuildPower = 300,
		mass = 50,
		powerDraw = 14,
		stats = {
			bonusHeatDissipation = 6,
		},
		ability = {
			id = "thermal_purge_nova",
			name = "Thermal Purge Nova",
			hotkey = "R",
			cooldownFrames = 240, -- 8.0s
			heatCost = -65, -- Vents 65 Heat!
			energyCost = 160,
			radius = 260,
			baseDamage = 650,
			damagePerHeatVented = 18,
			desc = "Vents up to 65 accumulated chassis Heat into a 260-radius plasma shockwave that scales with vented thermal load.",
		},
		recipe = {
			metal = 380,
			energy = 900,
			reclaimed_alloy = 35,
			reactor_conductors = 35,
		},
		desc = "Turns excess reactor heat into an offensive weapon, preventing thermal lockout during heavy siege exchanges.",
	},

	mod_magnetic_salvage = {
		id = "mod_magnetic_salvage",
		slot = "module",
		name = "Mag-Lathe Overdrive Tractor Array",
		techTier = 2,
		requiredBuildPower = 320,
		mass = 65,
		powerDraw = 26,
		stats = {
			bonusReclaimSpeed = 240,
		},
		ability = {
			id = "overdrive_salvage_beam",
			name = "Magnetic Salvage Overdrive",
			hotkey = "F",
			cooldownFrames = 270, -- 9.0s
			heatCost = 22,
			energyCost = 180,
			radius = 340,
			durationFrames = 180,
			reclaimSpeedMultiplier = 3.0,
			barrierPerMetal = 1.5,
			desc = "Triples reclaim speed for 6s, auto-strips wrecks within 340 elmos, and converts salvaged metal into hull plating.",
		},
		recipe = {
			metal = 460,
			energy = 1150,
			reclaimed_alloy = 40,
			servo_actuators = 25,
			reactor_conductors = 40,
		},
		desc = "Essential for stripping Experimental Boss Jackpot wrecks under heavy horde pressure.",
	},

	mod_siege_bastion = {
		id = "mod_siege_bastion",
		slot = "module",
		name = "Aegis Phase-Lock Bastion Projector",
		techTier = 3,
		requiredBuildPower = 450,
		mass = 110,
		powerDraw = 42,
		stats = {
			bonusMaxHealth = 1200,
		},
		ability = {
			id = "siege_bastion_field",
			name = "Siege Bastion Field",
			hotkey = "G",
			cooldownFrames = 300, -- 10.0s
			heatCost = 28,
			energyCost = 260,
			durationFrames = 150, -- 5.0s
			damageReduction = 0.60,
			desc = "Projects a heavy electromagnetic bastion dome for 5s, reducing incoming damage by 60% while salvaging or firing.",
		},
		recipe = {
			metal = 850,
			energy = 2400,
			reclaimed_alloy = 80,
			reactor_conductors = 75,
			optics_lenses = 45,
			experimental_cores = 1,
		},
		desc = "High-draw defensive field generator engineered for surviving war-foundry boss salvaging.",
	},
}

local DefaultLoadout = {
	frame = "frame_constructor_rig",
	core = "core_fission_mk1",
	locomotion = "loco_servo_biped",
	weapon_primary = "wpn_pulse_laser",
	weapon_secondary = "wpn_plasma_howitzer",
	module_1 = "mod_vectored_dash",
	module_2 = "mod_pile_bunker",
	module_3 = "mod_radar_scanner",
	module_4 = "mod_thermal_purge",
}

local SlotOrder = {
	"frame",
	"core",
	"locomotion",
	"weapon_primary",
	"weapon_secondary",
	"module_1",
	"module_2",
	"module_3",
	"module_4",
}

-- Engineering Budget Solver: computes Mass, Heat, Power & derived capabilities deterministically
local function ComputeAssemblyBudget(loadout)
	loadout = loadout or DefaultLoadout
	local frame = Parts[loadout.frame] or Parts.frame_constructor_rig
	local core = Parts[loadout.core] or Parts.core_fission_mk1
	local loco = Parts[loadout.locomotion] or Parts.loco_servo_biped
	local wpn1 = Parts[loadout.weapon_primary] or Parts.wpn_pulse_laser
	local wpn2 = Parts[loadout.weapon_secondary] or Parts.wpn_plasma_howitzer

	local modules = {
		Parts[loadout.module_1],
		Parts[loadout.module_2],
		Parts[loadout.module_3],
		Parts[loadout.module_4],
	}

	local totalMass = (frame.mass or 0) + (core.mass or 0) + (loco.mass or 0) + (wpn1.mass or 0) + (wpn2.mass or 0)
	local massLimit = (frame.massLimit or 800) + (loco.stats and loco.stats.bonusMassLimit or 0)

	local heatCapacity = (frame.heatCapacity or 100) + (core.heatCapacity or 30) + (loco.heatCapacity or 0)
	local heatDissipation = (frame.heatDissipation or 12) + (core.heatDissipation or 8) + (loco.heatDissipation or 0)
	local passiveHeatGen = (core.passiveHeatGen or 0) + (loco.passiveHeatGen or 0)

	local powerOutput = (frame.powerOutput or 0) + (core.powerOutput or 150)
	local powerDraw = (frame.powerDraw or 20) + (loco.powerDraw or 20) + (wpn1.powerDraw or 15) + (wpn2.powerDraw or 15)

	local maxHealth = (frame.stats and frame.stats.maxHealth or 3500) + (loco.stats and loco.stats.bonusMaxHealth or 0)
	local baseSpeed = frame.stats and frame.stats.baseSpeed or 40.0
	local speedMult = loco.stats and loco.stats.speedMult or 1.0
	local turnRate = (frame.stats and frame.stats.turnRate or 1150) * (loco.stats and loco.stats.turnRateMult or 1.0)
	local reclaimSpeed = frame.stats and frame.stats.reclaimSpeed or 300
	local buildPower = (frame.stats and frame.stats.buildPower or 300) + (core.stats and core.stats.buildPowerBonus or 0)
	local radarRadius = frame.stats and frame.stats.radarRadius or 700
	local losRadius = 480

	local activeAbilities = {}

	for idx = 1, 4 do
		local mod = modules[idx]
		if mod then
			totalMass = totalMass + (mod.mass or 0)
			powerDraw = powerDraw + (mod.powerDraw or 0)
			if mod.stats then
				maxHealth = maxHealth + (mod.stats.bonusMaxHealth or 0)
				speedMult = speedMult * (mod.stats.speedMult or 1.0)
				heatDissipation = heatDissipation + (mod.stats.bonusHeatDissipation or 0)
				reclaimSpeed = reclaimSpeed + (mod.stats.bonusReclaimSpeed or 0)
				radarRadius = radarRadius + (mod.stats.bonusRadarRadius or 0)
				losRadius = losRadius + (mod.stats.bonusLosRadius or 0)
			end
			if mod.ability then
				activeAbilities[#activeAbilities + 1] = {
					slotIndex = idx,
					moduleId = mod.id,
					moduleName = mod.name,
					ability = mod.ability,
				}
			end
		end
	end

	-- Physical Tradeoff 1: Mass Budget vs Locomotion Agility
	local massRatio = totalMass / math.max(1, massLimit)
	local massState = "OPTIMAL"
	if massRatio > 1.0 then
		-- Overweight penalty: reduces movement speed and turn rate proportionally
		local overweightPenalty = math.max(0.45, 1.0 - (massRatio - 1.0) * 0.85)
		speedMult = speedMult * overweightPenalty
		turnRate = turnRate * overweightPenalty
		massState = "OVERWEIGHT"
	elseif massRatio < 0.75 then
		-- Underweight agility bonus
		local underweightBonus = 1.0 + (0.75 - massRatio) * 0.35
		speedMult = speedMult * underweightBonus
		massState = "LIGHTWEIGHT_AGILE"
	end

	-- Physical Tradeoff 2: Power Budget vs Weapon & Capacitor Output
	local netPower = powerOutput - powerDraw
	local weaponDamageMult = ((wpn1.stats and wpn1.stats.damageMult or 1.0) + (wpn2.stats and wpn2.stats.damageMult or 1.0)) * 0.5
	weaponDamageMult = weaponDamageMult * (1.0 + (core.stats and core.stats.weaponDamageBonus or 0))
	local weaponReloadMult = ((wpn1.stats and wpn1.stats.reloadMult or 1.0) + (wpn2.stats and wpn2.stats.reloadMult or 1.0)) * 0.5

	local powerState = "SURPLUS"
	if netPower < 0 then
		-- Power deficit slows weapon recharge and reduces shield/energy regen
		local deficitFactor = math.min(2.0, 1.0 + math.abs(netPower) / 100.0)
		weaponReloadMult = weaponReloadMult * deficitFactor
		powerState = "DEFICIT_BROWNOUT"
	elseif netPower >= 40 then
		-- Surplus power overcharges capacitor reload slightly
		weaponReloadMult = weaponReloadMult * 0.90
		powerState = "OVERCHARGED"
	end

	return {
		totalMass = totalMass,
		massLimit = massLimit,
		massRatio = massRatio,
		massState = massState,
		heatCapacity = heatCapacity,
		heatDissipation = heatDissipation,
		passiveHeatGen = passiveHeatGen,
		powerOutput = powerOutput,
		powerDraw = powerDraw,
		netPower = netPower,
		powerState = powerState,
		maxHealth = math.floor(maxHealth),
		effectiveSpeed = baseSpeed * speedMult,
		speedMult = speedMult,
		turnRate = math.floor(turnRate),
		reclaimSpeed = math.floor(reclaimSpeed),
		buildPower = math.floor(buildPower),
		radarRadius = math.floor(radarRadius),
		losRadius = math.floor(losRadius),
		weaponDamageMult = weaponDamageMult,
		weaponReloadMult = weaponReloadMult,
		primaryWeapon = wpn1,
		secondaryWeapon = wpn2,
		activeAbilities = activeAbilities,
		reclaimHealRatio = core.stats and core.stats.reclaimHealRatio or 0.12,
	}
end

-- Deterministic Crafting Check: verifies tech prerequisite, build power, and bill of materials
local function CanCraftPart(partId, playerState)
	local part = Parts[partId]
	if not part or not part.recipe then
		return false, "UNKNOWN_PART"
	end
	local currentTech = playerState.unlockedTechTier or 1
	if currentTech < (part.techTier or 1) then
		return false, string.format("REQUIRES_TECH_TIER_%d", part.techTier)
	end
	local currentBuildPower = playerState.buildPower or 200
	if currentBuildPower < (part.requiredBuildPower or 200) then
		return false, string.format("REQUIRES_BUILD_POWER_%d", part.requiredBuildPower)
	end
	local mats = playerState.materials or {}
	for matKey, reqAmount in pairs(part.recipe) do
		if matKey ~= "metal" and matKey ~= "energy" then
			local have = mats[matKey] or 0
			if have < reqAmount then
				return false, string.format("MISSING_%s (%d/%d)", string.upper(matKey), have, reqAmount)
			end
		end
	end
	return true, "READY_TO_MACHINE"
end

return {
	Materials = Materials,
	Parts = Parts,
	DefaultLoadout = DefaultLoadout,
	SlotOrder = SlotOrder,
	ComputeAssemblyBudget = ComputeAssemblyBudget,
	CanCraftPart = CanCraftPart,
}
