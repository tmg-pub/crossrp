-------------------------------------------------------------------------------
-- Cross RP
-- by Tammya-MoonGuard (2018)
--
-- All Rights Reserved
-------------------------------------------------------------------------------
-- Time to get messy...
-------------------------------------------------------------------------------
local _, Me = ...

local CROSSRP_VERSION = GetAddOnMetadata( "CrossRP", "Version" )
local VERNUM_VERSION = 1

local host_addon_version

local MSP_imp = {}

local msp_fields = {
	A = {
		
	};
	B = {
	
	};
	C = {
	};
	D = {
	};
}

local function SetupTransferProfile()
	if not Me.msp_profile.A then
		Me.msp_profile.A = {
			CO = ""; -- Currently (OOC)
			CU = ""; -- Currently
			RP = 2; -- Out-of-character
			XP = 2; -- Experienced Roleplayer
			v  = 1;
		}
	end
	
	if not Me.msp_profile.B then
		Me.msp_profile.B = {
			CL = UnitClass("player"); -- Class
			RA = UnitRace("player");  -- Race
			FN = UnitName("player");  -- Name
			MI = {}; -- Additional Information
			PS = {}; -- Personality Traits
			--IC = "Achievement_Character_Human_Female";
			v  = 1;
		}
	end
	
	if not Me.msp_profile.C then
		Me.msp_profile.C = {
			PE = {
				["5"] = {
					AC = true;
					TI = "(Cross RP)";
					TX = "(This profile was transferred using Cross RP " .. CROSSRP_VERSION .. ".)";
					IC = "INV_Jewelcrafting_ArgusGemCut_Green_MiscIcons";
				};
			};
			ST = {
				["1"] = 0;
				["2"] = 0;
				["3"] = 0;
				["4"] = 0;
				["5"] = 0;
				["6"] = 0;
			};
			v = 1;
		}
	end
	
	if not Me.msp_profile.D then
		Me.msp_profile.D = {
			BK = 6; -- Background
			TE = 3; -- Template 3
			T3 = { -- Template 3 data
				PH = { -- Physical Description
					IC = "Ability_Warrior_StrengthOfArms"; -- Icon
					BK = 1; -- Background
					TX = nil; -- Text
				};
				HI = { -- History
					IC = "INV_Misc_Book_17"; -- Icon
					BK = 1; -- Background
					TX = nil; -- Text
				}
			};
			v = 1;
		}
	end
end

local function UpdateTransferProfile()
	
end


local function GetData_Misc()
	
	return Me.msp_profile.C
end

local function GetData_About()
	
end


function MSP_imp.BuildVernum()
	UpdateTransferProfile()
	local trial = IsTrialAccount() or IsVeteranTrialAccount()
	
	local pieces = {}
	pieces[Me.VERNUM_VERSION]      = VERNUM_VERSION
	pieces[Me.VERNUM_VERSION_TEXT] = msp.my.VA
	pieces[Me.Me.VERNUM_PROFILE]   = "[CRP]" .. Me.fullname
	pieces[Me.VERNUM_CHS_V]        = Me.msp_profile.B.v
	pieces[Me.VERNUM_ABOUT_V]      = Me.msp_profile.D.v
	pieces[Me.VERNUM_MISC_V]       = Me.msp_profile.C.v
	pieces[Me.VERNUM_CHAR_V]       = Me.msp_profile.A.v
	pieces[Me.VERNUM_TRIAL]        = trial and "1" or "0"
	
	return table.concat( pieces, ":" )
end

function MSP_imp.OnVernum( user, vernum )
	local entry = user.name .. "-" .. vernum[Me.VERNUM_PROFILE]
	local current = Me.msp_vernum_cache[entry]
	Me.msp_vernum_cache[entry] = {
		time = time();
		vernum = vernum;
	}
	local update_all = false
	
	for i = 1, Me.UPDATE_SLOTS do
		local vi = Me.VERNUM_CHS_V+i-1
		if not current or vernum[vi] ~= current.vernum[vi] then
			Me.TRP_SetNeedsUpdate( user.name, i )
		end
	end
end

function MSP_imp.GetExchangeData( section )
	UpdateTransferProfile()
	
	if section == Me.TRP_UPDATE_CHAR then
		return Me.msp_profile.A
	elseif section == Me.TRP_UPDATE_CHS then
		return Me.msp_profile.B
	elseif section == Me.TRP_UPDATE_MISC then
		return Me.msp_profile.C
	elseif section == Me.TRP_UPDATE_ABOUT then
		return Me.msp_profile.D
	end
end

function MSP_imp.SaveProfileData( user, index, data )
	
end

function MSP_imp.IsPlayerKnown( username )
	
end

function MSP_imp.Init()
	
end

function Me.MSP_Init()
	if not mrp and not xrp then return end
	
	Me.msp_addon = "unknown"
	local crossrp_version = GetAddOnMetadata( "CrossRP", "Version" )
	if mrp then
		Me.msp_addon = "MyRolePlay " .. GetAddOnMetadata( "MyRolePlay", 
		                                                            "Version" )
	elseif xrp then
		Me.msp_addon = "XRP " .. GetAddOnMetadata( "XRP", "Version" )
	else
		return
	end
	Me.DebugLog2( "Compatible profile addon version", Me.msp_addon )
	Me.TRP_imp = MSP_imp
	
	if not Me.db.char.msp_data 
	            or Me.db.char.msp_data.addon ~= Me.msp_addon 
				         or Me.db.char.msp_data.crossrp ~= crossrp_version then
		-- Wipe it.
		Me.db.char.msp_data = {
			addon   = Me.msp_addon;
			crossrp = crossrp_version;
			profile = {};
		}
		Me.db.global.msp_vernum_cache = {}
	end
	
	Me.msp_profile = Me.db.char.msp_data.profile
	Me.msp_vernum_cache = Me.db.global.msp_vernum_cache
	
	-- Purge old entries.
	for k,v in pairs( Me.msp_vernum_cache ) do
		if time() - v.time > (60*60*24*7) then
			Me.msp_vernum_cache[k] = nil
		end
	end
	
	-- Initialize profile structure.
	SetupProfile()
end


