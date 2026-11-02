-- luaui/widgets/gui_arpg_hud.lua
-- ARPG Control Scheme, Camera Lock, Ground Telegraph Renderer, Engineering Budget HUD,
-- Salvage Channel Bar, and Armored Core Modular Garage / Deterministic Machining UI.

function widget:GetInfo()
	return {
		name = "ARPG HUD, Camera & Modular Garage",
		desc = "Single-unit ARPG camera lock, WASD/click controls, telegraph rings, Mass/Heat/Power HUD, and AC Garage",
		author = "Argon",
		date = "2026-11-01",
		license = "GNU GPL, v2 or later",
		layer = 100,
		enabled = true,
	}
end

local PartsDB = VFS and VFS.Include and VFS.Include("luarules/configs/arpg_parts_db.lua")
	or require("luarules/configs/arpg_parts_db")

local Parts = PartsDB.Parts
local Materials = PartsDB.Materials
local SlotOrder = PartsDB.SlotOrder

local cameraLockEnabled = true
local garageDrawerOpen = false
local selectedSlotIndex = 1
local uiButtons = {} -- populated during layout/hit-testing

local function getHeroUnitID()
	if Spring and Spring.GetGameRulesParam then
		local id = Spring.GetGameRulesParam("arpg_hero_unit_id")
		if id and id > 0 then
			return id
		end
	end
	return nil
end

local function getCursorWorldPos()
	if not Spring or not Spring.GetMouseState or not Spring.TraceScreenRay then
		return 2048, 140, 2048
	end
	local mx, my = Spring.GetMouseState()
	local kind, coords = Spring.TraceScreenRay(mx, my, true)
	if kind == "ground" and coords then
		return coords[1], coords[2], coords[3]
	end
	return 2048, 140, 2048
end

local function triggerModuleAbility(slotIdx)
	if not Spring or not Spring.SendLuaRulesMsg then
		return
	end
	local tx, _, tz = getCursorWorldPos()
	Spring.SendLuaRulesMsg(string.format("arpg:ability:%d:%d:%d", slotIdx, math.floor(tx), math.floor(tz)))
end

local function triggerNearestSalvage()
	if Spring and Spring.SendLuaRulesMsg then
		Spring.SendLuaRulesMsg("arpg:reclaim_nearest")
	end
end

local function triggerNearestRaise()
	if Spring and Spring.SendLuaRulesMsg then
		Spring.SendLuaRulesMsg("arpg:raise_nearest")
	end
end

function widget:Initialize()
	cameraLockEnabled = true
	garageDrawerOpen = false
end

function widget:Update(dt)
	local heroID = getHeroUnitID()
	if not heroID or not Spring then
		return
	end

	-- 1. Enforce Single-Unit ARPG Selection
	if Spring.SelectUnitArray and Spring.GetSelectedUnits then
		local sel = Spring.GetSelectedUnits()
		if not sel or #sel ~= 1 or sel[1] ~= heroID then
			Spring.SelectUnitArray({ heroID })
		end
	end

	-- 2. Smooth ARPG Camera Follow Lock
	if cameraLockEnabled and Spring.GetUnitPosition and Spring.SetCameraTarget then
		local hx, hy, hz = Spring.GetUnitPosition(heroID)
		if hx then
			Spring.SetCameraTarget(hx, hy, hz, 0.10)
		end
	end

	-- 3. Poll WASD Movement Vector if keys held
	if Spring.GetKeyState and Spring.SendLuaRulesMsg then
		-- KeyCodes: W=119, A=97, S=115, D=100
		local w = Spring.GetKeyState(119)
		local a = Spring.GetKeyState(97)
		local s = Spring.GetKeyState(115)
		local d = Spring.GetKeyState(100)
		local dx = (d and 1 or 0) - (a and 1 or 0)
		local dz = (s and 1 or 0) - (w and 1 or 0)
		if dx ~= 0 or dz ~= 0 then
			Spring.SendLuaRulesMsg(string.format("arpg:move:%d:%d", dx, dz))
		end
	end
end

function widget:KeyPress(key, mods, isRepeat)
	if isRepeat then
		return false
	end
	-- [TAB] (9) toggles Armored Core Modular Garage & Machining Bench
	if key == 9 then
		garageDrawerOpen = not garageDrawerOpen
		return true
	end
	-- [Y] (121) toggles Camera Follow Lock
	if key == 121 then
		cameraLockEnabled = not cameraLockEnabled
		return true
	end
	-- [C] (99) channels Salvage Reclaim on nearest wreck (Fork A: Strip)
	if key == 99 then
		triggerNearestSalvage()
		return true
	end
	-- [V] (118) channels Necro-Lathe Resurrection on nearest wreck (Fork B: Raise)
	if key == 118 then
		triggerNearestRaise()
		return true
	end
	-- [1]..[4] (49..52) fire Bolted-On Module Abilities 1..4
	if key >= 49 and key <= 52 then
		triggerModuleAbility(key - 48)
		return true
	end
	return false
end

function widget:MousePress(mx, my, button)
	if button ~= 1 then
		return false
	end
	for i = 1, #uiButtons do
		local b = uiButtons[i]
		if mx >= b.x1 and mx <= b.x2 and my >= b.y1 and my <= b.y2 then
			if b.onClick then
				b.onClick()
			end
			return true
		end
	end
	return false
end

-- ============================================================================
-- World-Space Rendering: Ground Telegraph Rings & Extraction Beacon
-- ============================================================================
function widget:DrawWorld()
	if not gl or not Spring or not Spring.GetGameRulesParam then
		return
	end

	local frame = (Spring.GetGameFrame and Spring.GetGameFrame()) or 0
	local teleCount = Spring.GetGameRulesParam("arpg_telegraph_count") or 0

	-- 1. Render "Map-Never-Lies" Heavy Attack Ground Telegraphs
	for i = 1, teleCount do
		local tx = Spring.GetGameRulesParam("arpg_tele_" .. i .. "_x")
		local tz = Spring.GetGameRulesParam("arpg_tele_" .. i .. "_z")
		local tr = Spring.GetGameRulesParam("arpg_tele_" .. i .. "_r") or 135
		local detFrame = Spring.GetGameRulesParam("arpg_tele_" .. i .. "_det") or (frame + 30)
		if tx and tz and frame < detFrame then
			local rem = math.max(1, detFrame - frame)
			local progress = math.max(0.1, math.min(1.0, 1.0 - (rem / 55.0)))
			gl.Color(1.0, 0.18, 0.12, 0.85)
			if gl.DrawGroundCircle then
				gl.DrawGroundCircle(tx, 0, tz, tr, 36)
				gl.Color(1.0, 0.55, 0.15, 0.55)
				gl.DrawGroundCircle(tx, 0, tz, tr * progress, 36)
			end
		end
	end

	-- 2. Render Orbital Warp Extraction Gate Ring
	local extX = Spring.GetGameRulesParam("arpg_extract_x")
	local extZ = Spring.GetGameRulesParam("arpg_extract_z")
	local unlocked = (Spring.GetGameRulesParam("arpg_extraction_unlocked") or 0) == 1
	if extX and extZ and gl.DrawGroundCircle then
		if unlocked then
			gl.Color(0.15, 0.95, 0.65, 0.90)
		else
			gl.Color(0.45, 0.55, 0.65, 0.45)
		end
		gl.DrawGroundCircle(extX, 0, extZ, 190, 40)
	end
	gl.Color(1, 1, 1, 1)
end

-- ============================================================================
-- Screen-Space Rendering: Engineering Budget HUD, Salvage Bar & AC Garage
-- ============================================================================
function widget:DrawScreen()
	if not gl or not Spring then
		return
	end
	uiButtons = {}

	local vsx, vsy = 1920, 1080
	if Spring.GetViewGeometry then
		vsx, vsy = Spring.GetViewGeometry()
	end

	local heroID = getHeroUnitID()
	local curHealth, maxHealth = 3500, 3500
	if heroID and Spring.GetUnitHealth then
		local h, mh = Spring.GetUnitHealth(heroID)
		if h and mh then
			curHealth, maxHealth = h, mh
		end
	end

	local mass = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_mass")) or 540
	local massLimit = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_mass_limit")) or 820
	local massState = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_mass_state")) or "OPTIMAL"
	local heat = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_heat")) or 0
	local heatCap = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_heat_cap")) or 135
	local powerOut = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_power_out")) or 185
	local powerDraw = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_power_draw")) or 110
	local raisedCount = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_raised_unit_count")) or 0
	local raisedDraw = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_raised_power_draw")) or 0
	local powerState = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_power_state")) or "SURPLUS"
	local salvageActive = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_salvage_active")) or 0
	local salvagePct = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_salvage_progress")) or 0
	local nearGarage = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_near_garage")) or 1

	-- 1. Bottom Center ARPG Chassis & Engineering Budget Panel
	local panelW = 760
	local panelH = 128
	local px = (vsx - panelW) * 0.5
	local py = 18

	gl.Color(0.06, 0.08, 0.11, 0.88)
	gl.Rect(px, py, px + panelW, py + panelH)

	-- Hull Integrity Bar
	local hullRatio = math.max(0.0, math.min(1.0, curHealth / math.max(1, maxHealth)))
	gl.Color(0.18, 0.78, 0.42, 0.90)
	gl.Rect(px + 16, py + 94, px + 16 + 220 * hullRatio, py + 114)

	-- Thermal Load Bar
	local heatRatio = math.max(0.0, math.min(1.0, heat / math.max(1, heatCap)))
	gl.Color(0.95, 0.42, 0.14, 0.90)
	gl.Rect(px + 256, py + 94, px + 256 + 220 * heatRatio, py + 114)

	if gl.Text then
		gl.Color(1, 1, 1, 1)
		gl.Text(string.format("HULL: %d / %d", math.floor(curHealth), math.floor(maxHealth)), px + 22, py + 98, 12, "o")
		gl.Text(string.format("HEAT: %d / %d (%s)", math.floor(heat), math.floor(heatCap), massState), px + 262, py + 98, 12, "o")
		gl.Text(
			string.format("MASS: %d/%d | POWER: %+d MW (%s) | REZ: %d (-%d MW)", mass, massLimit, powerOut - powerDraw, powerState, raisedCount, raisedDraw),
			px + 455,
			py + 98,
			10.5,
			"o"
		)
	end

	-- 4 Module-Derived Active Ability Buttons + Salvage Channel Button + Garage Toggle
	for idx = 1, 4 do
		local bx1 = px + 16 + (idx - 1) * 140
		local by1 = py + 14
		local bx2 = bx1 + 130
		local by2 = by1 + 66
		local abName = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_ability_" .. idx .. "_name"))
			or ("MODULE " .. idx)

		gl.Color(0.14, 0.20, 0.28, 0.95)
		gl.Rect(bx1, by1, bx2, by2)
		if gl.Text then
			gl.Color(0.85, 0.95, 1.0, 1.0)
			gl.Text(string.format("[%d] %s", idx, string.sub(tostring(abName), 1, 16)), bx1 + 8, by1 + 36, 11, "o")
		end
		local slotCopy = idx
		uiButtons[#uiButtons + 1] = {
			x1 = bx1,
			y1 = by1,
			x2 = bx2,
			y2 = by2,
			onClick = function()
				triggerModuleAbility(slotCopy)
			end,
		}
	end

	-- Salvage Channel Button [C] (Strip Wreck) & [V] (Raise Wreck)
	local sbx1 = px + 580
	local sby1 = py + 43
	local sbx2 = sbx1 + 82
	local sby2 = sby1 + 37
	gl.Color(0.75, 0.55, 0.12, 0.95)
	gl.Rect(sbx1, sby1, sbx2, sby2)
	if gl.Text then
		gl.Color(1, 1, 1, 1)
		gl.Text("[C] STRIP", sbx1 + 8, sby1 + 14, 10, "o")
	end
	uiButtons[#uiButtons + 1] = {
		x1 = sbx1,
		y1 = sby1,
		x2 = sbx2,
		y2 = sby2,
		onClick = triggerNearestSalvage,
	}

	local rbx1 = px + 580
	local rby1 = py + 14
	local rbx2 = rbx1 + 82
	local rby2 = rby1 + 25
	gl.Color(0.18, 0.68, 0.45, 0.95)
	gl.Rect(rbx1, rby1, rbx2, rby2)
	if gl.Text then
		gl.Color(1, 1, 1, 1)
		gl.Text("[V] RAISE", rbx1 + 8, rby1 + 8, 10, "o")
	end
	uiButtons[#uiButtons + 1] = {
		x1 = rbx1,
		y1 = rby1,
		x2 = rbx2,
		y2 = rby2,
		onClick = triggerNearestRaise,
	}

	-- Garage Drawer Toggle Button [TAB]
	local gbx1 = px + 670
	local gby1 = py + 14
	local gbx2 = gbx1 + 76
	local gby2 = gby1 + 66
	gl.Color(0.18, 0.45, 0.65, 0.95)
	gl.Rect(gbx1, gby1, gbx2, gby2)
	if gl.Text then
		gl.Color(1, 1, 1, 1)
		gl.Text("[TAB] RIG", gbx1 + 8, gby1 + 36, 11, "o")
	end
	uiButtons[#uiButtons + 1] = {
		x1 = gbx1,
		y1 = gby1,
		x2 = gbx2,
		y2 = gby2,
		onClick = function()
			garageDrawerOpen = not garageDrawerOpen
		end,
	}

	-- 2. Active Salvage Channel Progress Overlay
	if salvageActive == 1 then
		local scx = (vsx - 360) * 0.5
		local scy = py + panelH + 18
		gl.Color(0.08, 0.10, 0.12, 0.92)
		gl.Rect(scx, scy, scx + 360, scy + 34)
		gl.Color(0.95, 0.72, 0.18, 0.92)
		gl.Rect(scx + 4, scy + 4, scx + 4 + 352 * (salvagePct / 100.0), scy + 30)
		if gl.Text then
			gl.Color(1, 1, 1, 1)
			gl.Text(string.format("STRIPPING WRECKAGE CHANNEL: %d%%", salvagePct), scx + 55, scy + 11, 12, "o")
		end
	end

	-- 3. Armored Core Modular Assembly & Deterministic Machining Drawer
	if garageDrawerOpen then
		local gx = (vsx - 820) * 0.5
		local gy = (vsy - 520) * 0.5
		gl.Color(0.05, 0.07, 0.10, 0.95)
		gl.Rect(gx, gy, gx + 820, gy + 520)

		if gl.Text then
			gl.Color(0.90, 0.95, 1.0, 1.0)
			gl.Text(
				string.format(
					"ARMORED CORE MODULAR GARAGE & DETERMINISTIC MACHINING (%s)",
					nearGarage == 1 and "GARAGE PAD LINKED" or "FIELD READ-ONLY"
				),
				gx + 20,
				gy + 488,
				14,
				"o"
			)
		end

		-- Left Column: 9 Modular Assembly Slots
		for sIdx = 1, #SlotOrder do
			local slotName = SlotOrder[sIdx]
			local mountedId = (heroID and Spring.GetUnitRulesParam and Spring.GetUnitRulesParam(heroID, "arpg_slot_" .. slotName))
				or PartsDB.DefaultLoadout[slotName]
			local sy = gy + 435 - (sIdx - 1) * 44
			gl.Color((selectedSlotIndex == sIdx) and 0.22 or 0.12, 0.28, 0.38, 0.95)
			gl.Rect(gx + 20, sy, gx + 360, sy + 36)
			if gl.Text then
				gl.Color(1, 1, 1, 1)
				gl.Text(string.format("%s: %s", string.upper(slotName), tostring(mountedId)), gx + 28, sy + 12, 11, "o")
			end
			local idxCopy = sIdx
			uiButtons[#uiButtons + 1] = {
				x1 = gx + 20,
				y1 = sy,
				x2 = gx + 360,
				y2 = sy + 36,
				onClick = function()
					selectedSlotIndex = idxCopy
				end,
			}
		end

		-- Right Column: Compatible Parts for Selected Slot (Machine or Bolt On)
		local activeSlotName = SlotOrder[selectedSlotIndex] or "frame"
		local targetSlotType = activeSlotName
		if activeSlotName == "weapon_primary" or activeSlotName == "weapon_secondary" then
			targetSlotType = "weapon"
		elseif string.sub(activeSlotName, 1, 7) == "module_" then
			targetSlotType = "module"
		end

		local row = 0
		for partId, part in pairs(Parts) do
			if part.slot == targetSlotType then
				row = row + 1
				local ry = gy + 435 - (row - 1) * 48
				if ry >= gy + 30 then
					gl.Color(0.14, 0.18, 0.24, 0.95)
					gl.Rect(gx + 385, ry, gx + 800, ry + 40)
					if gl.Text then
						gl.Color(1, 1, 1, 1)
						gl.Text(
							string.format("T%d %s [M:%d P:%d]", part.techTier or 1, part.name, part.mass or 0, part.powerDraw or 0),
							gx + 392,
							ry + 14,
							11,
							"o"
						)
					end
					local pidCopy = partId
					local slotCopy = activeSlotName
					uiButtons[#uiButtons + 1] = {
						x1 = gx + 385,
						y1 = ry,
						x2 = gx + 800,
						y2 = ry + 40,
						onClick = function()
							if Spring and Spring.SendLuaRulesMsg then
								Spring.SendLuaRulesMsg("arpg:craft:" .. pidCopy)
								Spring.SendLuaRulesMsg("arpg:equip:" .. slotCopy .. ":" .. pidCopy)
							end
						end,
					}
				end
			end
		end
	end

	gl.Color(1, 1, 1, 1)
end

return widget
