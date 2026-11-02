//! Deterministic 8-Biome Procedural Map Generator, Heightfield Synthesizer, Grid Pathability
//! Verifier, and Native PNG/SVG/Lua Map Atlas Compiler for Beyond All Reason — Wreckage Protocol.

use std::collections::VecDeque;
use std::fmt::Write as _;

#[derive(Clone, Debug)]
pub struct ProcRng {
    state: u64,
}

impl ProcRng {
    pub fn new(seed: u64) -> Self {
        let mut s = seed % 2_147_483_647;
        if s == 0 {
            s = 1337;
        }
        Self { state: s }
    }

    pub fn next_int(&mut self) -> u64 {
        self.state = (self.state * 48_271) % 2_147_483_647;
        self.state
    }

    pub fn next_f64(&mut self) -> f64 {
        (self.next_int() as f64) / 2_147_483_647.0
    }

    pub fn range_f64(&mut self, min_val: f64, max_val: f64) -> f64 {
        min_val + (max_val - min_val) * self.next_f64()
    }

    pub fn range_usize(&mut self, min_val: usize, max_val: usize) -> usize {
        if max_val <= min_val {
            return min_val;
        }
        min_val + (self.next_int() as usize) % (max_val - min_val + 1)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BiomeKind {
    SalvageYard,
    DerelictFactory,
    SlagRefinery,
    AutomatedWarFoundry,
    OrbitalRailSpine,
    CryoDataVault,
    ScrapCanyonBadlands,
    ExperimentalGantryCitadel,
}

impl BiomeKind {
    pub const ALL: [Self; 8] = [
        Self::SalvageYard,
        Self::DerelictFactory,
        Self::SlagRefinery,
        Self::AutomatedWarFoundry,
        Self::OrbitalRailSpine,
        Self::CryoDataVault,
        Self::ScrapCanyonBadlands,
        Self::ExperimentalGantryCitadel,
    ];

    pub fn from_depth(depth: usize) -> Self {
        Self::ALL[(depth.saturating_sub(1)) % Self::ALL.len()]
    }

    pub fn id(&self) -> &'static str {
        match self {
            Self::SalvageYard => "salvage_yard",
            Self::DerelictFactory => "derelict_factory",
            Self::SlagRefinery => "slag_refinery",
            Self::AutomatedWarFoundry => "automated_war_foundry",
            Self::OrbitalRailSpine => "orbital_rail_spine",
            Self::CryoDataVault => "cryo_data_vault",
            Self::ScrapCanyonBadlands => "scrap_canyon_badlands",
            Self::ExperimentalGantryCitadel => "experimental_gantry_citadel",
        }
    }

    pub fn title(&self) -> &'static str {
        match self {
            Self::SalvageYard => "Rust-Belt Salvage Yard",
            Self::DerelictFactory => "Derelict Assembly Megastructure",
            Self::SlagRefinery => "Molten Slag Smelting Refinery",
            Self::AutomatedWarFoundry => "Automated War-Foundry Caldera",
            Self::OrbitalRailSpine => "Orbital Mag-Rail Spine",
            Self::CryoDataVault => "Sub-Zero Cryo-Computation Vault",
            Self::ScrapCanyonBadlands => "Tectonic Scrap Canyon Badlands",
            Self::ExperimentalGantryCitadel => "Experimental Gantry Citadel",
        }
    }

    pub fn topology(&self) -> &'static str {
        match self {
            Self::SalvageYard => "open_scrapyard_bowls",
            Self::DerelictFactory => "orthogonal_bays",
            Self::SlagRefinery => "catwalk_bridges",
            Self::AutomatedWarFoundry => "foundry_caldera",
            Self::OrbitalRailSpine => "linear_spine_flanks",
            Self::CryoDataVault => "cryo_basins",
            Self::ScrapCanyonBadlands => "switchback_canyons",
            Self::ExperimentalGantryCitadel => "citadel_shield_nodes",
        }
    }

    pub fn spec(&self) -> BiomeSpec {
        match self {
            Self::SalvageYard => BiomeSpec {
                kind: *self,
                tier: 1,
                base_height: 140.0,
                wall_height: 310.0,
                noise_amplitude: 28.0,
                noise_frequency: 0.0025,
                domain_warp_strength: 45.0,
                max_walkable_slope_deg: 22.0,
                room_min: 8,
                room_max: 10,
                wreck_density: 1.35,
                boss_unit: "armcomboss",
                boss_title: "FERAL SALVAGE BAILER MK-I",
                wreck_pool: &["armpw_dead", "corak_dead", "armrock_dead", "armham_dead", "armstump_dead"],
                jackpot_pool: &["armcom_dead", "corcom_dead", "armzeus_dead"],
            },
            Self::DerelictFactory => BiomeSpec {
                kind: *self,
                tier: 2,
                base_height: 180.0,
                wall_height: 380.0,
                noise_amplitude: 14.0,
                noise_frequency: 0.0032,
                domain_warp_strength: 25.0,
                max_walkable_slope_deg: 20.0,
                room_min: 9,
                room_max: 11,
                wreck_density: 1.50,
                boss_unit: "armraz",
                boss_title: "AUTOMATED SIEGE WARDEN RAZORBACK",
                wreck_pool: &["armzeus_dead", "armfido_dead", "cormort_dead", "corpyro_dead", "armbull_dead"],
                jackpot_pool: &["armmav_dead", "armsnipe_dead", "corsumo_dead"],
            },
            Self::SlagRefinery => BiomeSpec {
                kind: *self,
                tier: 2,
                base_height: 170.0,
                wall_height: 395.0,
                noise_amplitude: 22.0,
                noise_frequency: 0.0029,
                domain_warp_strength: 38.0,
                max_walkable_slope_deg: 21.0,
                room_min: 9,
                room_max: 11,
                wreck_density: 1.55,
                boss_unit: "corshiva",
                boss_title: "SMELTER BEHEMOTH SHIVA-IX",
                wreck_pool: &["armbull_dead", "correap_dead", "corgol_dead", "corpyro_dead", "armmoho_dead"],
                jackpot_pool: &["corsumo_dead", "corgol_dead", "armfus_dead"],
            },
            Self::AutomatedWarFoundry => BiomeSpec {
                kind: *self,
                tier: 3,
                base_height: 165.0,
                wall_height: 410.0,
                noise_amplitude: 34.0,
                noise_frequency: 0.0028,
                domain_warp_strength: 55.0,
                max_walkable_slope_deg: 21.0,
                room_min: 10,
                room_max: 12,
                wreck_density: 1.65,
                boss_unit: "armthor",
                boss_title: "FOUNDRY OVERSEER THOR-PRIME",
                wreck_pool: &["armmav_dead", "armsnipe_dead", "corsumo_dead", "corgol_dead", "armfus_dead"],
                jackpot_pool: &["armbanth_dead", "armraz_dead", "corkarg_dead"],
            },
            Self::OrbitalRailSpine => BiomeSpec {
                kind: *self,
                tier: 3,
                base_height: 195.0,
                wall_height: 430.0,
                noise_amplitude: 18.0,
                noise_frequency: 0.0024,
                domain_warp_strength: 30.0,
                max_walkable_slope_deg: 20.0,
                room_min: 10,
                room_max: 12,
                wreck_density: 1.60,
                boss_unit: "armvang",
                boss_title: "RAIL-SPINE ARTILLERY DREADNOUGHT VANGUARD",
                wreck_pool: &["armsnipe_dead", "armmanni_dead", "cormort_dead", "armmav_dead", "corkarg_dead"],
                jackpot_pool: &["armraz_dead", "corcat_dead", "armthor_dead"],
            },
            Self::CryoDataVault => BiomeSpec {
                kind: *self,
                tier: 3,
                base_height: 155.0,
                wall_height: 390.0,
                noise_amplitude: 20.0,
                noise_frequency: 0.0026,
                domain_warp_strength: 35.0,
                max_walkable_slope_deg: 21.0,
                room_min: 10,
                room_max: 12,
                wreck_density: 1.70,
                boss_unit: "armbanth",
                boss_title: "CRYO-PRESERVED TITAN BANTHA-ZERO",
                wreck_pool: &["armanni_dead", "armsnipe_dead", "armfus_dead", "armafus_dead", "corgol_dead"],
                jackpot_pool: &["armbanth_dead", "corkorg_dead", "armafus_dead"],
            },
            Self::ScrapCanyonBadlands => BiomeSpec {
                kind: *self,
                tier: 4,
                base_height: 150.0,
                wall_height: 445.0,
                noise_amplitude: 38.0,
                noise_frequency: 0.0030,
                domain_warp_strength: 65.0,
                max_walkable_slope_deg: 22.0,
                room_min: 11,
                room_max: 13,
                wreck_density: 1.80,
                boss_unit: "corjugg",
                boss_title: "CANYON COLOSSUS BEHEMOTH-JUGGERNAUT",
                wreck_pool: &["corkarg_dead", "corcat_dead", "armmar_dead", "armraz_dead", "corgol_dead"],
                jackpot_pool: &["corkorg_dead", "corjugg_dead", "armbanth_dead"],
            },
            Self::ExperimentalGantryCitadel => BiomeSpec {
                kind: *self,
                tier: 4,
                base_height: 200.0,
                wall_height: 460.0,
                noise_amplitude: 24.0,
                noise_frequency: 0.0022,
                domain_warp_strength: 40.0,
                max_walkable_slope_deg: 20.0,
                room_min: 11,
                room_max: 14,
                wreck_density: 1.90,
                boss_unit: "corkorg",
                boss_title: "EXPERIMENTAL JUGGERNAUT KORGOTH-OMEGA",
                wreck_pool: &["armbanth_dead", "armraz_dead", "armmar_dead", "corkarg_dead", "corcat_dead"],
                jackpot_pool: &["corkorg_dead", "corjugg_dead", "armthor_dead"],
            },
        }
    }
}

#[derive(Clone, Debug)]
pub struct BiomeSpec {
    pub kind: BiomeKind,
    pub tier: u32,
    pub base_height: f64,
    pub wall_height: f64,
    pub noise_amplitude: f64,
    pub noise_frequency: f64,
    pub domain_warp_strength: f64,
    pub max_walkable_slope_deg: f64,
    pub room_min: usize,
    pub room_max: usize,
    pub wreck_density: f64,
    pub boss_unit: &'static str,
    pub boss_title: &'static str,
    pub wreck_pool: &'static [&'static str],
    pub jackpot_pool: &'static [&'static str],
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RoomKind {
    DropZone,
    SalvageField,
    ChokePoint,
    FoundryCache,
    HazardGauntlet,
    SetpieceVault,
    BossArena,
    ExtractionGate,
}

impl RoomKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::DropZone => "drop_zone",
            Self::SalvageField => "salvage_field",
            Self::ChokePoint => "choke_point",
            Self::FoundryCache => "foundry_cache",
            Self::HazardGauntlet => "hazard_gauntlet",
            Self::SetpieceVault => "setpiece_vault",
            Self::BossArena => "boss_arena",
            Self::ExtractionGate => "extraction_gate",
        }
    }
}

#[derive(Clone, Debug)]
pub struct CoverPillar {
    pub x: f64,
    pub z: f64,
    pub radius: f64,
    pub height: f64,
}

#[derive(Clone, Debug)]
pub struct RoomNode {
    pub id: usize,
    pub kind: RoomKind,
    pub x: f64,
    pub z: f64,
    pub radius: f64,
    pub elevation: f64,
    pub has_garage: bool,
    pub pillars: Vec<CoverPillar>,
}

#[derive(Clone, Debug)]
pub struct CorridorEdge {
    pub from: usize,
    pub to: usize,
    pub width: f64,
    pub length: f64,
    pub slope_deg: f64,
    pub is_primary: bool,
}

#[derive(Clone, Debug)]
pub struct PlannedWreck {
    pub node_id: usize,
    pub feature_name: &'static str,
    pub x: f64,
    pub z: f64,
    pub is_jackpot: bool,
    pub is_overclocked_reactor: bool,
    pub metal: u32,
    pub energy: u32,
}

#[derive(Clone, Debug)]
pub struct SetpieceObjective {
    pub id: usize,
    pub node_id: usize,
    pub kind: &'static str,
    pub x: f64,
    pub z: f64,
    pub radius: f64,
}

#[derive(Clone, Debug)]
pub struct ZoneBlueprint {
    pub seed: u64,
    pub zone_depth: usize,
    pub biome: BiomeSpec,
    pub map_size_x: f64,
    pub map_size_z: f64,
    pub nodes: Vec<RoomNode>,
    pub edges: Vec<CorridorEdge>,
    pub planned_wrecks: Vec<PlannedWreck>,
    pub setpieces: Vec<SetpieceObjective>,
}

fn smoothstep(t: f64) -> f64 {
    let c = t.clamp(0.0, 1.0);
    c * c * (3.0 - 2.0 * c)
}

fn lerp(a: f64, b: f64, t: f64) -> f64 {
    a + (b - a) * t
}

fn hash2d(ix: i64, iz: i64, seed: u64) -> f64 {
    let n = (ix.wrapping_mul(374_761_393))
        .wrapping_add(iz.wrapping_mul(668_265_263))
        .wrapping_add((seed as i64).wrapping_mul(1_442_695_041));
    let m = n.rem_euclid(2_147_483_647);
    let k = (m.wrapping_mul(1_103_515_245).wrapping_add(12_345)).rem_euclid(2_147_483_647);
    (k as f64 / 2_147_483_647.0) * 2.0 - 1.0
}

fn value_noise_2d(x: f64, z: f64, seed: u64) -> f64 {
    let ix = x.floor() as i64;
    let iz = z.floor() as i64;
    let fx = smoothstep(x - (ix as f64));
    let fz = smoothstep(z - (iz as f64));

    let v00 = hash2d(ix, iz, seed);
    let v10 = hash2d(ix + 1, iz, seed);
    let v01 = hash2d(ix, iz + 1, seed);
    let v11 = hash2d(ix + 1, iz + 1, seed);

    let vx0 = lerp(v00, v10, fx);
    let vx1 = lerp(v01, v11, fx);
    lerp(vx0, vx1, fz)
}

fn fbm_2d(x: f64, z: f64, seed: u64, octaves: usize) -> f64 {
    let mut total = 0.0;
    let mut amp = 0.5;
    let mut freq = 1.0;
    let mut norm = 0.0;
    for i in 1..=octaves {
        total += value_noise_2d(x * freq, z * freq, seed + (i as u64) * 101) * amp;
        norm += amp;
        amp *= 0.5;
        freq *= 2.03;
    }
    total / norm.max(1e-6)
}

pub fn domain_warped_noise_2d(x: f64, z: f64, freq: f64, warp_strength: f64, seed: u64) -> f64 {
    let qx = fbm_2d(x * freq, z * freq, seed + 17, 3);
    let qz = fbm_2d(x * freq + 5.2, z * freq + 1.3, seed + 53, 3);
    let wx = x + qx * warp_strength;
    let wz = z + qz * warp_strength;
    fbm_2d(wx * freq, wz * freq, seed + 97, 4)
}

fn point_to_segment_projection(px: f64, pz: f64, ax: f64, az: f64, bx: f64, bz: f64) -> (f64, f64) {
    let dx = bx - ax;
    let dz = bz - az;
    let len_sq = dx * dx + dz * dz;
    if len_sq <= 1e-6 {
        let dist = ((px - ax).powi(2) + (pz - az).powi(2)).sqrt();
        return (dist, 0.0);
    }
    let t = (((px - ax) * dx + (pz - az) * dz) / len_sq).clamp(0.0, 1.0);
    let proj_x = ax + t * dx;
    let proj_z = az + t * dz;
    let dist = ((px - proj_x).powi(2) + (pz - proj_z).powi(2)).sqrt();
    (dist, t)
}

fn compute_room_position(
    topology: &str,
    idx: usize,
    middle_count: usize,
    margin: f64,
    map_size_x: f64,
    map_size_z: f64,
    rng: &mut ProcRng,
) -> (f64, f64) {
    let progress = (idx as f64) / ((middle_count + 2) as f64);
    let span_x = map_size_x - 2.0 * margin;
    let span_z = map_size_z - 2.0 * margin;
    let base_x = margin + progress * span_x;
    let base_z = margin + progress * span_z;
    let min_dim = map_size_x.min(map_size_z);

    if topology == "orthogonal_bays" {
        let grid_step = 360.0;
        let ortho_sign = if (idx + 1) % 2 == 0 { 1.0 } else { -1.0 };
        let raw_x = base_x + ortho_sign * 0.18 * min_dim;
        let raw_z = base_z - ortho_sign * 0.18 * min_dim;
        let qx = ((raw_x / grid_step) + 0.5).floor() * grid_step;
        let qz = ((raw_z / grid_step) + 0.5).floor() * grid_step;
        (
            qx.clamp(margin, map_size_x - margin),
            qz.clamp(margin, map_size_z - margin),
        )
    } else if topology == "linear_spine_flanks" {
        let ortho_sign = if (idx + 1) % 2 == 0 { 1.0 } else { -1.0 };
        let flank_offset = if (idx + 1) % 3 == 0 { 0.04 } else { 0.14 };
        let nx = base_x + ortho_sign * flank_offset * min_dim;
        let nz = base_z - ortho_sign * flank_offset * min_dim;
        (
            nx.clamp(margin, map_size_x - margin),
            nz.clamp(margin, map_size_z - margin),
        )
    } else if topology == "switchback_canyons" {
        let wave = (progress * std::f64::consts::PI * 2.5).sin() * 0.28 * min_dim;
        let nx = base_x + wave;
        let nz = base_z - wave * 0.75;
        (
            nx.clamp(margin, map_size_x - margin),
            nz.clamp(margin, map_size_z - margin),
        )
    } else {
        let ortho_sign = if (idx + 1) % 2 == 0 { 1.0 } else { -1.0 };
        let ortho_mag = rng.range_f64(0.12, 0.26) * min_dim;
        let nx = base_x + ortho_sign * ortho_mag;
        let nz = base_z - ortho_sign * ortho_mag;
        (
            nx.clamp(margin, map_size_x - margin),
            nz.clamp(margin, map_size_z - margin),
        )
    }
}

pub fn build_zone_blueprint(
    seed: u64,
    zone_depth: usize,
    map_size_x: f64,
    map_size_z: f64,
    biome_override: Option<BiomeKind>,
) -> ZoneBlueprint {
    let depth = zone_depth.max(1);
    let mut rng = ProcRng::new(seed.wrapping_add((depth as u64) * 7919));
    let biome_kind = biome_override.unwrap_or_else(|| BiomeKind::from_depth(depth));
    let biome = biome_kind.spec();
    let topology = biome_kind.topology();

    let room_count = rng.range_usize(biome.room_min, biome.room_max);
    let margin = map_size_x.min(map_size_z) * 0.12;

    let mut nodes = Vec::with_capacity(room_count);
    let mut edges = Vec::new();

    nodes.push(RoomNode {
        id: 0,
        kind: RoomKind::DropZone,
        x: margin + rng.range_f64(40.0, 140.0),
        z: margin + rng.range_f64(40.0, 140.0),
        radius: 280.0,
        elevation: biome.base_height,
        has_garage: true,
        pillars: Vec::new(),
    });

    let middle_count = room_count - 3;
    let room_cycle = [
        RoomKind::SalvageField,
        RoomKind::ChokePoint,
        RoomKind::FoundryCache,
        RoomKind::SalvageField,
        RoomKind::HazardGauntlet,
        RoomKind::SetpieceVault,
    ];

    for i in 1..=middle_count {
        let kind = room_cycle[(i - 1) % room_cycle.len()];
        let (nx, nz) = compute_room_position(topology, i, middle_count, margin, map_size_x, map_size_z, &mut rng);

        let radius = match kind {
            RoomKind::SalvageField => rng.range_f64(280.0, 340.0),
            RoomKind::ChokePoint => rng.range_f64(195.0, 235.0),
            RoomKind::FoundryCache | RoomKind::SetpieceVault => rng.range_f64(245.0, 295.0),
            RoomKind::HazardGauntlet => rng.range_f64(250.0, 310.0),
            _ => 255.0,
        };

        let prev_elev = nodes[i - 1].elevation;
        let elev_delta = rng.range_f64(-15.0, 18.0);
        let elevation = (prev_elev + elev_delta).clamp(biome.base_height - 30.0, biome.base_height + 50.0);

        let mut pillars = Vec::new();
        if kind == RoomKind::ChokePoint {
            let p_angle = rng.range_f64(0.0, std::f64::consts::PI * 2.0);
            pillars.push(CoverPillar {
                x: nx + p_angle.cos() * 70.0,
                z: nz + p_angle.sin() * 70.0,
                radius: 34.0,
                height: elevation + 95.0,
            });
        }

        nodes.push(RoomNode {
            id: i,
            kind,
            x: nx,
            z: nz,
            radius,
            elevation,
            has_garage: matches!(kind, RoomKind::FoundryCache | RoomKind::SetpieceVault),
            pillars,
        });
    }

    let boss_idx = room_count - 2;
    let boss_x = map_size_x - margin - rng.range_f64(220.0, 320.0);
    let boss_z = map_size_z - margin - rng.range_f64(220.0, 320.0);
    let boss_elev = biome.base_height + 24.0;
    let mut boss_pillars = Vec::new();
    for p in 0..4 {
        let angle = (p as f64) * (std::f64::consts::PI * 0.5) + (std::f64::consts::PI * 0.25);
        boss_pillars.push(CoverPillar {
            x: boss_x + angle.cos() * 195.0,
            z: boss_z + angle.sin() * 195.0,
            radius: 40.0,
            height: boss_elev + 115.0,
        });
    }

    nodes.push(RoomNode {
        id: boss_idx,
        kind: RoomKind::BossArena,
        x: boss_x,
        z: boss_z,
        radius: 420.0,
        elevation: boss_elev,
        has_garage: false,
        pillars: boss_pillars,
    });

    let ext_idx = room_count - 1;
    nodes.push(RoomNode {
        id: ext_idx,
        kind: RoomKind::ExtractionGate,
        x: (boss_x + 260.0).min(map_size_x - margin * 0.75),
        z: (boss_z + 260.0).min(map_size_z - margin * 0.75),
        radius: 210.0,
        elevation: boss_elev,
        has_garage: true,
        pillars: Vec::new(),
    });

    let corridor_w = if topology == "catwalk_bridges" { 115.0 } else { 135.0 };

    for i in 0..(room_count - 1) {
        let u = &nodes[i];
        let v = &nodes[i + 1];
        let dist = ((v.x - u.x).powi(2) + (v.z - u.z).powi(2)).sqrt();
        let elev_diff = (v.elevation - u.elevation).abs();
        let slope_deg = elev_diff.atan2(dist.max(120.0)).to_degrees();
        edges.push(CorridorEdge {
            from: i,
            to: i + 1,
            width: if v.kind == RoomKind::BossArena { 165.0 } else { corridor_w },
            length: dist,
            slope_deg,
            is_primary: true,
        });
    }

    for i in 1..(room_count.saturating_sub(3)) {
        if rng.next_f64() < 0.65 {
            let u = &nodes[i];
            let v = &nodes[i + 2];
            let dist = ((v.x - u.x).powi(2) + (v.z - u.z).powi(2)).sqrt();
            let elev_diff = (v.elevation - u.elevation).abs();
            let slope_deg = elev_diff.atan2(dist.max(120.0)).to_degrees();
            if slope_deg <= biome.max_walkable_slope_deg {
                edges.push(CorridorEdge {
                    from: i,
                    to: i + 2,
                    width: 115.0,
                    length: dist,
                    slope_deg,
                    is_primary: false,
                });
            }
        }
    }

    let mut planned_wrecks = Vec::new();
    let mut setpieces = Vec::new();
    let setpiece_cycle = [
        "locked_armory_vault",
        "live_constructor_bay",
        "overclocked_reactor_wreck",
    ];

    for node in &nodes {
        if matches!(
            node.kind,
            RoomKind::SalvageField | RoomKind::FoundryCache | RoomKind::ChokePoint | RoomKind::SetpieceVault
        ) {
            let base_wrecks = match node.kind {
                RoomKind::SalvageField => 18,
                RoomKind::FoundryCache | RoomKind::SetpieceVault => 14,
                _ => 8,
            };
            let count = ((base_wrecks as f64) * biome.wreck_density).floor() as usize;
            for w in 0..count {
                let angle = rng.range_f64(0.0, std::f64::consts::PI * 2.0);
                let r = rng.range_f64(35.0, node.radius * 0.82);
                let is_jackpot = matches!(node.kind, RoomKind::FoundryCache | RoomKind::SetpieceVault) && w < 3
                    || (w == 0 && rng.next_f64() < 0.45);
                let is_overclocked_reactor = node.kind == RoomKind::SetpieceVault && w == 0;
                let pool = if is_jackpot {
                    biome.jackpot_pool
                } else {
                    biome.wreck_pool
                };
                let feature_name = pool[rng.range_usize(0, pool.len() - 1)];
                planned_wrecks.push(PlannedWreck {
                    node_id: node.id,
                    feature_name,
                    x: node.x + angle.cos() * r,
                    z: node.z + angle.sin() * r,
                    is_jackpot,
                    is_overclocked_reactor,
                    metal: if is_jackpot { 450 * biome.tier } else { 150 * biome.tier },
                    energy: if is_jackpot { 300 * biome.tier } else { 90 * biome.tier },
                });
            }
        }

        if matches!(node.kind, RoomKind::FoundryCache | RoomKind::SetpieceVault) {
            let sp_kind = setpiece_cycle[setpieces.len() % setpiece_cycle.len()];
            setpieces.push(SetpieceObjective {
                id: setpieces.len() + 1,
                node_id: node.id,
                kind: sp_kind,
                x: node.x,
                z: node.z,
                radius: node.radius * 0.65,
            });
        }
    }

    ZoneBlueprint {
        seed,
        zone_depth: depth,
        biome,
        map_size_x,
        map_size_z,
        nodes,
        edges,
        planned_wrecks,
        setpieces,
    }
}

pub fn sample_zone_height(bp: &ZoneBlueprint, x: f64, z: f64) -> f64 {
    let biome = &bp.biome;
    let n_val = domain_warped_noise_2d(x, z, biome.noise_frequency, biome.domain_warp_strength, bp.seed);
    let wall_elev = biome.wall_height + n_val * biome.noise_amplitude;

    let mut min_wall_blend = 1.0_f64;
    let mut weighted_elev_sum = 0.0_f64;
    let mut weight_sum = 0.0_f64;

    for node in &bp.nodes {
        let dist = ((x - node.x).powi(2) + (z - node.z).powi(2)).sqrt();
        let inner_r = node.radius * 0.78;
        let outer_r = node.radius * 1.18;
        if dist <= outer_r {
            let blend = if dist > inner_r {
                smoothstep((dist - inner_r) / (outer_r - inner_r).max(1.0))
            } else {
                0.0
            };
            min_wall_blend = min_wall_blend.min(blend);
            let w = (1.0 - blend).powi(2).max(0.001);
            weighted_elev_sum += node.elevation * w;
            weight_sum += w;
        }
    }

    for edge in &bp.edges {
        let u = &bp.nodes[edge.from];
        let v = &bp.nodes[edge.to];
        let (dist, t) = point_to_segment_projection(x, z, u.x, u.z, v.x, v.z);
        let inner_w = edge.width * 0.65;
        let outer_w = edge.width * 1.25;
        if dist <= outer_w {
            let blend = if dist > inner_w {
                smoothstep((dist - inner_w) / (outer_w - inner_w).max(1.0))
            } else {
                0.0
            };
            min_wall_blend = min_wall_blend.min(blend);
            let ramp_elev = lerp(u.elevation, v.elevation, smoothstep(t));
            let w = (1.0 - blend).powi(2).max(0.001);
            weighted_elev_sum += ramp_elev * w;
            weight_sum += w;
        }
    }

    let best_floor_elev = if weight_sum > 0.0 {
        weighted_elev_sum / weight_sum
    } else {
        biome.base_height
    };

    let floor_micro = n_val * (biome.noise_amplitude * 0.14);
    let mut h = lerp(best_floor_elev + floor_micro, wall_elev, min_wall_blend);

    for node in &bp.nodes {
        for pil in &node.pillars {
            let pd = ((x - pil.x).powi(2) + (z - pil.z).powi(2)).sqrt();
            if pd <= pil.radius * 1.25 {
                let p_blend = 1.0 - smoothstep(((pd - pil.radius * 0.65) / (pil.radius * 0.60)).max(0.0));
                h = lerp(h, pil.height, p_blend);
            }
        }
    }

    h
}

pub fn verify_blueprint_and_grid_pathability(bp: &ZoneBlueprint, grid_res: usize) -> Result<(), String> {
    if bp.nodes.len() < 3 {
        return Err("Blueprint has fewer than 3 nodes".to_string());
    }

    let max_slope = bp.biome.max_walkable_slope_deg;
    let mut adj = vec![Vec::new(); bp.nodes.len()];
    for e in &bp.edges {
        if e.slope_deg <= max_slope + 0.01 {
            adj[e.from].push(e.to);
            adj[e.to].push(e.from);
        }
    }
    let mut visited = vec![false; bp.nodes.len()];
    let mut queue = VecDeque::new();
    visited[0] = true;
    queue.push_back(0);
    let mut reached = 0;
    while let Some(u) = queue.pop_front() {
        reached += 1;
        for &v in &adj[u] {
            if !visited[v] {
                visited[v] = true;
                queue.push_back(v);
            }
        }
    }
    if reached != bp.nodes.len() {
        return Err(format!("Macro graph disconnected: {}/{} nodes reached", reached, bp.nodes.len()));
    }

    let res = grid_res.max(64);
    let cell_w = bp.map_size_x / (res as f64);
    let cell_h = bp.map_size_z / (res as f64);
    let wall_threshold = bp.biome.base_height + 90.0;

    let mut walkable = vec![false; res * res];
    for gz in 0..res {
        for gx in 0..res {
            let wx = (gx as f64 + 0.5) * cell_w;
            let wz = (gz as f64 + 0.5) * cell_h;
            let h = sample_zone_height(bp, wx, wz);
            walkable[gz * res + gx] = h <= wall_threshold;
        }
    }

    let to_cell = |wx: f64, wz: f64| -> (usize, usize) {
        let gx = ((wx / cell_w).floor() as isize).clamp(0, (res - 1) as isize) as usize;
        let gz = ((wz / cell_h).floor() as isize).clamp(0, (res - 1) as isize) as usize;
        (gx, gz)
    };

    let (start_x, start_z) = to_cell(bp.nodes[0].x, bp.nodes[0].z);
    if !walkable[start_z * res + start_x] {
        return Err("DropZone start cell is not walkable on heightfield grid".to_string());
    }

    let mut grid_vis = vec![false; res * res];
    let mut gq = VecDeque::new();
    grid_vis[start_z * res + start_x] = true;
    gq.push_back((start_x, start_z));

    let dirs = [
        (-1isize, 0isize),
        (1, 0),
        (0, -1),
        (0, 1),
        (-1, -1),
        (1, -1),
        (-1, 1),
        (1, 1),
    ];

    while let Some((cx, cz)) = gq.pop_front() {
        for (dx, dz) in dirs {
            let nx = cx as isize + dx;
            let nz = cz as isize + dz;
            if nx >= 0 && nx < res as isize && nz >= 0 && nz < res as isize {
                let ux = nx as usize;
                let uz = nz as usize;
                let idx = uz * res + ux;
                if walkable[idx] && !grid_vis[idx] {
                    grid_vis[idx] = true;
                    gq.push_back((ux, uz));
                }
            }
        }
    }

    for node in &bp.nodes {
        let (nx, nz) = to_cell(node.x, node.z);
        if !grid_vis[nz * res + nx] {
            return Err(format!(
                "Node {} ({}) at ({:.0}, {:.0}) unreachable on 2D heightfield grid",
                node.id,
                node.kind.as_str(),
                node.x,
                node.z
            ));
        }
    }

    Ok(())
}

pub fn render_ascii_map(bp: &ZoneBlueprint, width: usize, height: usize) -> String {
    let mut out = String::new();
    let wall_cutoff = bp.biome.base_height + 90.0;

    for rz in 0..height {
        for rx in 0..width {
            let wx = (rx as f64 + 0.5) / (width as f64) * bp.map_size_x;
            let wz = (rz as f64 + 0.5) / (height as f64) * bp.map_size_z;

            let mut marker = None;
            for node in &bp.nodes {
                let d = ((wx - node.x).powi(2) + (wz - node.z).powi(2)).sqrt();
                if d <= 90.0 {
                    marker = Some(match node.kind {
                        RoomKind::DropZone => 'D',
                        RoomKind::SalvageField => 'S',
                        RoomKind::ChokePoint => 'C',
                        RoomKind::FoundryCache => 'F',
                        RoomKind::HazardGauntlet => 'H',
                        RoomKind::SetpieceVault => 'V',
                        RoomKind::BossArena => 'B',
                        RoomKind::ExtractionGate => 'E',
                    });
                    break;
                }
            }

            if let Some(ch) = marker {
                out.push(ch);
            } else {
                let h = sample_zone_height(bp, wx, wz);
                if h > wall_cutoff {
                    out.push('#');
                } else {
                    out.push('.');
                }
            }
        }
        out.push('\n');
    }
    out
}

fn append_zone_svg_elements(svg: &mut String, bp: &ZoneBlueprint) {
    let wall_cutoff = bp.biome.base_height + 90.0;
    let grid_n = 28usize;
    let cell_w = bp.map_size_x / (grid_n as f64);
    let cell_h = bp.map_size_z / (grid_n as f64);

    // Heightmap hypsometric contour cells
    for gz in 0..grid_n {
        for gx in 0..grid_n {
            let wx = (gx as f64 + 0.5) * cell_w;
            let wz = (gz as f64 + 0.5) * cell_h;
            let h = sample_zone_height(bp, wx, wz);
            let fill = if h > wall_cutoff {
                let band = ((h - wall_cutoff) / 45.0).floor() as i32;
                if band % 2 == 0 {
                    "#111722"
                } else {
                    "#161f2e"
                }
            } else {
                let band = ((h - bp.biome.base_height + 40.0) / 16.0).floor() as i32;
                if band % 2 == 0 {
                    "#162436"
                } else {
                    "#1b2d42"
                }
            };
            let _ = writeln!(
                svg,
                r##"    <rect x="{:.1}" y="{:.1}" width="{:.1}" height="{:.1}" fill="{}"/>"##,
                gx as f64 * cell_w,
                gz as f64 * cell_h,
                cell_w + 0.8,
                cell_h + 0.8,
                fill
            );
        }
    }

    // Corridor graph edges
    for edge in &bp.edges {
        let u = &bp.nodes[edge.from];
        let v = &bp.nodes[edge.to];
        let stroke = if edge.is_primary { "#2d5a7b" } else { "#1f3d58" };
        let center_stroke = if edge.is_primary { "#58a6ff" } else { "#388bfd" };
        let _ = writeln!(
            svg,
            r##"    <line x1="{:.1}" y1="{:.1}" x2="{:.1}" y2="{:.1}" stroke="{}" stroke-width="{:.1}" stroke-linecap="round"/>"##,
            u.x,
            u.z,
            v.x,
            v.z,
            stroke,
            edge.width * 1.35
        );
        let _ = writeln!(
            svg,
            r##"    <line x1="{:.1}" y1="{:.1}" x2="{:.1}" y2="{:.1}" stroke="{}" stroke-width="10" stroke-dasharray="24,18" stroke-linecap="round" opacity="0.65"/>"##,
            u.x, u.z, v.x, v.z, center_stroke
        );
    }

    // Setpiece Vault objective rings
    for sp in &bp.setpieces {
        let _ = writeln!(
            svg,
            r##"    <circle cx="{:.1}" cy="{:.1}" r="{:.1}" fill="none" stroke="#d2a8ff" stroke-width="10" stroke-dasharray="28,16"/>"##,
            sp.x, sp.z, sp.radius
        );
    }

    // Zone room boundaries and cover pillars
    for node in &bp.nodes {
        let (fill, stroke) = match node.kind {
            RoomKind::DropZone => ("#1f6f50", "#3fb950"),
            RoomKind::SalvageField => ("#4a5d23", "#a2d240"),
            RoomKind::ChokePoint => ("#5c4033", "#f0883e"),
            RoomKind::FoundryCache => ("#2e5a88", "#79c0ff"),
            RoomKind::HazardGauntlet => ("#7a2e2e", "#ff7b72"),
            RoomKind::SetpieceVault => ("#5e35b1", "#d2a8ff"),
            RoomKind::BossArena => ("#6b1d2f", "#ffa198"),
            RoomKind::ExtractionGate => ("#178577", "#56d4dd"),
        };
        let _ = writeln!(
            svg,
            r##"    <circle cx="{:.1}" cy="{:.1}" r="{:.1}" fill="{}" fill-opacity="0.88" stroke="{}" stroke-width="12"/>"##,
            node.x, node.z, node.radius, fill, stroke
        );
        for pil in &node.pillars {
            let _ = writeln!(
                svg,
                r##"    <circle cx="{:.1}" cy="{:.1}" r="{:.1}" fill="#0b0e14" stroke="#f28b82" stroke-width="8"/>"##,
                pil.x, pil.z, pil.radius
            );
        }
    }

    // Pre-seeded BAR wreckage clusters
    for w in &bp.planned_wrecks {
        let color = if w.is_overclocked_reactor {
            "#ff5252"
        } else if w.is_jackpot {
            "#fbbc04"
        } else {
            "#9aa0a6"
        };
        let r = if w.is_jackpot { 18.0 } else { 10.0 };
        let _ = writeln!(
            svg,
            r##"    <circle cx="{:.1}" cy="{:.1}" r="{:.1}" fill="{}"/>"##,
            w.x, w.z, r, color
        );
    }
}

pub fn render_svg_map(bp: &ZoneBlueprint) -> String {
    let mut svg = String::new();
    let _ = writeln!(
        svg,
        r##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {:.0} {:.0}" width="512" height="512">"##,
        bp.map_size_x, bp.map_size_z
    );
    let _ = writeln!(svg, r##"  <rect width="100%" height="100%" fill="#0d1117"/>"##);
    append_zone_svg_elements(&mut svg, bp);
    let _ = writeln!(svg, "</svg>");
    svg
}

/// Compiles a standalone, pure-SVG 8-Biome Procedural Map Atlas (zero HTML, zero web wrappers).
pub fn render_svg_map_atlas(base_seed: u64) -> String {
    let width = 1860usize;
    let height = 1020usize;
    let mut svg = String::new();
    let _ = writeln!(
        svg,
        r##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {} {}" width="{}" height="{}">"##,
        width, height, width, height
    );
    let _ = writeln!(svg, r##"  <rect width="100%" height="100%" fill="#0b0e14"/>"##);
    let _ = writeln!(
        svg,
        r##"  <text x="28" y="42" fill="#58a6ff" font-family="monospace" font-size="22" font-weight="bold">WRECKAGE PROTOCOL — 8-BIOME PROCEDURAL MAP ATLAS (SEED {})</text>"##,
        base_seed
    );
    let _ = writeln!(
        svg,
        r##"  <text x="28" y="66" fill="#8b949e" font-family="monospace" font-size="13">NATIVE VECTOR ATLAS | DROP PAD (GREEN) | SALVAGE FIELD (OLIVE) | FOUNDRY/VAULT (BLUE/PURPLE) | BOSS ARENA (CRIMSON) | EXTRACTION GATE (TEAL)</text>"##
    );

    let card_w = 436.0;
    let card_h = 446.0;
    let map_box = 368.0;

    for depth in 1..=8 {
        let col = (depth - 1) % 4;
        let row = (depth - 1) / 4;
        let cx = 24.0 + (col as f64) * (card_w + 18.0);
        let cy = 84.0 + (row as f64) * (card_h + 18.0);
        let bp = build_zone_blueprint(base_seed, depth, 4096.0, 4096.0, None);

        let _ = writeln!(
            svg,
            r##"  <rect x="{:.1}" y="{:.1}" width="{:.1}" height="{:.1}" rx="8" fill="#161b22" stroke="#30363d" stroke-width="2"/>"##,
            cx, cy, card_w, card_h
        );
        let _ = writeln!(
            svg,
            r##"  <text x="{:.1}" y="{:.1}" fill="#58a6ff" font-family="monospace" font-size="14" font-weight="bold">Z{}: {} ({})</text>"##,
            cx + 14.0,
            cy + 24.0,
            depth,
            bp.biome.kind.title(),
            bp.biome.kind.topology()
        );
        let _ = writeln!(
            svg,
            r##"  <text x="{:.1}" y="{:.1}" fill="#8b949e" font-family="monospace" font-size="11">Rooms:{} Edges:{} Wrecks:{} Vaults:{} | {}</text>"##,
            cx + 14.0,
            cy + 42.0,
            bp.nodes.len(),
            bp.edges.len(),
            bp.planned_wrecks.len(),
            bp.setpieces.len(),
            bp.biome.boss_title
        );

        let map_x = cx + (card_w - map_box) * 0.5;
        let map_y = cy + 54.0;
        let scale = map_box / bp.map_size_x;
        let _ = writeln!(
            svg,
            r##"  <g transform="translate({:.2},{:.2}) scale({:.6})">"##,
            map_x, map_y, scale
        );
        let _ = writeln!(
            svg,
            r##"    <rect x="0" y="0" width="{:.0}" height="{:.0}" fill="#0d1117" stroke="#21262d" stroke-width="16"/>"##,
            bp.map_size_x, bp.map_size_z
        );
        append_zone_svg_elements(&mut svg, &bp);
        let _ = writeln!(svg, "  </g>");
    }

    let _ = writeln!(svg, "</svg>");
    svg
}

// ============================================================================
// Pure-Rust Native PNG Map Atlas Rasterizer & RFC 1950/1951 Encoder
// ============================================================================

fn glyph_5x7(ch: char) -> [u8; 7] {
    match ch.to_ascii_uppercase() {
        'A' => [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
        'B' => [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110],
        'C' => [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110],
        'D' => [0b11100, 0b10010, 0b10001, 0b10001, 0b10001, 0b10010, 0b11100],
        'E' => [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
        'F' => [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000],
        'G' => [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01110],
        'H' => [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
        'I' => [0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
        'J' => [0b00111, 0b00010, 0b00010, 0b00010, 0b10010, 0b10010, 0b01100],
        'K' => [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001],
        'L' => [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
        'M' => [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001],
        'N' => [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001],
        'O' => [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
        'P' => [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000],
        'Q' => [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101],
        'R' => [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001],
        'S' => [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110],
        'T' => [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100],
        'U' => [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
        'V' => [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100],
        'W' => [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b10101, 0b01010],
        'X' => [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001],
        'Y' => [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100],
        'Z' => [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111],
        '0' => [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110],
        '1' => [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
        '2' => [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111],
        '3' => [0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110],
        '4' => [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010],
        '5' => [0b11111, 0b10000, 0b10000, 0b11110, 0b00001, 0b00001, 0b11110],
        '6' => [0b01110, 0b10000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110],
        '7' => [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000],
        '8' => [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110],
        '9' => [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00001, 0b01110],
        ':' => [0b00000, 0b00100, 0b00100, 0b00000, 0b00100, 0b00100, 0b00000],
        '-' => [0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000],
        '|' => [0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100],
        '#' => [0b01010, 0b11111, 0b01010, 0b01010, 0b11111, 0b01010, 0b00000],
        '(' => [0b00010, 0b00100, 0b01000, 0b01000, 0b01000, 0b00100, 0b00010],
        ')' => [0b01000, 0b00100, 0b00010, 0b00010, 0b00010, 0b00100, 0b01000],
        '/' => [0b00001, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b10000],
        '_' => [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b11111],
        '.' => [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b00100],
        _ => [0; 7],
    }
}

fn put_px(buf: &mut [u8], w: usize, h: usize, x: isize, y: isize, rgb: [u8; 3]) {
    if x >= 0 && (x as usize) < w && y >= 0 && (y as usize) < h {
        let idx = ((y as usize) * w + (x as usize)) * 3;
        buf[idx] = rgb[0];
        buf[idx + 1] = rgb[1];
        buf[idx + 2] = rgb[2];
    }
}

fn draw_text_5x7(
    buf: &mut [u8],
    w: usize,
    h: usize,
    x0: usize,
    y0: usize,
    text: &str,
    scale: usize,
    rgb: [u8; 3],
) {
    let sc = scale.max(1);
    for (ci, ch) in text.chars().enumerate() {
        let rows = glyph_5x7(ch);
        let cx = x0 + ci * 6 * sc;
        for (ry, row_bits) in rows.iter().enumerate() {
            for rx in 0..5 {
                if (row_bits >> (4 - rx)) & 1 == 1 {
                    for sy in 0..sc {
                        for sx in 0..sc {
                            put_px(
                                buf,
                                w,
                                h,
                                (cx + rx * sc + sx) as isize,
                                (y0 + ry * sc + sy) as isize,
                                rgb,
                            );
                        }
                    }
                }
            }
        }
    }
}

fn rasterize_zone_panel(
    buf: &mut [u8],
    img_w: usize,
    img_h: usize,
    px0: usize,
    py0: usize,
    panel_size: usize,
    bp: &ZoneBlueprint,
) {
    let wall_cutoff = bp.biome.base_height + 90.0;
    let inv = 1.0 / (panel_size.max(1) as f64);

    // 1. Hypsometric heightfield, walkable floor, wall cliffs, and elevation contour lines
    for py in 0..panel_size {
        let wz = (py as f64 + 0.5) * inv * bp.map_size_z;
        for px in 0..panel_size {
            let wx = (px as f64 + 0.5) * inv * bp.map_size_x;
            let h = sample_zone_height(bp, wx, wz);
            let contour = ((h / 18.0).rem_euclid(1.0)) < 0.085;
            let rgb = if h > wall_cutoff {
                let t = ((h - wall_cutoff) / 140.0).clamp(0.0, 1.0);
                if contour {
                    [34, 46, 64]
                } else {
                    [
                        (15.0 + 14.0 * t) as u8,
                        (20.0 + 16.0 * t) as u8,
                        (30.0 + 22.0 * t) as u8,
                    ]
                }
            } else {
                let t = ((h - (bp.biome.base_height - 35.0)) / 95.0).clamp(0.0, 1.0);
                if contour {
                    [46, 78, 108]
                } else {
                    [
                        (24.0 + 26.0 * t) as u8,
                        (40.0 + 38.0 * t) as u8,
                        (58.0 + 44.0 * t) as u8,
                    ]
                }
            };
            put_px(buf, img_w, img_h, (px0 + px) as isize, (py0 + py) as isize, rgb);
        }
    }

    // 2. Corridor centerline & width bands
    for edge in &bp.edges {
        let u = &bp.nodes[edge.from];
        let v = &bp.nodes[edge.to];
        let steps = (edge.length / 16.0).ceil() as usize;
        let col = if edge.is_primary {
            [72, 148, 224]
        } else {
            [52, 104, 162]
        };
        for s in 0..=steps.max(1) {
            let t = (s as f64) / (steps.max(1) as f64);
            let wx = lerp(u.x, v.x, t);
            let wz = lerp(u.z, v.z, t);
            let ix = px0 as isize + ((wx / bp.map_size_x) * (panel_size as f64)) as isize;
            let iz = py0 as isize + ((wz / bp.map_size_z) * (panel_size as f64)) as isize;
            for dz in -1..=1 {
                for dx in -1..=1 {
                    put_px(buf, img_w, img_h, ix + dx, iz + dz, col);
                }
            }
        }
    }

    // 3. Room boundary rings, setpiece vaults, and cover pillars
    for node in &bp.nodes {
        let (fill, ring_col) = match node.kind {
            RoomKind::DropZone => ([31, 111, 80], [63, 185, 80]),
            RoomKind::SalvageField => ([74, 93, 35], [162, 210, 64]),
            RoomKind::ChokePoint => ([92, 64, 51], [240, 136, 62]),
            RoomKind::FoundryCache => ([46, 90, 136], [121, 192, 255]),
            RoomKind::HazardGauntlet => ([122, 46, 46], [255, 123, 114]),
            RoomKind::SetpieceVault => ([94, 53, 177], [210, 168, 255]),
            RoomKind::BossArena => ([107, 29, 47], [255, 161, 152]),
            RoomKind::ExtractionGate => ([23, 133, 119], [86, 212, 221]),
        };
        let cx = ((node.x / bp.map_size_x) * (panel_size as f64)) as isize;
        let cz = ((node.z / bp.map_size_z) * (panel_size as f64)) as isize;
        let r_px = ((node.radius / bp.map_size_x) * (panel_size as f64)).ceil() as isize;
        for dz in -r_px..=r_px {
            for dx in -r_px..=r_px {
                let d2 = dx * dx + dz * dz;
                let r2 = r_px * r_px;
                let inner2 = (r_px - 2).max(0).pow(2);
                if d2 <= r2 {
                    let c = if d2 >= inner2 { ring_col } else { fill };
                    put_px(buf, img_w, img_h, px0 as isize + cx + dx, py0 as isize + cz + dz, c);
                }
            }
        }
        for pil in &node.pillars {
            let px_c = ((pil.x / bp.map_size_x) * (panel_size as f64)) as isize;
            let pz_c = ((pil.z / bp.map_size_z) * (panel_size as f64)) as isize;
            let pr = (((pil.radius / bp.map_size_x) * (panel_size as f64)).ceil() as isize).max(2);
            for dz in -pr..=pr {
                for dx in -pr..=pr {
                    if dx * dx + dz * dz <= pr * pr {
                        put_px(
                            buf,
                            img_w,
                            img_h,
                            px0 as isize + px_c + dx,
                            py0 as isize + pz_c + dz,
                            [242, 139, 130],
                        );
                    }
                }
            }
        }
    }

    // 4. Pre-seeded BAR wreckage clusters (standard grey, jackpot gold, reactor crimson)
    for w in &bp.planned_wrecks {
        let wx = ((w.x / bp.map_size_x) * (panel_size as f64)) as isize;
        let wz = ((w.z / bp.map_size_z) * (panel_size as f64)) as isize;
        let (col, rad) = if w.is_overclocked_reactor {
            ([255, 82, 82], 2isize)
        } else if w.is_jackpot {
            ([251, 188, 4], 2isize)
        } else {
            ([185, 194, 204], 1isize)
        };
        for dz in -rad..=rad {
            for dx in -rad..=rad {
                if dx * dx + dz * dz <= rad * rad {
                    put_px(buf, img_w, img_h, px0 as isize + wx + dx, py0 as isize + wz + dz, col);
                }
            }
        }
    }
}

fn crc32_png(chunk_type: &[u8; 4], data: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &b in chunk_type.iter().chain(data.iter()) {
        let mut c = (crc ^ (b as u32)) & 0xFF;
        for _ in 0..8 {
            c = if (c & 1) != 0 {
                0xEDB8_8320 ^ (c >> 1)
            } else {
                c >> 1
            };
        }
        crc = (crc >> 8) ^ c;
    }
    !crc
}

fn adler32_zlib(data: &[u8]) -> u32 {
    let mut s1 = 1u32;
    let mut s2 = 0u32;
    for &b in data {
        s1 = (s1 + (b as u32)) % 65_521;
        s2 = (s2 + s1) % 65_521;
    }
    (s2 << 16) | s1
}

struct BitWriter {
    bytes: Vec<u8>,
    cur: u8,
    bit_pos: u8,
}

impl BitWriter {
    fn new(cap: usize) -> Self {
        Self {
            bytes: Vec::with_capacity(cap),
            cur: 0,
            bit_pos: 0,
        }
    }

    fn write_lsb(&mut self, val: u32, nbits: u8) {
        for i in 0..nbits {
            if ((val >> i) & 1) != 0 {
                self.cur |= 1 << self.bit_pos;
            }
            self.bit_pos += 1;
            if self.bit_pos == 8 {
                self.bytes.push(self.cur);
                self.cur = 0;
                self.bit_pos = 0;
            }
        }
    }

    fn write_msb(&mut self, code: u32, nbits: u8) {
        for i in (0..nbits).rev() {
            if ((code >> i) & 1) != 0 {
                self.cur |= 1 << self.bit_pos;
            }
            self.bit_pos += 1;
            if self.bit_pos == 8 {
                self.bytes.push(self.cur);
                self.cur = 0;
                self.bit_pos = 0;
            }
        }
    }

    fn write_fixed_lit_or_len(&mut self, sym: usize) {
        if sym <= 143 {
            self.write_msb(0x30 + (sym as u32), 8);
        } else if sym <= 255 {
            self.write_msb(0x190 + ((sym - 144) as u32), 9);
        } else if sym <= 279 {
            self.write_msb((sym - 256) as u32, 7);
        } else {
            self.write_msb(0xC0 + ((sym - 280) as u32), 8);
        }
    }

    fn finish(mut self) -> Vec<u8> {
        if self.bit_pos > 0 {
            self.bytes.push(self.cur);
        }
        self.bytes
    }
}

fn encode_length_code(len: usize) -> (usize, u8, u32) {
    const BASES: [usize; 29] = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
        131, 163, 195, 227, 258,
    ];
    const EXTRAS: [u8; 29] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
    ];
    if len >= 258 {
        return (285, 0, 0);
    }
    let mut idx = 0;
    for i in 0..28 {
        if len >= BASES[i] && len < BASES[i + 1] {
            idx = i;
            break;
        }
    }
    (257 + idx, EXTRAS[idx], (len - BASES[idx]) as u32)
}

fn encode_distance_code(dist: usize) -> (u32, u8, u32) {
    const BASES: [usize; 30] = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
        2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
    ];
    const EXTRAS: [u8; 30] = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12,
        13, 13,
    ];
    let mut idx = 29;
    for i in 0..29 {
        if dist >= BASES[i] && dist < BASES[i + 1] {
            idx = i;
            break;
        }
    }
    (idx as u32, EXTRAS[idx], (dist - BASES[idx]) as u32)
}

fn zlib_compress_fixed_huffman(raw: &[u8]) -> Vec<u8> {
    let mut bw = BitWriter::new(raw.len() / 2 + 64);
    // RFC 1950 Zlib header: CMF = 0x78, FLG = 0x9C
    bw.bytes.push(0x78);
    bw.bytes.push(0x9C);
    // RFC 1951 single final block with fixed Huffman codes: BFINAL=1, BTYPE=01
    bw.write_lsb(1, 1);
    bw.write_lsb(0b01, 2);

    let mut head = vec![usize::MAX; 4096];
    let mut prev = vec![usize::MAX; raw.len()];
    let hash3 = |p: usize| -> usize {
        (((raw[p] as usize) << 8) ^ ((raw[p + 1] as usize) << 4) ^ (raw[p + 2] as usize)) & 4095
    };

    let mut pos = 0;
    while pos < raw.len() {
        let mut best_len = 0usize;
        let mut best_dist = 0usize;
        if pos + 3 <= raw.len() {
            let h = hash3(pos);
            let mut cand = head[h];
            prev[pos] = cand;
            head[h] = pos;
            let mut chain = 0;
            let max_len = (raw.len() - pos).min(258);
            while cand != usize::MAX && pos - cand <= 32_768 && chain < 24 {
                if raw[cand + best_len] == raw[pos + best_len] {
                    let mut l = 0;
                    while l < max_len && raw[cand + l] == raw[pos + l] {
                        l += 1;
                    }
                    if l >= 3 && l > best_len {
                        best_len = l;
                        best_dist = pos - cand;
                        if l == max_len {
                            break;
                        }
                    }
                }
                cand = prev[cand];
                chain += 1;
            }
        }
        if best_len >= 3 {
            let (lsym, lextra, lval) = encode_length_code(best_len);
            bw.write_fixed_lit_or_len(lsym);
            if lextra > 0 {
                bw.write_lsb(lval, lextra);
            }
            let (dsym, dextra, dval) = encode_distance_code(best_dist);
            bw.write_msb(dsym, 5);
            if dextra > 0 {
                bw.write_lsb(dval, dextra);
            }
            for step in 1..best_len {
                if pos + step + 3 <= raw.len() {
                    let h = hash3(pos + step);
                    prev[pos + step] = head[h];
                    head[h] = pos + step;
                }
            }
            pos += best_len;
        } else {
            bw.write_fixed_lit_or_len(raw[pos] as usize);
            pos += 1;
        }
    }

    // End of block (symbol 256)
    bw.write_fixed_lit_or_len(256);
    let mut out = bw.finish();
    out.extend_from_slice(&adler32_zlib(raw).to_be_bytes());
    out
}

fn write_png_chunk(out: &mut Vec<u8>, chunk_type: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    out.extend_from_slice(chunk_type);
    out.extend_from_slice(data);
    out.extend_from_slice(&crc32_png(chunk_type, data).to_be_bytes());
}

pub fn encode_png_rgb(width: usize, height: usize, rgb: &[u8]) -> Vec<u8> {
    assert_eq!(rgb.len(), width * height * 3);
    let row_bytes = width * 3;
    let mut raw_scanlines = Vec::with_capacity((row_bytes + 1) * height);
    for y in 0..height {
        raw_scanlines.push(0u8); // Filter type 0 (None)
        let start = y * row_bytes;
        raw_scanlines.extend_from_slice(&rgb[start..start + row_bytes]);
    }
    let idat_payload = zlib_compress_fixed_huffman(&raw_scanlines);

    let mut png = Vec::with_capacity(idat_payload.len() + 64);
    png.extend_from_slice(&[137, 80, 78, 71, 13, 10, 26, 10]);

    let mut ihdr = [0u8; 13];
    ihdr[0..4].copy_from_slice(&(width as u32).to_be_bytes());
    ihdr[4..8].copy_from_slice(&(height as u32).to_be_bytes());
    ihdr[8] = 8; // 8 bits per channel
    ihdr[9] = 2; // Truecolor RGB
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    write_png_chunk(&mut png, b"IHDR", &ihdr);
    write_png_chunk(&mut png, b"IDAT", &idat_payload);
    write_png_chunk(&mut png, b"IEND", &[]);
    png
}

/// Renders a single zone blueprint into a standalone Truecolor RGB `.png` image.
pub fn render_png_zone_map(bp: &ZoneBlueprint, size: usize) -> Vec<u8> {
    let dim = size.max(128);
    let mut rgb = vec![11u8; dim * dim * 3];
    rasterize_zone_panel(&mut rgb, dim, dim, 0, 0, dim, bp);
    encode_png_rgb(dim, dim, &rgb)
}

/// Compiles a native Truecolor RGB `.png` 8-Biome Procedural Map Atlas (`1240 x 680`).
pub fn render_png_map_atlas(base_seed: u64) -> Vec<u8> {
    let width = 1240usize;
    let height = 680usize;
    let mut rgb = vec![0u8; width * height * 3];
    for px in rgb.chunks_exact_mut(3) {
        px[0] = 11;
        px[1] = 14;
        px[2] = 20;
    }

    let header = format!(
        "WRECKAGE PROTOCOL - 8-BIOME PROCEDURAL MAP ATLAS (SEED {})",
        base_seed
    );
    draw_text_5x7(&mut rgb, width, height, 20, 12, &header, 2, [88, 166, 255]);
    draw_text_5x7(
        &mut rgb,
        width,
        height,
        20,
        32,
        "DROP PAD (GREEN) | SALVAGE (OLIVE) | FOUNDRY/VAULT (BLUE/PURPLE) | BOSS (RED) | EXTRACT (TEAL)",
        1,
        [139, 148, 158],
    );

    let panel_size = 264usize;
    let card_w = 292usize;
    let card_h = 304usize;

    for depth in 1..=8 {
        let col = (depth - 1) % 4;
        let row = (depth - 1) / 4;
        let cx = 18 + col * (card_w + 12);
        let cy = 48 + row * (card_h + 12);
        let bp = build_zone_blueprint(base_seed, depth, 4096.0, 4096.0, None);

        // Card border and background
        for y in cy..(cy + card_h) {
            for x in cx..(cx + card_w) {
                let border = x == cx || x + 1 == cx + card_w || y == cy || y + 1 == cy + card_h;
                let c = if border { [48, 54, 61] } else { [22, 27, 34] };
                put_px(&mut rgb, width, height, x as isize, y as isize, c);
            }
        }

        let title = format!("Z{}: {}", depth, bp.biome.kind.id());
        draw_text_5x7(&mut rgb, width, height, cx + 10, cy + 8, &title, 1, [88, 166, 255]);
        let stats = format!(
            "R:{} E:{} W:{} V:{}",
            bp.nodes.len(),
            bp.edges.len(),
            bp.planned_wrecks.len(),
            bp.setpieces.len()
        );
        draw_text_5x7(&mut rgb, width, height, cx + 10, cy + 20, &stats, 1, [139, 148, 158]);

        rasterize_zone_panel(&mut rgb, width, height, cx + 14, cy + 32, panel_size, &bp);
    }

    encode_png_rgb(width, height, &rgb)
}

fn append_lua_blueprint_table(lua: &mut String, bp: &ZoneBlueprint, indent: &str) {
    let wall_cutoff = bp.biome.base_height + 90.0;
    let mut min_elev = f64::MAX;
    let mut max_elev = f64::MIN;
    let mut walkable_samples = 0usize;
    let grid_n = 32usize;
    for gz in 0..grid_n {
        for gx in 0..grid_n {
            let wx = (gx as f64 + 0.5) / (grid_n as f64) * bp.map_size_x;
            let wz = (gz as f64 + 0.5) / (grid_n as f64) * bp.map_size_z;
            let h = sample_zone_height(bp, wx, wz);
            min_elev = min_elev.min(h);
            max_elev = max_elev.max(h);
            if h <= wall_cutoff {
                walkable_samples += 1;
            }
        }
    }
    let walkable_frac = (walkable_samples as f64) / ((grid_n * grid_n) as f64);

    let _ = writeln!(lua, "{}{{", indent);
    let _ = writeln!(lua, "{}  seed = {},", indent, bp.seed);
    let _ = writeln!(lua, "{}  zoneDepth = {},", indent, bp.zone_depth);
    let _ = writeln!(lua, "{}  biomeId = {:?},", indent, bp.biome.kind.id());
    let _ = writeln!(lua, "{}  biomeTitle = {:?},", indent, bp.biome.kind.title());
    let _ = writeln!(lua, "{}  topology = {:?},", indent, bp.biome.kind.topology());
    let _ = writeln!(lua, "{}  bossUnit = {:?},", indent, bp.biome.boss_unit);
    let _ = writeln!(lua, "{}  bossTitle = {:?},", indent, bp.biome.boss_title);
    let _ = writeln!(lua, "{}  mapSizeX = {:.0},", indent, bp.map_size_x);
    let _ = writeln!(lua, "{}  mapSizeZ = {:.0},", indent, bp.map_size_z);
    let _ = writeln!(lua, "{}  nodeCount = {},", indent, bp.nodes.len());
    let _ = writeln!(lua, "{}  wreckCount = {},", indent, bp.planned_wrecks.len());
    let _ = writeln!(lua, "{}  setpieceCount = {},", indent, bp.setpieces.len());
    let _ = writeln!(
        lua,
        "{}  heightContourSummary = {{ minElev = {:.1}, maxElev = {:.1}, wallCutoff = {:.1}, walkableFraction = {:.3} }},",
        indent, min_elev, max_elev, wall_cutoff, walkable_frac
    );
    let _ = writeln!(lua, "{}  nodes = {{", indent);
    for n in &bp.nodes {
        let _ = writeln!(
            lua,
            "{}    {{ id = {}, kind = {:?}, x = {:.1}, z = {:.1}, radius = {:.1}, elevation = {:.1}, hasGarage = {}, pillarCount = {} }},",
            indent,
            n.id + 1,
            n.kind.as_str(),
            n.x,
            n.z,
            n.radius,
            n.elevation,
            n.has_garage,
            n.pillars.len()
        );
    }
    let _ = writeln!(lua, "{}  }},", indent);
    let _ = writeln!(lua, "{}  edges = {{", indent);
    for e in &bp.edges {
        let _ = writeln!(
            lua,
            "{}    {{ from = {}, to = {}, width = {:.1}, length = {:.1}, slopeDeg = {:.2}, isPrimary = {} }},",
            indent,
            e.from + 1,
            e.to + 1,
            e.width,
            e.length,
            e.slope_deg,
            e.is_primary
        );
    }
    let _ = writeln!(lua, "{}  }},", indent);
    let _ = writeln!(lua, "{}  setpieces = {{", indent);
    for sp in &bp.setpieces {
        let _ = writeln!(
            lua,
            "{}    {{ id = {}, nodeId = {}, kind = {:?}, x = {:.1}, z = {:.1}, radius = {:.1} }},",
            indent,
            sp.id,
            sp.node_id + 1,
            sp.kind,
            sp.x,
            sp.z,
            sp.radius
        );
    }
    let _ = writeln!(lua, "{}  }},", indent);
    let _ = writeln!(lua, "{}  plannedWrecks = {{", indent);
    for w in &bp.planned_wrecks {
        let _ = writeln!(
            lua,
            "{}    {{ nodeId = {}, featureName = {:?}, x = {:.1}, z = {:.1}, isJackpot = {}, isOverclockedReactor = {}, metal = {}, energy = {} }},",
            indent,
            w.node_id + 1,
            w.feature_name,
            w.x,
            w.z,
            w.is_jackpot,
            w.is_overclocked_reactor,
            w.metal,
            w.energy
        );
    }
    let _ = writeln!(lua, "{}  }},", indent);
    let _ = writeln!(lua, "{}}}", indent);
}

pub fn export_lua_blueprint(bp: &ZoneBlueprint) -> String {
    let mut lua = String::new();
    let _ = writeln!(lua, "-- Generated by arpg-mapgen (Rust)");
    lua.push_str("return ");
    append_lua_blueprint_table(&mut lua, bp, "");
    let _ = writeln!(lua);
    lua
}

/// Compiles a deterministic Recoil/BAR Lua 8-Biome Map Atlas Blueprint dump (`luarules/configs/arpg_map_atlas_blueprints.lua`).
pub fn export_lua_map_atlas(base_seed: u64) -> String {
    let mut lua = String::new();
    let _ = writeln!(
        lua,
        "-- luarules/configs/arpg_map_atlas_blueprints.lua"
    );
    let _ = writeln!(
        lua,
        "-- Deterministic 8-Biome Procedural Map Atlas Blueprints generated by tools/arpg-mapgen (Rust)."
    );
    let _ = writeln!(
        lua,
        "-- Native Recoil/BAR Lua + PNG/SVG map atlas output (zero HTML/web artifacts)."
    );
    let _ = writeln!(lua, "return {{");
    let _ = writeln!(lua, "  seed = {},", base_seed);
    let _ = writeln!(lua, "  generator = \"arpg-mapgen\",");
    let _ = writeln!(lua, "  atlasPng = \"bitmaps/arpg_icons/arpg_map_atlas.png\",");
    let _ = writeln!(lua, "  atlasSvg = \"out/arpg_map_atlas.svg\",");
    let _ = writeln!(lua, "  zones = {{");
    for depth in 1..=8 {
        let bp = build_zone_blueprint(base_seed, depth, 4096.0, 4096.0, None);
        let _ = write!(lua, "    [{}] = ", depth);
        let mut zone_block = String::new();
        append_lua_blueprint_table(&mut zone_block, &bp, "    ");
        lua.push_str(zone_block.trim_start());
        let _ = writeln!(lua, ",");
    }
    let _ = writeln!(lua, "  }},");
    let _ = writeln!(lua, "}}");
    lua
}

/// Generates a valid Spring / Recoil engine `_script.txt` launch configuration for solo or 1-4P Co-Op testing.
pub fn generate_spring_launch_script(
    seed: u64,
    biome_id: &str,
    chassis_id: &str,
    modifier_id: &str,
    coop_players: usize,
) -> String {
    let coop = coop_players.clamp(1, 4);
    let mut script = String::new();
    let _ = writeln!(script, "[GAME]");
    let _ = writeln!(script, "{{");
    let _ = writeln!(script, "\tMapName=Quicksilver Remake 1.24;");
    let _ = writeln!(script, "\tGameType=Beyond All Reason - Wreckage Protocol ARPG 1.0;");
    let _ = writeln!(script, "\tStartPosType=2;");
    let _ = writeln!(script, "\tHostIP=127.0.0.1;");
    let _ = writeln!(script, "\tHostPort=8452;");
    let _ = writeln!(script, "\tMyPlayerName=Operator;");
    let _ = writeln!(script, "\tIsHost=1;");
    let _ = writeln!(script);
    let _ = writeln!(script, "\t[MODOPTIONS]");
    let _ = writeln!(script, "\t{{");
    let _ = writeln!(script, "\t\tarpg_seed={};", seed);
    let _ = writeln!(script, "\t\tarpg_starting_biome={};", biome_id);
    let _ = writeln!(script, "\t\tarpg_starting_chassis={};", chassis_id);
    let _ = writeln!(script, "\t\tarpg_zone_modifier={};", modifier_id);
    let _ = writeln!(script, "\t\tarpg_coop_players={};", coop);
    let _ = writeln!(script, "\t}}");
    let _ = writeln!(script);

    for p in 0..coop {
        let _ = writeln!(script, "\t[PLAYER{}]", p);
        let _ = writeln!(script, "\t{{");
        let _ = writeln!(script, "\t\tName=Operator_{};", p + 1);
        let _ = writeln!(script, "\t\tTeam={};", p);
        let _ = writeln!(script, "\t\tSpectator=0;");
        let _ = writeln!(script, "\t}}");
        let _ = writeln!(script, "\t[TEAM{}]", p);
        let _ = writeln!(script, "\t{{");
        let _ = writeln!(script, "\t\tTeamLeader={};", p);
        let _ = writeln!(script, "\t\tAllyTeam=0;");
        let _ = writeln!(script, "\t\tSide=Armada;");
        let _ = writeln!(script, "\t}}");
    }

    let _ = writeln!(script, "\t[AI0]");
    let _ = writeln!(script, "\t{{");
    let _ = writeln!(script, "\t\tName=WreckageDirector;");
    let _ = writeln!(script, "\t\tShortName=NullAI;");
    let _ = writeln!(script, "\t\tTeam={};", coop);
    let _ = writeln!(script, "\t\tHost=0;");
    let _ = writeln!(script, "\t}}");
    let _ = writeln!(script, "\t[TEAM{}]", coop);
    let _ = writeln!(script, "\t{{");
    let _ = writeln!(script, "\t\tTeamLeader=0;");
    let _ = writeln!(script, "\t\tAllyTeam=1;");
    let _ = writeln!(script, "\t\tSide=Cortex;");
    let _ = writeln!(script, "\t}}");
    let _ = writeln!(script, "\t[ALLYTEAM0]");
    let _ = writeln!(script, "\t{{");
    let _ = writeln!(script, "\t\tNumAllies=0;");
    let _ = writeln!(script, "\t}}");
    let _ = writeln!(script, "\t[ALLYTEAM1]");
    let _ = writeln!(script, "\t{{");
    let _ = writeln!(script, "\t\tNumAllies=0;");
    let _ = writeln!(script, "\t}}");
    let _ = writeln!(script, "}}");
    script
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::process::Command;

    #[test]
    fn test_520_seeds_macro_and_grid_connectivity_across_all_8_biomes() {
        for i in 1..=520 {
            let seed = i * 104_729;
            let depth = ((i as usize - 1) % 8) + 1;
            let bp = build_zone_blueprint(seed, depth, 4096.0, 4096.0, None);
            verify_blueprint_and_grid_pathability(&bp, 80).unwrap_or_else(|err| {
                panic!(
                    "Seed {} (depth {}, biome {}) failed verification: {}",
                    seed,
                    depth,
                    bp.biome.kind.id(),
                    err
                )
            });
            assert!(bp.nodes.len() >= 8);
            assert!(bp.planned_wrecks.len() >= 25);
            assert!(!bp.setpieces.is_empty());
            assert_eq!(bp.nodes.first().unwrap().kind, RoomKind::DropZone);
            assert_eq!(bp.nodes[bp.nodes.len() - 2].kind, RoomKind::BossArena);
            assert_eq!(bp.nodes.last().unwrap().kind, RoomKind::ExtractionGate);
        }
    }

    #[test]
    fn test_deterministic_native_svg_png_and_lua_atlas_export() {
        let bp1 = build_zone_blueprint(424_242, 3, 4096.0, 4096.0, None);
        let bp2 = build_zone_blueprint(424_242, 3, 4096.0, 4096.0, None);
        assert_eq!(render_svg_map(&bp1), render_svg_map(&bp2));
        assert_eq!(export_lua_blueprint(&bp1), export_lua_blueprint(&bp2));

        let svg_atlas = render_svg_map_atlas(424_242);
        assert!(svg_atlas.starts_with("<svg xmlns=\"http://www.w3.org/2000/svg\""));
        assert!(!svg_atlas.contains("<!DOCTYPE html"));
        assert!(!svg_atlas.contains("<html"));
        assert!(svg_atlas.contains("WRECKAGE PROTOCOL — 8-BIOME PROCEDURAL MAP ATLAS"));
        assert!(svg_atlas.contains("Molten Slag Smelting Refinery"));
        assert!(svg_atlas.contains("Sub-Zero Cryo-Computation Vault"));

        let png_atlas = render_png_map_atlas(424_242);
        assert_eq!(&png_atlas[0..8], &[137, 80, 78, 71, 13, 10, 26, 10]);
        assert!(png_atlas.len() > 25_000, "PNG atlas should exceed 25 KB byte floor");
        assert_eq!(png_atlas, render_png_map_atlas(424_242));

        let lua_atlas = export_lua_map_atlas(424_242);
        assert!(lua_atlas.contains("atlasPng = \"bitmaps/arpg_icons/arpg_map_atlas.png\""));
        assert!(lua_atlas.contains("biomeId = \"salvage_yard\""));
        assert!(lua_atlas.contains("biomeId = \"experimental_gantry_citadel\""));
        assert!(lua_atlas.contains("heightContourSummary"));
        assert!(lua_atlas.contains("plannedWrecks"));

        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let repo_root = manifest_dir
            .parent()
            .and_then(|p| p.parent())
            .expect("repo root");
        let out_png = std::fs::read(repo_root.join("out").join("arpg_map_atlas.png"))
            .expect("out/arpg_map_atlas.png exists");
        let vfs_png = std::fs::read(
            repo_root
                .join("bitmaps")
                .join("arpg_icons")
                .join("arpg_map_atlas.png"),
        )
        .expect("bitmaps/arpg_icons/arpg_map_atlas.png exists");
        let out_svg = std::fs::read_to_string(repo_root.join("out").join("arpg_map_atlas.svg"))
            .expect("out/arpg_map_atlas.svg exists");
        let lua_file = std::fs::read_to_string(
            repo_root
                .join("luarules")
                .join("configs")
                .join("arpg_map_atlas_blueprints.lua"),
        )
        .expect("luarules/configs/arpg_map_atlas_blueprints.lua exists");

        assert_eq!(&out_png[0..8], &[137, 80, 78, 71, 13, 10, 26, 10]);
        assert_eq!(out_png, vfs_png);
        assert!(out_png.len() > 50_000);
        assert!(out_svg.starts_with("<svg ") && !out_svg.contains("<html"));
        assert!(out_svg.len() > 100_000);
        assert!(lua_file.len() > 50_000 && !lua_file.contains("<html"));
        assert!(!repo_root.join("out").join("arpg_map_atlas.html").exists());
    }

    #[test]
    fn test_bar_lua_integration_suite_via_luatex() {
        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let repo_root = manifest_dir
            .parent()
            .and_then(|p| p.parent())
            .expect("repo root");
        let output = Command::new("luatex")
            .arg("--luaonly")
            .arg("luarules/gadgets/arpg_integration_test.lua")
            .current_dir(repo_root)
            .output()
            .expect("failed to execute luatex --luaonly");

        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(
            output.status.success(),
            "Lua integration test failed:\nSTDOUT:\n{}\nSTDERR:\n{}",
            stdout,
            stderr
        );
        assert!(stdout.contains("ALL BAR SCI-FI ARPG INTEGRATION TESTS PASSED (EXIT 0)"));
    }
}
