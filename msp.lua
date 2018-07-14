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

local host_addon_version

local MSP_imp = {}

function Me.MSP_CreateTRPTemplate( va )
	return {
		A = {
			CO = ""; -- Currently (OOC)
			CU = ""; -- Currently
			RP = 2; -- Out-of-character
			XP = 2; -- Experienced Roleplayer
			v  = 1;
			
			-- No optional fields.
		};
		B = {
			VA = va; -- Addon version (non TRP field)
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
		};
		C = {
			-- At first glances.
			PE = {};
			
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
		};
		D = {
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
		};
	}
end

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

-------------------------------------------------------------------------------
local function TrimString( value )
	return value:match( "^%s*(.-)%s*$" )
end

-------------------------------------------------------------------------------
local function RebuildAdditionalInfo()
	if msp.my.MO == "" and msp.my.NI == "" and msp.my.NH == "" then
		wipe( Me.trp_profile.B.MI )
		return
	end
	
	local data = Me.trp_profile.B.MI
	wipe( data )
	
	if msp.my.NH and msp.my.NH ~= "" then
		table.insert( data, {
			IC = "inv_misc_kingsring1";
			NA = "House Name";
			VA = msp.my.NH;
		})
	end
	
	if msp.my.NI and msp.my.NI ~= "" then
		table.insert( data, {
			IC = "Ability_Hunter_BeastCall";
			NA = "Nickname";
			VA = msp.my.NI;
		})
	end
	
	if msp.my.MO and msp.my.MO ~= "" then
		table.insert( data, {
			IC = "INV_Inscription_ScrollOfWisdom_01";
			NA = "Motto";
			VA = msp.my.MO;
		})
	end
end

-------------------------------------------------------------------------------
local function RebuildAboutData()
	local de = TrimString( msp.my.DE or "" )
	local hi = TrimString( msp.my.HI or "" )
	if de ~= "" and hi ~= "" then
		-- Physical and history. Use template 3.
		Me.trp_profile.D.TE = 3
		Me.trp_profile.D.T1 = nil
		Me.trp_profile.D.T3 = {
			PH = { -- Physical Description
				IC = "Ability_Warrior_StrengthOfArms"; -- Icon
				BK = 1; -- Background
				TX = de; -- Text
			};
			HI = { -- History
				IC = "INV_Misc_Book_17"; -- Icon
				BK = 1; -- Background
				TX = hi; -- Text
			}
		}
	elseif de ~= "" or hi ~= "" then
		-- Only one or none set, use template 1.
		local tx = de
		if tx == "" then tx = hi end
		if tx == "" then tx = nil end
		Me.trp_profile.D.TE = 1
		Me.trp_profile.D.T1 = {
			TX = tx
		}
		Me.trp_profile.D.T3 = nil
	end
end

-------------------------------------------------------------------------------
-- Called when a value in the msp registry is changed.
--
local function UpdateTRPField( field )
	local section = MSP_FIELD_MAP[field]
	if not section then return end
	
	local value = msp.my[field] or ""
	
	if Me.msp_cache[field] == value then
		-- Up to date.
		if not Me.msp_force_update then
			return
		end
	else
		m_section_dirty[section] = true
	end
	
	Me.DebugLog2( "Updating MSP field.", field, value )
	
	Me.msp_cache[field] = value
	
	local vornil = value
	if value == "" then vornil = nil end
	
	local isnumber = value:match( "^[0-9]+$" )
	
	local simple = TRP_SIMPLE_MSP_MAP[field]
	if simple then
		Me.trp_profile[section][simple] = vornil
	end
	
	local tv = TrimString(value)
	if field == "NA" and tv == "" then
		Me.trp_profile.B.FN = UnitName( "player" )
	elseif field == "RA" and tv == "" then
		Me.trp_profile.B.RA = UnitRace( "player" )
	elseif field == "RC" and tv == "" then
		Me.trp_profile.B.CL = UnitClass( "player" )
	elseif field == "DE" or field == "HI" then
		RebuildAboutData()
	elseif field == "FC" then
		Me.trp_profile.A.RP = value == "1" and 2 or 1
	elseif field == "FR" then
		Me.trp_profile.A.XP = value == "4" and 1 or 2
	elseif field == "MO" or field == "NI" or field == "NH" then
		RebuildAdditionalInfo()
	end
end

-------------------------------------------------------------------------------
local function BumpVersion( key, condition )
	if not condition then return end
	local a = (Me.msp_cache.ver[key] or 1)
	a = a + 1
	if a >= 100 then a = 1 end
	Me.msp_cache.ver[key] = a
end

-------------------------------------------------------------------------------
local function OnMSPReceived( name )
	if name ~= Me.fullname then return end
	
	Me.DebugLog2( "My MSP received." )
	
	-- Schedule vernum exchange.
	Me.TRP_OnProfileChanged()
end

local function UpdateTRPProfile()
	for field, section in pairs( MSP_FIELD_MAP ) do
		UpdateTRPField( field )
	end
	
	BumpVersion( "A", m_section_dirty.A )
	BumpVersion( "B", m_section_dirty.B )
	BumpVersion( "C", m_section_dirty.C )
	BumpVersion( "D", m_section_dirty.D )
	wipe( m_section_dirty )
	
	Me.trp_profile.A.v = Me.msp_cache.ver.A or 1
	Me.trp_profile.B.v = Me.msp_cache.ver.B or 1
	Me.trp_profile.C.v = Me.msp_cache.ver.C or 1
	Me.trp_profile.D.v = Me.msp_cache.ver.D or 1
	
	Me.msp_force_update = false
end
-- goodmorning
-- you need to save those A,B,C,D version numbers somewhere persistent
-- move them to the cache
-- also, this SHIT should not be used if you can communicate normally to osmeone
-- unlike with the trp protocol where the profile data is received exactly.
-- in other words, dont save the trp downgraded to msp if you can communicate
--  trhough whispers, and dont save the msp upgraded to trp if you can communicate
-- through whispers
local m_updated_field = false

-------------------------------------------------------------------------------
local function UpdateMSPField( name, field, value, version )
	value = value or ""
	value = tostring( value )
	if not value then return end
	
	if msp.char[name].field[field] == value then
	  --                 and msp.char[name].ver[field] == version then
		return
	end
	m_updated_field = true
	msp.char[name].field[field] = value
	msp.char[name].time[field] = GetTime()
	--msp.char[name].ver[field] = version
	for _,v in ipairs( msp.callback.updated ) do
		v( name, field, value, nil )--version )
	end
end

-------------------------------------------------------------------------------
local function TriggerReceivedCallback( name )
	for _,v in ipairs( msp.callback.received ) do
		v( name )
	end
end

-------------------------------------------------------------------------------
function MSP_imp.BuildVernum()
	UpdateTRPProfile()
--	local trial = IsTrialAccount() or IsVeteranTrialAccount()
	
	local pieces = {}
--	pieces[Me.VERNUM_CLIENT]       = Me.msp_addon:match( "^%S+" )
--	pieces[Me.VERNUM_VERSION_TEXT] = Me.msp_addon:match( "^%S+%s*(.+)" )
	pieces[Me.VERNUM_PROFILE]      = "[CMSP]" .. Me.fullname
	pieces[Me.VERNUM_CHS_V]        = Me.trp_profile.B.v
	pieces[Me.VERNUM_ABOUT_V]      = Me.trp_profile.D.v
	pieces[Me.VERNUM_MISC_V]       = Me.trp_profile.C.v
	pieces[Me.VERNUM_CHAR_V]       = Me.trp_profile.A.v
--	pieces[Me.VERNUM_TRIAL]        = trial and "1" or "0"
	
	return table.concat( pieces, ":" )
end


-------------------------------------------------------------------------------
function MSP_imp.OnVernum( user, vernum )

	-- Our transfer medium isn't super compatible with MSP's format, so we
	--  don't want to touch any MSP compatibility profile from someone who is
	--                     local. Just walk up and get their profile manually.
	if Me.IsLocal( user.name, true ) then
		return false
	end
	
	local entry = user.name .. "-" .. vernum[Me.VERNUM_PROFILE]
	msp.char[user.name].crossrp = true
	msp.char[user.name].supported = true
	
	Me.DebugLog2( "On MSP Vernum", user.name, vernum )
	
	for i = 1, Me.TRP_UPDATE_SLOTS do
		local vi = Me.VERNUM_CHS_V+i-1
		local mspkey = "CR"..i
		
		-- i ~= 3: we aren't using this section C currently in our msp
		--  implementation.
		Me.DebugLog2( "Vernum check", mspkey, msp.char[user.name].field[mspkey], vernum[vi] )
		if msp.char[user.name].field[mspkey] ~= tostring(vernum[vi]) and i ~= 3 then
			-- TODO: don't forget to update this field!
			Me.DebugLog2( "Set Needs Update", i )
			Me.TRP_SetNeedsUpdate( user.name, i )
		end
	end
	
	return true
end

-------------------------------------------------------------------------------
function MSP_imp.GetExchangeData( section )
	UpdateTRPProfile()
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

local function UpdateFieldsStart()
	m_updated_field = false
end

local function UpdateFieldsEnd( user )
	if m_updated_field then
		TriggerReceivedCallback( user.name )
	end
end

-------------------------------------------------------------------------------
local function SaveCHSData( user, data )
	UpdateFieldsStart()
	UpdateMSPField( user.name, "CR1", data.v )
	
	local va, va2 = data.VA:match( "([^;]+);([^;]*)" )
	if va then 
		-- quirk for xrp
		if va == "Total RP 3" then va = "TotalRP3" end
		va = va .. "/" .. va2
	end
	UpdateMSPField( user.name, "VA", va )
	
	Me.DebugLog2( user.name, data.v, va, data.FN )
	
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
	
	if data.CH and data.CH:match("%x%x%x%x%x%x") then
		fullname = "|cff" .. data.CH .. fullname
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
	
	UpdateFieldsEnd( user )
end

-------------------------------------------------------------------------------
local function SaveAboutData( user, data )
	UpdateFieldsStart()
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
		end)
		
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
	
	UpdateFieldsEnd( user )
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
	UpdateFieldsStart()
	UpdateMSPField( user.name, "CR4", data.v )
	Me.DebugLog2( "MSP Character Data", user.name, data.v, data.CU )
	UpdateMSPField( user.name, "VP", "1" ) -- MSP might need this.
	UpdateMSPField( user.name, "CU", data.CU )
	UpdateMSPField( user.name, "CO", data.CO )
	UpdateMSPField( user.name, "FC", data.RP == 1 and "2" or "1" )
	UpdateMSPField( user.name, "FR", FR_VALUES[ data.XP ] )
	
	UpdateFieldsEnd( user )
end

-------------------------------------------------------------------------------
function MSP_imp.SaveProfileData( user, index, data )
	if index == 1 then -- CHS
		Me.DebugLog('debug1')
		SaveCHSData( user, data )
	elseif index == 2 then -- ABOUT
		SaveAboutData( user, data )
	elseif index == 3 then -- MISC
		-- Nothing to save.
		UpdateFieldsStart()
		UpdateMSPField( user.name, "CR3", data.v )
		UpdateFieldsEnd( user )
	elseif index == 4 then -- CHAR
		SaveCharacterData( user, data )
	end
end

-------------------------------------------------------------------------------
function MSP_imp.IsPlayerKnown( username )
	return msp.char[username].crossrp
end

-------------------------------------------------------------------------------
function MSP_imp.Init()
	--table.insert( msp.callback.updated, OnMSPUpdated )
	table.insert( msp.callback.received, OnMSPReceived )
end

-------------------------------------------------------------------------------
function Me.HookMRP()
	if not mrp then return end
	-- Fixup MRP button.
	mrp.TargetChanged = function( self )
		MyRolePlayButton:Hide()
		if not mrpSaved.Options.Enabled or not mrpSaved.Options.ShowButton 
					                                    or not mrp.Enabled then
			return
		end
		if UnitIsUnit( "player", "target" ) then
			MyRolePlayButton:Show()
		elseif UnitIsPlayer( "target" ) then
			if msp.char[ mrp:UnitNameWithRealm( "target" ) ].supported then
				MyRolePlayButton:Show()
			end
		end
	end
	
	local function fixed_callback( player )
		Me.DebugLog2( "PISS.", player )
		if mrp.Enabled and UnitIsPlayer( "target" )
			   and mrp:UnitNameWithRealm( "target" ) == player then
			MyRolePlayButton:Show()
		end
	end
	
	-- Race condition with OnLogin
	C_Timer.After( 0.1, function()
		for k,v in pairs( msp.callback.received ) do
			if v == mrp_MSPButtonCallback then
				Me.DebugLog2( "Replaced MRP Button Callback." )
				msp.callback.received[k] = fixed_callback
				break
			end
		end
	end)
	
	hooksecurefunc( mrp, "Show", function( self, username )
		if username ~= UnitName("player") then
			Me.TRP_OnProfileOpened( username )
		end
	end)

end

-------------------------------------------------------------------------------
function Me.HookXRP()
	if not xrp then return end
	
	hooksecurefunc( XRPViewer, "View", function( self, player )
		Me.DebugLog2( "XRP On View.", player )
		if not player then return end
		local username
		if UnitExists( player ) then
			username = Me.GetFullName( player )
			if not username then return end
			
		else
			username = player
			-- player name
			if not username:find("-") then
				username = username .. "-" .. Me.realm
			end
		end
		Me.TRP_OnProfileOpened( username )
	end)
end

-------------------------------------------------------------------------------
function Me.MSP_Init()
	if not mrp and not xrp then return end
	
	Me.msp_addon = "unknown"
	local crossrp_version = GetAddOnMetadata( "CrossRP", "Version" )
	if mrp then
		Me.msp_addon = "MyRolePlay;" .. GetAddOnMetadata( "MyRolePlay", 
		                                                            "Version" )
	elseif xrp then
		Me.msp_addon = "XRP;" .. GetAddOnMetadata( "XRP", "Version" )
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
			msp_cache = {
				ver = {}
			};
		}
	end
	local trial = (IsTrialAccount() or IsVeteranTrialAccount()) and "1" or "0"
	local va = Me.msp_addon .. ";" .. trial
	Me.trp_profile = Me.MSP_CreateTRPTemplate( va )
	Me.msp_cache   = Me.db.char.msp_data.msp_cache
	Me.msp_force_update = true
	-- Initialize profile structure.
	--SetupTRPProfile()
	
	Me.HookMRP()
	Me.HookXRP()
end


