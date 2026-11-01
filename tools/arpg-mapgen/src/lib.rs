//! Deterministic Procedural Map Generator, Heightfield Synthesizer, and Grid Pathability
//! Verifier for Beyond All Reason — Wreckage Protocol (Sci-Fi ARPG).

use std::collections::VecDeque;
use std::fmt::Write as _;

/// Deterministic Park-Miller LCG matching `luarules/gadgets/arpg_procgen_map.lua`.
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
    AutomatedWarFoundry,
    ExperimentalGantryCitadel,
}

impl BiomeKind {
    pub fn from_depth(depth: usize) -> Self {
        match (depth.saturating_sub(1)) % 4 {
            0 => Self::SalvageYard,
            1 => Self::DerelictFactory,
            2 => Self::AutomatedWarFoundry,
            _ => Self::ExperimentalGantryCitadel,
        }
    }

    pub fn id(&self) -> &'static str {
        match self {
            Self::SalvageYard => "salvage_yard",
            Self::DerelictFactory => "derelict_factory",
            Self::AutomatedWarFoundry => "automated_war_foundry",
            Self::ExperimentalGantryCitadel => "experimental_gantry_citadel",
        }
    }

    pub fn title(&self) -> &'static str {
        match self {
            Self::SalvageYard => "Rust-Belt Salvage Yard",
            Self::DerelictFactory => "Derelict Assembly Megastructure",
            Self::AutomatedWarFoundry => "Automated War-Foundry Caldera",
            Self::ExperimentalGantryCitadel => "Experimental Gantry Citadel",
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
                room_min: 7,
                room_max: 9,
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
                room_min: 8,
                room_max: 11,
                wreck_density: 1.50,
                boss_unit: "armraz",
                boss_title: "AUTOMATED SIEGE WARDEN RAZORBACK",
                wreck_pool: &["armzeus_dead", "armfido_dead", "cormort_dead", "corpyro_dead", "armbull_dead"],
                jackpot_pool: &["armmav_dead", "armsnipe_dead", "corsumo_dead"],
            },
            Self::AutomatedWarFoundry => BiomeSpec {
                kind: *self,
                tier: 3,
                base_height: 165.0,
                wall_height: 410.0,
                noise_amplitude: 36.0,
                noise_frequency: 0.0028,
                domain_warp_strength: 60.0,
                max_walkable_slope_deg: 21.0,
                room_min: 9,
                room_max: 12,
                wreck_density: 1.65,
                boss_unit: "armthor",
                boss_title: "FOUNDRY OVERSEER THOR-PRIME",
                wreck_pool: &["armmav_dead", "armsnipe_dead", "corsumo_dead", "corgol_dead", "armfus_dead"],
                jackpot_pool: &["armbanth_dead", "armraz_dead", "corkarg_dead"],
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
                room_min: 10,
                room_max: 14,
                wreck_density: 1.85,
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
    pub metal: u32,
    pub energy: u32,
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

    let room_count = rng.range_usize(biome.room_min, biome.room_max);
    let margin = map_size_x.min(map_size_z) * 0.12;

    let mut nodes = Vec::with_capacity(room_count);
    let mut edges = Vec::new();

    // Node 0 (1-indexed in Lua): Drop Zone & Mobile Garage
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
    ];

    for i in 1..=middle_count {
        let progress = (i as f64) / ((middle_count + 2) as f64);
        let kind = room_cycle[(i - 1) % room_cycle.len()];
        let base_x = margin + progress * (map_size_x - 2.0 * margin);
        let base_z = margin + progress * (map_size_z - 2.0 * margin);

        let ortho_sign = if (i + 1) % 2 == 0 { 1.0 } else { -1.0 };
        let ortho_mag = rng.range_f64(0.12, 0.28) * map_size_x.min(map_size_z);
        let nx = (base_x + ortho_sign * ortho_mag).clamp(margin, map_size_x - margin);
        let nz = (base_z - ortho_sign * ortho_mag).clamp(margin, map_size_z - margin);

        let radius = match kind {
            RoomKind::SalvageField => rng.range_f64(280.0, 340.0),
            RoomKind::ChokePoint => rng.range_f64(190.0, 230.0),
            RoomKind::FoundryCache => rng.range_f64(240.0, 290.0),
            RoomKind::HazardGauntlet => rng.range_f64(250.0, 310.0),
            _ => 250.0,
        };

        let prev_elev = nodes[i - 1].elevation;
        let elev_delta = rng.range_f64(-16.0, 20.0);
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
            has_garage: kind == RoomKind::FoundryCache,
            pillars,
        });
    }

    // Boss Arena Node
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

    // Extraction Gate Node
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

    // Primary Backbone Spine
    for i in 0..(room_count - 1) {
        let u = &nodes[i];
        let v = &nodes[i + 1];
        let dist = ((v.x - u.x).powi(2) + (v.z - u.z).powi(2)).sqrt();
        let elev_diff = (v.elevation - u.elevation).abs();
        let slope_deg = elev_diff.atan2(dist.max(120.0)).to_degrees();
        edges.push(CorridorEdge {
            from: i,
            to: i + 1,
            width: if v.kind == RoomKind::BossArena { 165.0 } else { 135.0 },
            length: dist,
            slope_deg,
            is_primary: true,
        });
    }

    // Secondary Flanking Loops
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

    // Populate Planned Wreck Fields
    let mut planned_wrecks = Vec::new();
    for node in &nodes {
        if matches!(
            node.kind,
            RoomKind::SalvageField | RoomKind::FoundryCache | RoomKind::ChokePoint
        ) {
            let base_wrecks = match node.kind {
                RoomKind::SalvageField => 18,
                RoomKind::FoundryCache => 14,
                _ => 8,
            };
            let count = ((base_wrecks as f64) * biome.wreck_density).floor() as usize;
            for w in 0..count {
                let angle = rng.range_f64(0.0, std::f64::consts::PI * 2.0);
                let r = rng.range_f64(35.0, node.radius * 0.82);
                let is_jackpot = (node.kind == RoomKind::FoundryCache && w < 3) || (w == 0 && rng.next_f64() < 0.45);
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
                    metal: if is_jackpot { 450 * biome.tier } else { 150 * biome.tier },
                    energy: if is_jackpot { 300 * biome.tier } else { 90 * biome.tier },
                });
            }
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

/// Verifies both Macro Graph connectivity AND 2D Heightfield Grid Pathability across all rooms.
pub fn verify_blueprint_and_grid_pathability(bp: &ZoneBlueprint, grid_res: usize) -> Result<(), String> {
    if bp.nodes.len() < 3 {
        return Err("Blueprint has fewer than 3 nodes".to_string());
    }

    // 1. Macro Graph Slope-Constrained BFS
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

    // 2. 2D Heightfield Grid Pathability Verification
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

/// Renders an ASCII top-down tactical overview of the synthesized heightfield & rooms.
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

/// Renders a clean SVG preview of the procedural zone layout, corridors, cover pillars, and wreck fields.
pub fn render_svg_map(bp: &ZoneBlueprint) -> String {
    let mut svg = String::new();
    let _ = writeln!(
        svg,
        r##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {:.0} {:.0}" width="768" height="768">"##,
        bp.map_size_x, bp.map_size_z
    );
    let _ = writeln!(svg, r##"  <rect width="100%" height="100%" fill="#11161d"/>"##);

    for edge in &bp.edges {
        let u = &bp.nodes[edge.from];
        let v = &bp.nodes[edge.to];
        let stroke = if edge.is_primary { "#2d4a63" } else { "#1f3347" };
        let _ = writeln!(
            svg,
            r##"  <line x1="{:.1}" y1="{:.1}" x2="{:.1}" y2="{:.1}" stroke="{}" stroke-width="{:.1}" stroke-linecap="round"/>"##,
            u.x,
            u.z,
            v.x,
            v.z,
            stroke,
            edge.width * 1.4
        );
    }

    for node in &bp.nodes {
        let fill = match node.kind {
            RoomKind::DropZone => "#1f6f50",
            RoomKind::SalvageField => "#4a5d23",
            RoomKind::ChokePoint => "#5c4033",
            RoomKind::FoundryCache => "#2e5a88",
            RoomKind::HazardGauntlet => "#7a2e2e",
            RoomKind::BossArena => "#6b1d2f",
            RoomKind::ExtractionGate => "#178577",
        };
        let _ = writeln!(
            svg,
            r##"  <circle cx="{:.1}" cy="{:.1}" r="{:.1}" fill="{}" stroke="#8ab4f8" stroke-width="6"/>"##,
            node.x, node.z, node.radius, fill
        );
        for pil in &node.pillars {
            let _ = writeln!(
                svg,
                r##"  <circle cx="{:.1}" cy="{:.1}" r="{:.1}" fill="#0b0e14" stroke="#f28b82" stroke-width="4"/>"##,
                pil.x, pil.z, pil.radius
            );
        }
    }

    for w in &bp.planned_wrecks {
        let color = if w.is_jackpot { "#fbbc04" } else { "#9aa0a6" };
        let r = if w.is_jackpot { 16.0 } else { 9.0 };
        let _ = writeln!(
            svg,
            r##"  <circle cx="{:.1}" cy="{:.1}" r="{:.1}" fill="{}"/>"##,
            w.x, w.z, r, color
        );
    }

    let _ = writeln!(svg, "</svg>");
    svg
}

/// Exports a BAR Lua table representation of the blueprint.
pub fn export_lua_blueprint(bp: &ZoneBlueprint) -> String {
    let mut lua = String::new();
    let _ = writeln!(lua, "-- Generated by arpg-mapgen (Rust)");
    let _ = writeln!(lua, "return {{");
    let _ = writeln!(lua, "  seed = {},", bp.seed);
    let _ = writeln!(lua, "  zoneDepth = {},", bp.zone_depth);
    let _ = writeln!(lua, "  biomeId = {:?},", bp.biome.kind.id());
    let _ = writeln!(lua, "  nodeCount = {},", bp.nodes.len());
    let _ = writeln!(lua, "  wreckCount = {},", bp.planned_wrecks.len());
    let _ = writeln!(lua, "}}");
    lua
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::process::Command;

    #[test]
    fn test_120_seeds_macro_and_grid_connectivity_across_all_biomes() {
        for i in 1..=120 {
            let seed = i * 104_729;
            let depth = ((i as usize - 1) % 4) + 1;
            let bp = build_zone_blueprint(seed, depth, 4096.0, 4096.0, None);
            verify_blueprint_and_grid_pathability(&bp, 96).unwrap_or_else(|err| {
                panic!(
                    "Seed {} (depth {}, biome {}) failed verification: {}",
                    seed,
                    depth,
                    bp.biome.kind.id(),
                    err
                )
            });
            assert!(bp.nodes.len() >= 7);
            assert!(bp.planned_wrecks.len() >= 25);
            assert_eq!(bp.nodes.first().unwrap().kind, RoomKind::DropZone);
            assert_eq!(bp.nodes[bp.nodes.len() - 2].kind, RoomKind::BossArena);
            assert_eq!(bp.nodes.last().unwrap().kind, RoomKind::ExtractionGate);
        }
    }

    #[test]
    fn test_deterministic_svg_and_lua_export() {
        let bp1 = build_zone_blueprint(424_242, 3, 4096.0, 4096.0, None);
        let bp2 = build_zone_blueprint(424_242, 3, 4096.0, 4096.0, None);
        assert_eq!(render_svg_map(&bp1), render_svg_map(&bp2));
        assert_eq!(export_lua_blueprint(&bp1), export_lua_blueprint(&bp2));
        let ascii = render_ascii_map(&bp1, 48, 24);
        assert!(ascii.contains('D'));
        assert!(ascii.contains('B'));
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
