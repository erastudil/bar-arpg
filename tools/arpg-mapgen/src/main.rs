use arpg_mapgen::{
    build_zone_blueprint, export_lua_blueprint, render_ascii_map, render_svg_map,
    verify_blueprint_and_grid_pathability,
};
use std::env;
use std::fs;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();
    let cmd = args.get(1).map(|s| s.as_str()).unwrap_or("verify");

    match cmd {
        "verify" => {
            let count: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(100);
            println!(
                "[arpg-mapgen] Verifying {} seeds across all 4 Scrap Frontier biomes (macro graph + 2D heightfield grid)...",
                count
            );
            for i in 1..=count {
                let seed = i * 99_991;
                let depth = ((i as usize - 1) % 4) + 1;
                let bp = build_zone_blueprint(seed, depth, 4096.0, 4096.0, None);
                if let Err(err) = verify_blueprint_and_grid_pathability(&bp, 96) {
                    eprintln!("[ERROR] Seed {} (depth {}) failed: {}", seed, depth, err);
                    process::exit(1);
                }
            }
            println!(
                "[arpg-mapgen] PASS: {}/{} seeds verified with 100% connectivity and walkable slope bounds.",
                count, count
            );
        }
        "generate" => {
            let seed: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(424_242);
            let depth: usize = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(1);
            let bp = build_zone_blueprint(seed, depth, 4096.0, 4096.0, None);
            verify_blueprint_and_grid_pathability(&bp, 96).expect("Generated map failed pathability");

            println!(
                "=== Zone #{} | Biome: {} ({}) | Seed: {} ===",
                bp.zone_depth,
                bp.biome.kind.title(),
                bp.biome.kind.id(),
                bp.seed
            );
            println!(
                "Nodes: {} | Edges: {} | Pre-Seeded Wrecks: {} | Boss: {}",
                bp.nodes.len(),
                bp.edges.len(),
                bp.planned_wrecks.len(),
                bp.biome.boss_title
            );
            print!("{}", render_ascii_map(&bp, 64, 32));

            let mut i = 4;
            while i < args.len() {
                if args[i] == "--svg" && i + 1 < args.len() {
                    fs::write(&args[i + 1], render_svg_map(&bp)).expect("Failed to write SVG");
                    println!("Wrote SVG preview to {}", args[i + 1]);
                    i += 2;
                } else if args[i] == "--lua" && i + 1 < args.len() {
                    fs::write(&args[i + 1], export_lua_blueprint(&bp)).expect("Failed to write Lua");
                    println!("Wrote Lua blueprint to {}", args[i + 1]);
                    i += 2;
                } else {
                    i += 1;
                }
            }
        }
        _ => {
            eprintln!("Usage: arpg-mapgen [verify <count> | generate <seed> <depth> [--svg <path>] [--lua <path>]]");
            process::exit(1);
        }
    }
}
