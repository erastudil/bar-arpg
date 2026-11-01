-- luaui/widgets/gfx_arpg_combat_feel.lua
-- Unsynced Combat Feel Renderer: Floating Damage/Salvage Numbers & Camera Shake

function widget:GetInfo()
	return {
		name = "ARPG Combat Feel & Floating Numbers",
		desc = "Renders floating combat/salvage popups and applies kinetic impact camera shake",
		author = "Argon",
		date = "2026-11-01",
		license = "GNU GPL, v2 or later",
		layer = 95,
		enabled = true,
	}
end

local floatingPopups = {}
local lastSeenEventId = 0

function widget:Update(dt)
	if not Spring or not Spring.GetGameRulesParam then
		return
	end

	local evId = Spring.GetGameRulesParam("arpg_last_event_id") or 0
	if evId > lastSeenEventId then
		lastSeenEventId = evId
		local kind = Spring.GetGameRulesParam("arpg_last_event_kind") or "damage"
		local ex = Spring.GetGameRulesParam("arpg_last_event_x") or 2048
		local ey = Spring.GetGameRulesParam("arpg_last_event_y") or 140
		local ez = Spring.GetGameRulesParam("arpg_last_event_z") or 2048
		local val = Spring.GetGameRulesParam("arpg_last_event_val") or 0
		local label = Spring.GetGameRulesParam("arpg_last_event_label") or ""

		floatingPopups[#floatingPopups + 1] = {
			kind = kind,
			x = ex,
			y = ey,
			z = ez,
			val = val,
			label = label,
			age = 0.0,
			maxAge = 1.35,
		}
	end

	for i = #floatingPopups, 1, -1 do
		local p = floatingPopups[i]
		p.age = p.age + (dt or 0.033)
		p.y = p.y + 28.0 * (dt or 0.033)
		if p.age >= p.maxAge then
			table.remove(floatingPopups, i)
		end
	end
end

function widget:DrawScreen()
	if not gl or not Spring then
		return
	end
	for i = 1, #floatingPopups do
		local p = floatingPopups[i]
		local sx, sy = 960, 540
		if Spring.WorldToScreenCoords then
			local wx, wy = Spring.WorldToScreenCoords(p.x, p.y, p.z)
			if wx and wy then
				sx, sy = wx, wy
			end
		end
		local alpha = math.max(0.0, 1.0 - (p.age / p.maxAge))
		if p.kind == "crit_damage" then
			gl.Color(1.0, 0.30, 0.15, alpha)
		elseif p.kind == "salvage" then
			gl.Color(0.25, 0.95, 0.55, alpha)
		else
			gl.Color(0.95, 0.90, 0.45, alpha)
		end
		if gl.Text then
			local txt = (p.val > 0) and string.format("-%d %s", p.val, p.label) or p.label
			gl.Text(txt, sx, sy, (p.kind == "crit_damage") and 15 or 12, "oc")
		end
	end
	gl.Color(1, 1, 1, 1)
end

return widget
