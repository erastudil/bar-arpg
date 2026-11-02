use arpg_mapgen::{
    build_zone_blueprint, export_lua_blueprint, export_lua_map_atlas, generate_spring_launch_script,
    render_ascii_map, render_png_map_atlas, render_png_zone_map, render_svg_map,
    render_svg_map_atlas, verify_blueprint_and_grid_pathability,
};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process;

fn ensure_parent(p: &Path) {
    if let Some(parent) = p.parent() {
        if !parent.as_os_str().is_empty() {
            let _ = fs::create_dir_all(parent);
        }
    }
}

fn default_repo_root() -> PathBuf {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest_dir
        .parent()
        .and_then(|p| p.parent())
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."))
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let cmd = args.get(1).map(|s| s.as_str()).unwrap_or("verify");

    match cmd {
        "verify" => {
            let count: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(500);
            println!(
                "[arpg-mapgen] Verifying {} seeds across all 8 Scrap Frontier biomes (macro graph + 2D heightfield grid)...",
                count
            );
            for i in 1..=count {
                let seed = i * 99_991;
                let depth = ((i as usize - 1) % 8) + 1;
                let bp = build_zone_blueprint(seed, depth, 4096.0, 4096.0, None);
                if let Err(err) = verify_blueprint_and_grid_pathability(&bp, 80) {
                    eprintln!("[ERROR] Seed {} (depth {}) failed: {}", seed, depth, err);
                    process::exit(1);
                }
            }
            println!(
                "[arpg-mapgen] PASS: {}/{} seeds verified across all 8 biomes with 100% connectivity and zero softlocks.",
                count, count
            );
        }
        "atlas" => {
            let repo_root = default_repo_root();
            let seed: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(424_242);

            let png_bytes = render_png_map_atlas(seed);
            let svg_text = render_svg_map_atlas(seed);
            let lua_text = export_lua_map_atlas(seed);

            let out_png = repo_root.join("out/arpg_map_atlas.png");
            let vfs_png = repo_root.join("bitmaps/arpg_icons/arpg_map_atlas.png");
            let out_svg = repo_root.join("out/arpg_map_atlas.svg");
            let out_lua = repo_root.join("luarules/configs/arpg_map_atlas_blueprints.lua");

            for p in [&out_png, &vfs_png, &out_svg, &out_lua] {
                ensure_parent(p);
            }

            fs::write(&out_png, &png_bytes).expect("Failed to write out/arpg_map_atlas.png");
            fs::write(&vfs_png, &png_bytes)
                .expect("Failed to write bitmaps/arpg_icons/arpg_map_atlas.png");
            fs::write(&out_svg, &svg_text).expect("Failed to write out/arpg_map_atlas.svg");
            fs::write(&out_lua, &lua_text)
                .expect("Failed to write luarules/configs/arpg_map_atlas_blueprints.lua");

            println!(
                "[arpg-mapgen] Wrote Native 8-Biome Map Atlas (seed={}):\n  PNG : {} ({} bytes)\n  VFS : {} ({} bytes)\n  SVG : {} ({} bytes)\n  LUA : {} ({} bytes)",
                seed,
                out_png.display(),
                png_bytes.len(),
                vfs_png.display(),
                png_bytes.len(),
                out_svg.display(),
                svg_text.len(),
                out_lua.display(),
                lua_text.len()
            );
        }
        "launch-script" => {
            let out_path = args
                .get(2)
                .map(|s| s.as_str())
                .unwrap_or("out/wreckage_protocol_script.txt");
            let seed: u64 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(424_242);
            let biome = args.get(4).map(|s| s.as_str()).unwrap_or("salvage_yard");
            let chassis = args
                .get(5)
                .map(|s| s.as_str())
                .unwrap_or("frame_assault_medium");
            let modifier = args
                .get(6)
                .map(|s| s.as_str())
                .unwrap_or("lazarus_nanite_reanimation");
            let coop: usize = args.get(7).and_then(|s| s.parse().ok()).unwrap_or(1);
            ensure_parent(Path::new(out_path));
            let script = generate_spring_launch_script(seed, biome, chassis, modifier, coop);
            fs::write(out_path, script).expect("Failed to write Spring launch script");
            println!(
                "[arpg-mapgen] Generated Spring/Recoil launch script at {} (seed={}, biome={}, coop={})",
                out_path, seed, biome, coop
            );
        }
        "generate" => {
            let seed: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(424_242);
            let depth: usize = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(1);
            let bp = build_zone_blueprint(seed, depth, 4096.0, 4096.0, None);
            verify_blueprint_and_grid_pathability(&bp, 80).expect("Generated map failed pathability");

            println!(
                "=== Zone #{} | Biome: {} ({} / {}) | Seed: {} ===",
                bp.zone_depth,
                bp.biome.kind.title(),
                bp.biome.kind.id(),
                bp.biome.kind.topology(),
                bp.seed
            );
            println!(
                "Nodes: {} | Edges: {} | Pre-Seeded Wrecks: {} | Setpieces: {} | Boss: {}",
                bp.nodes.len(),
                bp.edges.len(),
                bp.planned_wrecks.len(),
                bp.setpieces.len(),
                bp.biome.boss_title
            );
            print!("{}", render_ascii_map(&bp, 64, 32));

            let mut i = 4;
            while i < args.len() {
                if args[i] == "--png" && i + 1 < args.len() {
                    let p = Path::new(&args[i + 1]);
                    ensure_parent(p);
                    fs::write(p, render_png_zone_map(&bp, 512)).expect("Failed to write PNG");
                    println!("Wrote PNG preview to {}", args[i + 1]);
                    i += 2;
                } else if args[i] == "--svg" && i + 1 < args.len() {
                    let p = Path::new(&args[i + 1]);
                    ensure_parent(p);
                    fs::write(p, render_svg_map(&bp)).expect("Failed to write SVG");
                    println!("Wrote SVG preview to {}", args[i + 1]);
                    i += 2;
                } else if args[i] == "--lua" && i + 1 < args.len() {
                    let p = Path::new(&args[i + 1]);
                    ensure_parent(p);
                    fs::write(p, export_lua_blueprint(&bp)).expect("Failed to write Lua");
                    println!("Wrote Lua blueprint to {}", args[i + 1]);
                    i += 2;
                } else {
                    i += 1;
                }
            }
        }
        _ => {
            eprintln!("Usage: arpg-mapgen [verify <count> | atlas [seed] | generate <seed> <depth> [--png <path>] [--svg <path>] [--lua <path>]]");
            process::exit(1);
        }
    }
}
