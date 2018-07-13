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

local function SetupTRPProfile()
	if not Me.trp_profile.A then
		Me.trp_profile.A = {
			CO = ""; -- Currently (OOC)
			CU = ""; -- Currently
			RP = 2; -- Out-of-character
			XP = 2; -- Experienced Roleplayer
			v  = 1;
			
			-- No optional fields.
		}
	end
	
	if not Me.trp_profile.B then
		Me.trp_profile.B = {
			CL = UnitClass("player"); -- Class
			RA = UnitRace("player");  -- Race
			FN = UnitName("player");  -- Name
			MI = { -- Additional Information
				-- Optional fields are structs for house name, nickname, 
				--  and motto.
			};
			PS = {}; -- Personality Traits (Unused)
			--IC = "Achievement_Character_Human_Female";
			v  = 1;
		}
	end
	
	if not Me.trp_profile.C then
		-- Section C isn't used for MSP.
		Me.trp_profile.C = {
			-- At first glances.
			PE = {
				["5"] = {
					AC = true;
					TI = "(Cross RP)";
					TX = "(This profile was transferred using Cross RP " 
					     .. CROSSRP_VERSION .. ".)";
					IC = "INV_Jewelcrafting_ArgusGemCut_Green_MiscIcons";
				};
			};
			
			-- RP Style
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
	
	if not Me.trp_profile.D then
		-- About page.
		Me.trp_profile.D = {
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
	
	if not Me.trp_profile.mspver then
		-- We could either cache the version numbers or the values.
		-- Of course this saves memory.
		Me.trp_profile.mspver = {}
	end
end

-------------------------------------------------------------------------------
local m_changed = false
local function UpdateTRPField( key, value )
	local parts = strsplit( key )
	local t = Me.trp_profile
	
	for i = 1, #parts-1 do
		if not t[ parts[i] ] then
			m_changed = true
		end
		t = t[ parts[i] ]
	end
	
	local finalkey = parts[#parts]
	
	if t[finalkey] == value then return end
	
	-- We do this so we can increment v only once when anything changes.
	m_changed = true
	t[finalkey] = value
end

-------------------------------------------------------------------------------
local function MyRPStyle()
	if msp.my.FR == "4" then return 1 end
	return 2
end

local function MyCharacterStatus()
	if msp.my.FC == "1" then return 2 end
	return 1 end
end

-------------------------------------------------------------------------------
--[[
local function UpdateTRPProfile()
	m_changed = false
	UpdateTRPField( "A.CU", msp.my.CU )
	UpdateTRPField( "A.CO", msp.my.CO )
	UpdateTRPField( "A.RP", MyCharacterStatus() )
	UpdateTRPField( "A.XP", MyRPStyle() )
	BumpVersion( Me.trp_profile.A )
	
	UpdateTRPField( "B.EC", eye color
	UpdateTRPField( "B.FN", name     not nil
	UpdateTRPField( "B.AG", age
	UpdateTRPField( "B.IC", icon
	UpdateTRPField( "B.HE", height
	UpdateTRPField( "B.CH", class color    
	UpdateTRPField( "B.RA", race           not nil
	UpdateTRPField( "B.BP", birthplace
	UpdateTRPField( "B.RE", residence
	UpdateTRPField( "B.CL", class
	UpdateTRPField( "B.FT", title
	UpdateTRPField( "B.MI
	
		Me.trp_profile.A.v = Me
		UpdateTRPField( "A.v", 
			CO = ""; -- Currently (OOC)
			CU = ""; -- Currently
			RP = 2; -- Out-of-character
			XP = 2; -- Experienced Roleplayer
end]]

local m_section_dirty = {}

-------------------------------------------------------------------------------
-- These are the MSP fields that we support. The list of TRP supported values
--  is here:
--   https://totalrp3.info/documentation/technical_design/mary_sue_protocol
local MSP_FIELD_MAP = {
	-- GROUP A
	-- Currently, Currently OOC, Character Staus, RP Style
	CU = 'A'; CO = 'A'; FC = 'A'; FR = 'A';
	
	-- GROUP B
	-- Eye Color, Height, Age, Body Shape
	AE = 'B'; AH = 'B'; AG = 'B'; AW = 'B';
	-- Birthplace, residence, Icon, Motto
	HB = 'B'; HH = 'B'; IC = 'B'; MO = 'B';
	-- Name, Nickname, House Name, Title
	NA = 'B'; NI = 'B'; NH = 'B'; NT = 'B';
	-- Race, Custom Class
	RA = 'B'; RC = 'B';
	
	-- GROUP C doesn't have any MSP values.
	
	-- GROUP D
	-- Description, History
	DE = 'D'; HI = 'D';

	-- UNUSED FIELDS
	-- GC (Game Class), GF (Game Faction), GR (Game Race), GS (Game Sex)
	-- GU (Game GUID), VA (Addon versions), VP (Protocol version)
}

-------------------------------------------------------------------------------
local TRP_SIMPLE_MSP_MAP = {
	CU = "CU"; -- CURRENTLY
	CO = "CO"; -- CURRENTLY OOC
	
	AE = "EC"; -- EYE COLOR
	AG = "AG"; -- AGE
	HB = "BP"; -- BIRTHPLACE
	HH = "RE"; -- RESIDENCE
	IC = "IC"; -- ICON
	NA = "FN"; -- NAME
	NT = "FT"; -- TITLE
	RA = "RA"; -- RACE
	RC = "CL"; -- CLASS
	AH = "HE"; -- HEIGHT        -- We can't localize these because this is what
	AW = "WE"; -- WEIGHT/SHAPE  --  we're transferring /shrug.
}

local strtrim( value )
	return value:gmatch( "^%s*(%S*)%s*$" )
end

-------------------------------------------------------------------------------
local function RebuildAdditionalInfo()
	if msp.my.MO == "" and msp.my.NI == "" and msp.my.NH == "" then
		wipe( Me.trp_profile.B.MI )
		return
	end
	
	local data = Me.trp_profile.B.MI
	wipe( data )
	
	if msp.my.NH ~= "" then
		table.insert( data, {
			IC = "inv_misc_kingsring1";
			NA = "House Name";
			VA = msp.my.NH;
		})
	end
	
	if msp.my.NI ~= "" then
		table.insert( data, {
			IC = "Ability_Hunter_BeastCall";
			NA = "Nickname";
			VA = "NICKNAME";
		})
	end
	
	if msp.my.MO ~= "" then
		table.insert( data, {
			IC = "INV_Inscription_ScrollOfWisdom_01";
			NA = "Motto";
			VA = msp.my.MO;
		})
	end
end

-------------------------------------------------------------------------------
-- Called when a value in the msp registry is changed.
--
local function OnMSPUpdated( name, field, value, crc )
	-- We're only interested in changes to our own profile.
	if name ~= Me.fullname then return end
	
	local section = MSP_FIELD_MAP[field]
	if not section then return end
	
	-- This will stop us from updating everything when the game starts.
	if Me.trp_profile.mspver[field] == crc then
		return
	end
	Me.trp_profile.mspver[field] = crc
	
	m_section_dirty[section] = true
	
	local vornil = value == "" and value or nil
	local isnumber = value:match( "^[0-9]+$" )
	
	local simple = TRP_SIMPLE_MSP_MAP[field]
	if simple then
		Me.trp_profile[section][simple] = vornil
	end
	
	local tv = strtrim(value)
	
	if field == "NA" and tv == "" then
		Me.trp_profile.B.FN = UnitName( "player" )
	elseif field == "RA" and tv == "" then
		Me.trp_profile.B.RA = UnitRace( "player" )
	elseif field == "RC" and tv == "" then
		Me.trp_profile.B.CL = UnitClass( "player" )
	elseif field == "DE" then
		Me.trp_profile.D.PH.TX = vornil
	elseif field == "HI" then
		Me.trp_profile.D.HI.TX = vornil
	elseif field == "FC" then
		Me.trp_profile.A.RP = value == "1" and 2 or 1
	elseif field == "FR" then
		Me.trp_profile.A.XP = value == "4" and 1 or 2
	elseif field == "MO" or field == "NI" or field == "NH" then
		RebuildAdditionalInfo()
	end
end

-------------------------------------------------------------------------------
local function BumpVersion( table, condition )
	if not condition then return end
	table.v = table.v + 1
	if table.v >= 100 then table.v = 1 end
end

-------------------------------------------------------------------------------
local function OnMSPReceived( name )
	if name ~= Me.fullname then return end
	
	BumpVersion( Me.trp_profile.A, m_section_dirty.A )
	BumpVersion( Me.trp_profile.B, m_section_dirty.B )
	BumpVersion( Me.trp_profile.C, m_section_dirty.C )
	BumpVersion( Me.trp_profile.D, m_section_dirty.D )
	wipe( m_section_dirty )
	
	-- schedule vernum exchange
end

-------------------------------------------------------------------------------
local function UpdateMSPField( name, field, value, version )
	value = value or ""
	value = tostring( value )
	if not value then return end
	
	if msp.char[name].field[field] == value then
	  --                 and msp.char[name].ver[field] == version then
		return
	end
	
	msp.char[name].field[field] = value
	--msp.char[name].ver[field] = version
	for _,v in ipairs( msp.callback.updated ) do
		v( name, field, value, nil )--version )
	end
end

-------------------------------------------------------------------------------
local function TriggerReceivedCallback( name )
	for _,v in ipairs( msp.callback.received ) do
		v( name, field, value, version )
	end
end

-------------------------------------------------------------------------------
function MSP_imp.BuildVernum()
	UpdateTransferProfile()
	local trial = IsTrialAccount() or IsVeteranTrialAccount()
	
	local pieces = {}
	pieces[Me.VERNUM_VERSION]      = VERNUM_VERSION
	pieces[Me.VERNUM_VERSION_TEXT] = msp.my.VA
	pieces[Me.Me.VERNUM_PROFILE]   = "[CRP]" .. Me.fullname
	pieces[Me.VERNUM_CHS_V]        = Me.trp_profile.B.v
	pieces[Me.VERNUM_ABOUT_V]      = Me.trp_profile.D.v
	pieces[Me.VERNUM_MISC_V]       = Me.trp_profile.C.v
	pieces[Me.VERNUM_CHAR_V]       = Me.trp_profile.A.v
	pieces[Me.VERNUM_TRIAL]        = trial and "1" or "0"
	
	return table.concat( pieces, ":" )
end


-------------------------------------------------------------------------------
function MSP_imp.OnVernum( user, vernum )
	local entry = user.name .. "-" .. vernum[Me.VERNUM_PROFILE]
	
	for i = 1, Me.UPDATE_SLOTS do
		local vi = Me.VERNUM_CHS_V+i-1
		local mspkey = "CR"..i
		if msp.char[user.name].field[mspkey] ~= vernum[vi] then
			-- TODO: don't forget to update this field!
			Me.TRP_SetNeedsUpdate( user.name, i )
		end
	end
end

-------------------------------------------------------------------------------
function MSP_imp.GetExchangeData( section )
	UpdateTransferProfile()
	
	if section == Me.TRP_UPDATE_CHAR then
		return Me.trp_profile.A
	elseif section == Me.TRP_UPDATE_CHS then
		return Me.trp_profile.B
	elseif section == Me.TRP_UPDATE_MISC then
		return Me.trp_profile.C
	elseif section == Me.TRP_UPDATE_ABOUT then
		return Me.trp_profile.D
	end
end

-------------------------------------------------------------------------------
local function GetMIString( data, name )
	for k,v in pairs( data.MI or {} ) do
		if v.NA:lower() == name then
			return v.VA
		end
	end
end

-------------------------------------------------------------------------------
local function SaveCHSData( user, data )
	UpdateMSPField( user.name, "CR1", data.v )
	
	local fullname = ""
	if data.TI and data.TI ~= "" then
		fullname = data.TI
	end
	local firstname = data.FN
	if not firstname or firstname == "" then
		firstname = user.name:match( "^[^%-]*" )
	end
	
	if fullname ~= "" then fullname = fullname .. " " end
	fullname = fullname .. firstname
	
	if data.LN and data.LN ~= "" then
		if fullname ~= "" then fullname = fullname .. " " end
		fullname = fullname .. data.LN
	end
	
	UpdateMSPField( user.name, "NA", fullname )
	UpdateMSPField( user.name, "NT", data.FT  )
	UpdateMSPField( user.name, "IC", data.IC  )
	UpdateMSPField( user.name, "RA", data.RA  )
	UpdateMSPField( user.name, "RC", data.CL  )
	UpdateMSPField( user.name, "AH", data.HE  )
	UpdateMSPField( user.name, "AG", data.AG  )
	UpdateMSPField( user.name, "AE", data.EC  )
	UpdateMSPField( user.name, "AW", data.WE  )
	UpdateMSPField( user.name, "HB", data.BP  )
	UpdateMSPField( user.name, "HH", data.RE  )
	UpdateMSPField( user.name, "MO", GetMIString( data, "motto" ))
	UpdateMSPField( user.name, "NI", GetMIString( data, "nickname" ))
	UpdateMSPField( user.name, "NH", GetMIString( data, "house name" ))
end

-------------------------------------------------------------------------------
local function SaveAboutData( user, data )
	-- Some of the code below might error, so we want to make sure that we save
	--  the version first and foremost so nobody is going to be re-transferring
	--  their profile again and again due to it not being able to be saved.
	UpdateMSPField( user.name, "CR2", data.v )
	
	if data.TE == 1 then
		-- Template 1
		local text = data.T1.TX
		
		-- {link*http://your.url.here*Your text here}
		text = text:gsub( "{link%*([^*])%*([^}])}", function( link, text )
			return link .. "(" .. text .. ")"
		end
		
		text = text:gsub( "{[^}]*}", "" )
		
		UpdateMSPField( user.name, "DE", text )
		UpdateMSPField( user.name, "HI", "" )
		
	elseif data.TE == 2 then
		-- Template 2
		local text = ""
		if data.t2 and data.t2[1] then
			for _, page in ipairs( data.t2 or {} ) do
				text = text .. (page.TX or "") .. "\n\n"
			end
		end
		UpdateMSPField( user.name, "DE", text )
		UpdateMSPField( user.name, "HI", "" )
		
	elseif data.TE == 3 then
		-- Template 3
		UpdateMSPField( user.name, "DE", data.T3.PH.TX )
		UpdateMSPField( user.name, "HI", data.T3.HI.TX )
	end
end

-- These should be localized? Not sure if something might depend on them to be
--  keys.
local FR_VALUES = {
	[1] = "Beginner roleplayer";
	[2] = "Experienced roleplayer";
	[3] = "Volunteer roleplayer";
}

-------------------------------------------------------------------------------
local function SaveCharacterData( user, data )
	UpdateMSPField( user.name, "CR4", data.v )
	
	UpdateMSPField( user.name, "CU", data.CU )
	UpdateMSPField( user.name, "CO", data.CO )
	UpdateMSPField( user.name, "FC", data.RP == 1 and "2" or "1" )
	UpdateMSPField( user.name, "FR", FR_VALUES[ data.XP ] )
end

-------------------------------------------------------------------------------
function MSP_imp.SaveProfileData( user, index, data )
	if index == 1 then -- CHS
		SaveCHSData( user, data )
	elseif index == 2 then -- ABOUT
		SaveAboutData( user, data )
	elseif index == 3 then -- MISC
		-- Nothing to save.
		UpdateMSPField( user.name, "CR3", data.v )
	elseif index == 4 then -- CHAR
		SaveCharacterData( user, data )
	end
end

-------------------------------------------------------------------------------
function MSP_imp.IsPlayerKnown( username )
	return msp.char[username].supported
end

-------------------------------------------------------------------------------
function MSP_imp.Init()
	
end

-------------------------------------------------------------------------------
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
			trp_profile = {};
		}
	end
	
	Me.trp_profile = Me.db.char.msp_data.trp_profile

	-- Initialize profile structure.
	SetupTRPProfile()
end


