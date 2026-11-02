-- scripts/arpg_hero_chassis.lua
-- Spring/Recoil Lua Unit Script (LUS) for the Wreckage Protocol Modular Hero Chassis
-- Controls multi-turret aiming, weapon muzzle queries, nano-lathe reclaim channel, and death wreck creation.

local base = piece and piece("base") or 1
local pelvis = piece and piece("pelvis") or 2
local torso = piece and piece("torso") or 3
local larm = piece and piece("larm") or 4
local rarm = piece and piece("rarm") or 5
local lfirept = piece and piece("lfirept") or 6
local rfirept = piece and piece("rfirept") or 7
local nanolathe = piece and piece("nanolathe") or 8

local SIG_AIM_PRIMARY = 2
local SIG_AIM_SECONDARY = 4
local SIG_AIM_UNIQUE = 8
local SIG_BUILD = 16

local isMoving = false

function script.Create()
	if Spring and Spring.SetUnitRulesParam and unitID then
		Spring.SetUnitRulesParam(unitID, "arpg_lus_initialized", 1)
	end
end

function script.StartMoving()
	isMoving = true
end

function script.StopMoving()
	isMoving = false
end

function script.AimFromWeapon(weaponNum)
	if weaponNum == 1 then
		return rarm
	elseif weaponNum == 2 then
		return larm
	else
		return torso
	end
end

function script.QueryWeapon(weaponNum)
	if weaponNum == 1 then
		return rfirept
	elseif weaponNum == 2 then
		return lfirept
	else
		return nanolathe
	end
end

function script.AimWeapon(weaponNum, heading, pitch)
	if Signal and SetSignalMask and Turn and WaitForTurn then
		local sig = (weaponNum == 1 and SIG_AIM_PRIMARY)
			or (weaponNum == 2 and SIG_AIM_SECONDARY)
			or SIG_AIM_UNIQUE
		Signal(sig)
		SetSignalMask(sig)
		local yAxis = y_axis or 2
		local xAxis = x_axis or 1
		Turn(torso, yAxis, heading, math.rad(360))
		if weaponNum == 1 then
			Turn(rarm, xAxis, -pitch, math.rad(280))
			WaitForTurn(torso, yAxis)
			WaitForTurn(rarm, xAxis)
		elseif weaponNum == 2 then
			Turn(larm, xAxis, -pitch, math.rad(240))
			WaitForTurn(torso, yAxis)
			WaitForTurn(larm, xAxis)
		else
			WaitForTurn(torso, yAxis)
		end
	end
	return true
end

function script.FireWeapon(weaponNum)
	if EmitSfx then
		local muzzle = (weaponNum == 1 and rfirept) or (weaponNum == 2 and lfirept) or nanolathe
		EmitSfx(muzzle, 1024)
	end
	if GG and GG.ARPG_Assembly and unitID then
		local st = GG.ARPG_Assembly.GetHeroState(unitID)
		if st then
			local heatAdd = (weaponNum == 1 and 1.2) or (weaponNum == 2 and 3.5) or 8.0
			st.heat = math.min((st.maxHeat or 140) * 1.25, (st.heat or 0) + heatAdd)
		end
	end
end

function script.StartBuilding(heading, pitch)
	if Signal and SetSignalMask and Turn and SetUnitValue then
		Signal(SIG_BUILD)
		SetSignalMask(SIG_BUILD)
		local yAxis = y_axis or 2
		Turn(torso, yAxis, heading, math.rad(320))
		if COB and COB.INBUILDSTANCE then
			SetUnitValue(COB.INBUILDSTANCE, 1)
		end
	end
end

function script.StopBuilding()
	if Signal and SetUnitValue then
		Signal(SIG_BUILD)
		if COB and COB.INBUILDSTANCE then
			SetUnitValue(COB.INBUILDSTANCE, 0)
		end
	end
end

function script.QueryNanoPiece()
	return nanolathe
end

function script.Killed(recentDamage, maxHealth)
	local severity = (recentDamage or 0) / math.max(1, maxHealth or 4500)
	if severity <= 0.50 then
		return 1
	end
	return 2
end
