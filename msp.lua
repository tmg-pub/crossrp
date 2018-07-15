-------------------------------------------------------------------------------
-- Cross RP
-- by Tammya-MoonGuard (2018)
--
-- All Rights Reserved
--
-- Time to get messy...
-------------------------------------------------------------------------------
local _, Me = ...
local L     = Me.Locale
-------------------------------------------------------------------------------
-- Implementation object. Contains everything for the TRP fallback code.
--
local MSP_imp = {}

-------------------------------------------------------------------------------
-- The way this works, is that we load everything from the MSP side into a TRP
--  profile, transfer that, and then parse it natively by our TRP code, or
--  translate it back down into MSP fields for MSP addons. It's not the
--  prettiest thing in the world, but it allows us to have a clean TRP side at
--  least, where everything is using native functions. After all, TRP is our
--                                  priority when it comes to compatibility.
function Me.MSP_CreateTRPTemplate()
	local trial = (IsTrialAccount() or IsVeteranTrialAccount()) and "1" or "0"
	local va = Me.msp_addon .. ";" .. trial
	
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
			-- This is a non-trp field that should be removed as soon as its 
			--  seen and verified on our end before passing over to the TRP
			--  register. It's similar to MSP'S "VA", but the format or use
			--  isn't entirely the same.
			VA = va;
			
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
			
			-- This secton is overwritten by a template 1 or template 3 block.
			-- T3 is only used when there is both DE and HI present. T1 is
			--  used when there's only one, or when everything is empty.
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

-------------------------------------------------------------------------------
-- We're doing a little bit of public data structure sharing to make the code
--  simpler below. If any field from a section changes when recording MSP
--  changes in the player's side, one of these flags are set, so we can bump
--  the version number in our TRP profile template just once. This might be
--  reconsidered, as you can increment the numbers above plenty of times
--                                                        without much penalty.
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
-- Simple 1-1 mappings of certain values to TRP fields.
-- The field is already indexed by the different sections by the above table.
-- These can also be manually tweaked after the simple copy.
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
	AH = "HE"; -- HEIGHT
	AW = "WE"; -- WEIGHT/SHAPE
}

-------------------------------------------------------------------------------
local function TrimString( value )
	return value:match( "^%s*(.-)%s*$" )
end

-------------------------------------------------------------------------------
-- Rebuilds the MI table in the section B data. These are 
--  "Additional Information" values in the characteristics page. The three
--  supported fields from MSP are NH - House Name, NI - Nickname, and
--                                                       MO - Motto.
local function RebuildAdditionalInfo()
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
-- Rebuilds the About page in the section D data.
--
local function RebuildAboutData()
	local de = TrimString( msp.my.DE or "" )
	local hi = TrimString( msp.my.HI or "" )
	if de ~= "" and hi ~= "" then
		-- Found physical appearance and history. Use template 3.
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
-- Convert centimeters to a localized string for body height.
--
function Me.LocalizeHeight( centimeters )
	if L.HEIGHT_UNIT == "FEETINCHES" then
		local inches = math.floor( centimeters * 0.393701 + 0.5 )
		local feet = math.floor( inches / 12 )
		inches = inches - feet * 12
		return feet .. "'" .. inches .. '"'
	elseif L.HEIGHT_UNIT == "CM" then
		return centimeters .. "cm"
	end
	return centimeters
end

-------------------------------------------------------------------------------
-- Convert kilograms to a localized string for body weight.
--
function Me.LocalizeWeight( kg )
	if L.WEIGHT_UNIT == "POUNDS" then
		return math.floor( kg * 2.20462 + 0.5 ) .. " lbs."
	elseif L.WEIGHT_UNIT == "KG" then
		return kg .. " kg"
	elseif L.WEIGHT_UNIT == "STONESPOUNDS" then
		local pounds = math.floor( kg * 2.20462 + 0.5 )
		local stones = math.floor( pounds / 14 )
		local pounds = pounds - stones * 14
		return stones .. " st " .. pounds .. " lb"
	end
	
	return kg
end

-------------------------------------------------------------------------------
-- Called when a value in the MSP registry is changed - from UpdateTRPProfile.
-- We rely on the msp field to check for changes, and then skip setting values.
--  The first time this runs `msp_force_update` is set, so we can cache
--                      everything into the TRP profile the first time.
local function UpdateTRPField( field )
	local section = MSP_FIELD_MAP[field]
	if not section then return end
	
	-- msp.my returns nil when things aren't found.
	local value = msp.my[field] or ""
	
	-- `msp_cache` is persistent across sections, and only wiped when the user
	--  changes their profile addon or updates Cross RP.
	if Me.msp_cache[field] == value then
		-- Field is up to date, but we might want to do that first-time cache.
		if not Me.msp_force_update then
			return
		end
	else
		m_section_dirty[section] = true
		Me.msp_cache[field] = value
	end
	
	Me.DebugLog2( "Updating MSP field.", field, value )
	
	-- Value or nil.
	local vornil = value
	if value == "" then vornil = nil end
	
	-- Value is a number. Keep in mind that MSP strictly only deals with string
	--  values in its fields.
	local isnumber = value:match( "^[0-9]+$" )
	
	-- The simple map is for copying values directly into the table. We can do
	--  that for most values, and then clean them up a little further below
	--  alongside what needs to be custom-copied.
	local simple = TRP_SIMPLE_MSP_MAP[field]
	if simple then
		Me.trp_profile[section][simple] = vornil
	end
	
	local tv = TrimString(value)
	
	if field == "NA" and tv == "" then
		-- TRP exchange always has name present.
		Me.trp_profile.B.FN = UnitName( "player" )
	elseif field == "RA" and tv == "" then
		-- TRP exchange always has RA and CL present. This is kind of odd
		--  because then we can't do localization on the client end for
		--  default values. Upside is that it doesn't need to depend on the
		--  game to provide that data (MSP has special fields to transfer that
		--  sort of data).
		Me.trp_profile.B.RA = UnitRace( "player" )
	elseif field == "RC" and tv == "" then
		Me.trp_profile.B.CL = UnitClass( "player" )
	elseif field == "DE" or field == "HI" then
		RebuildAboutData()
	elseif field == "FC" then
		-- This isn't confusing at all. :)
		-- "1" in MSP is in-character, which is 2 in TRP. I think...
		Me.trp_profile.A.RP = value == "1" and 2 or 1
	elseif field == "FR" then
		-- "4" is beginner roleplayer in FR.
		Me.trp_profile.A.XP = value == "4" and 1 or 2
	elseif field == "MO" or field == "NI" or field == "NH" then
		-- These are the fields in the middle of the characteristic's page
		--  above personality traits.
		RebuildAdditionalInfo()
	end
	
	-- For height and weight, MSP defines that numbers are fixed units that
	--  should be converted according to locale (and we have L.HEIGHT_UNIT and
	--  L.WEIGHT_UNIT strings for it).
	-- AFAIK TRP doesn't do that, so we have two choices of evil here. One,
	--  localize the values in our end, and hope the recipient is using the
	--  same locale preference (which is likely!). Or two, transfer it as is
	--  and then MSP implementations can handle it properly, while TRP
	--  implementations might show a number value.
	if field == "AH" then
		if isnumber then
			Me.trp_profile.B.HE = Me.LocalizeHeight( value )
		end
	end
	
	if field == "AW" then
		if isnumber then
			Me.trp_profile.B.WE = Me.LocalizeWeight( value )
		end
	end
end

-------------------------------------------------------------------------------
-- If anything changed in one of the sections, this is for incrementing the
--  version number. Version numbers are semi-deprecated, but who knows how far
--  off a new protocol is. `condition` is the section's dirty flag, and this
--                               does nothing if the condition is nil/false.
local function BumpVersion( key, condition )
	if not condition then return end
	local a = (Me.msp_cache.ver[key] or 1)
	a = a + 1
	if a >= 100 then a = 1 end
	Me.msp_cache.ver[key] = a
end

-------------------------------------------------------------------------------
-- This is triggered by LibMSP when the the MSP cache is changed. It's
--  implementation-defined, how many times it might be called when a profile
--  is loaded (might be several times, or once, depending on how msp:Update
--  is used). This is called both for the user's character and other
--  characters.
local function OnMSPReceived( name )
	if name ~= Me.fullname then return end
	
	Me.DebugLog2( "My MSP received." )
	
	-- Schedule vernum exchange. This is safe to spam, as are most things in
	--  the parent side.
	Me.TRP_OnProfileChanged()
end

-------------------------------------------------------------------------------
-- Called whenever we're about to give data to someone. Primps and populates
--  our TRP profile data.
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
	
	-- This is to make sure that the profile is filled at the start; we're not
	--  putting it in save data anymore.
	Me.msp_force_update = false
end

-------------------------------------------------------------------------------
-- Here's where it gets a little messy; we're inserting data into the msp.char
--  fields ourself, and then triggering the callbacks manually. This
--  semi-globalis to keep track of any change when updating fields, and then in
--                         UpdateFieldsEnd it'll trigger the received callback.
local m_updated_field = false

-------------------------------------------------------------------------------
local function UpdateMSPField( name, field, value )
	value = value or ""
	value = tostring( value )
	if not value then return end
	
	if msp.char[name].field[field] == value then
		return
	end
	m_updated_field = true
	msp.char[name].field[field] = value
	msp.char[name].time[field] = GetTime()
	for _,v in ipairs( msp.callback.updated ) do
		-- One scary thing we're doing here is not passing anything for
		--  the version. We don't have it, and we can't really generate it
		--  easily. The good news is that the RP addon should usually not
		--  care about it, as LibMSP should be handling any versioning and 
		--  transfers. The bad news is that it can be cached to help LibMSP
		--  out later. This is one of the reasons why we shut down our MSP
		--      compatibility protocol when dealing with any local players.
		v( name, field, value, nil )
	end
end

-------------------------------------------------------------------------------
-- Helper function to trigger the `received` callback for LibMSP.
--
local function TriggerReceivedCallback( ... )
	for _,v in ipairs( msp.callback.received ) do
		v( ... )
	end
end

-------------------------------------------------------------------------------
-- This needs to build a properly formatted vernum string for the TRP side.
--
function MSP_imp.BuildVernum()
	UpdateTRPProfile()
	
	local pieces = {}
	-- TRP uses a couple of profile name formats. The first is a GUID, which is
	--  <time><random string>. The second is [MSP]<username>. The second always
	--  has `msp` set in the unit ID data (unit ID has special meaning to TRP).
	--  We're introducing a third type [CMSP]<username>, because we have a
	--  number of discrepancies from their MSP compatibility code, especially
	--  regarding versions, and we want to avoid tainting any normal MSP
	--  profile they might have in that slot already. In the end, profile
	--  swapping/selecting is very iffy at the moment in all addons and the
	--  future will revisit this.
	pieces[Me.VERNUM_PROFILE] = "[CMSP]" .. Me.fullname
	
	-- In an ideal world we would have rearranged our profile bits to be
	--  A,B,C,D in the vernum too. /shrug
	pieces[Me.VERNUM_CHS_V]   = Me.trp_profile.B.v
	pieces[Me.VERNUM_ABOUT_V] = Me.trp_profile.D.v
	pieces[Me.VERNUM_MISC_V]  = Me.trp_profile.C.v
	pieces[Me.VERNUM_CHAR_V]  = Me.trp_profile.A.v
	
	return table.concat( pieces, ":" )
end

-------------------------------------------------------------------------------
-- Triggered when we receive a vernum (TV) message in the relay. This should
--  return true if we accept it as a valid client, and false if we want to
--  reject it.
function MSP_imp.OnVernum( user, vernum )

	-- Our transfer medium isn't super compatible with MSP's format, so we
	--  don't want to touch any MSP compatibility profile from someone who is
	--                     local. Just walk up and get their profile manually.
	if Me.IsLocal( user.name, true ) then
		Me.DebugLog( "MSP ignoring local user." )
		return false
	end
	
	if not msp.char[user.name].supported then
		msp.char[user.name].supported = true
		
		-- Give them something to look at while the real version loads.
		UpdateMSPField( user.name, "VA", "CrossRP/"
		    .. GetAddOnMetadata( "CrossRP", "Version" ) )
	end
	msp.char[user.name].crossrp = true
	
	for i = 1, Me.TRP_UPDATE_SLOTS do
		local vi = Me.VERNUM_CHS_V+i-1
		local mspkey = "CR"..i
		
		-- Doing a simple block in here against section C (3/misc), since our
		--  MSP implementation doesn't use any fields from there right now.
		--  That contains the at-first glances and RP preferences in TRP.
		if msp.char[user.name].field[mspkey] ~= tostring(vernum[vi])
		                                                      and i ~= 3 then
			--Me.DebugLog2( "Set Needs Update", i )
			Me.TRP_SetNeedsUpdate( user.name, i )
		end
	end
	
	if Me.TRP_needs_update[user.name] then
		Me.DebugLog( "MSP needs updates: %s%s%s%s",
			 Me.TRP_needs_update[user.name][1] and "1" or "0",
			 Me.TRP_needs_update[user.name][2] and "1" or "0",
			 Me.TRP_needs_update[user.name][3] and "1" or "0",
			 Me.TRP_needs_update[user.name][4] and "1" or "0")
	else
		Me.DebugLog( "MSP no update needed." )
	end
	
	return true
end

-------------------------------------------------------------------------------
-- Returns our generated TRP profile data.
--
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
-- Searches through the "Additional information" data in a TRP profile for
--  a key, and then returns the value for it if found. `data` is section B.
--
local function GetMIString( data, name )
	for k,v in pairs( data.MI or {} ) do
		if v.NA:lower() == name then
			return v.VA
		end
	end
end

-------------------------------------------------------------------------------
-- Called when we're about to update our MSP data. Finished with 
--  UpdateFieldsEnd, when we're all done changing everything, which will
--                                            trigger the `received` callback.
local function UpdateFieldsStart()
	m_updated_field = false
end

local function UpdateFieldsEnd( user )
	-- This is a semi-global passed around by the MSP updating functions for
	--  ease of use.
	if m_updated_field then
		TriggerReceivedCallback( user.name )
	end
end

-------------------------------------------------------------------------------
-- Builds the NA field from TRP data.
--
local function PullName( user, data )
	-- Fields in the TRP profile (section B) are
	-- TI: Title
	-- FN: First Name
	-- LN: Last Name
	-- CH: Color Code
	-- Basically concatenate everything safely.
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
	
	-- TRP does this too when translating for MSP. Applies the color code
	--  directly to the NA field as an escape sequence. We do a little check
	--  too, to make sure that it's a valid color we received.
	if data.CH and data.CH:match("%x%x%x%x%x%x") then
		fullname = "|cff" .. data.CH .. fullname
	end
	
	return fullname
end

-------------------------------------------------------------------------------
-- Read the characteristics data (section B) from the profile received and copy
--                                                    data into the MSP fields.
local function SaveCHSData( user, data )
	UpdateFieldsStart()
	UpdateMSPField( user.name, "CR1", data.v )
	
	-- VA is a special field we add for transferring the RP addon version. This
	--  was originally in the vernum data, but we moved it into here to save
	--  on vernum spam. It's not formatted the same as MSP's VA. This is
	--  "ADDONNAME;VERSION;TRIAL" where TRIAL is 1/0 if they're a trial
	--  account.
	local va, va2 = data.VA:match( "([^;]+);([^;]*)" )
	if va then 
		-- MRP/XRP only recognizes "TotalRP3" without spaces to think it's TRP.
		-- TRP saves it like that in the actual VA field for MSP.
		if va == "Total RP 3" then va = "TotalRP3" end
		va = va .. "/" .. va2
	end
	UpdateMSPField( user.name, "VA", va )
	
	-- Name, Title, Icon, Race, Class, Height, Age, Eye Color, Weight,
	--  Birthplace, Residence, Motto, Nickname, House Name.
	UpdateMSPField( user.name, "NA", PullName( user, data ))
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
	UpdateMSPField( user.name, "MO", GetMIString( data, "motto"      ))
	UpdateMSPField( user.name, "NI", GetMIString( data, "nickname"   ))
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
		
		-- * Remind the TRP authors that this is how it should be done so you
		--            don't lose the link entirely when translating for MSP.
		-- "{link*http://your.url.here*Your text here}"
		text = text:gsub( "{link%*([^*])%*([^}])}", function( link, text )
			return link .. "(" .. text .. ")"
		end)
		
		-- Kill all other tags in the text.
		text = text:gsub( "{[^}]*}", "" )
		
		UpdateMSPField( user.name, "DE", text )
		UpdateMSPField( user.name, "HI", "" )
		
	elseif data.TE == 2 then
		-- Template 2
		-- AFAIK template 2 might have some {formatting} allowed if you insert
		--  it manually, but the TRP code doesn't clean anything for it when
		--  converting template 2 for MSP.
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
		-- MSP compatible template.
		UpdateMSPField( user.name, "DE", data.T3.PH.TX )
		UpdateMSPField( user.name, "HI", data.T3.HI.TX )
	end
	
	UpdateFieldsEnd( user )
end

-------------------------------------------------------------------------------
-- Maybe these should be localized? Not sure if something might depend on them
--  to be keys.
local FR_VALUES = {
	[1] = "Beginner roleplayer";
	[2] = "Experienced roleplayer";
	[3] = "Volunteer roleplayer";
}

-------------------------------------------------------------------------------
-- By "character" I don't mean a generic character. Character is a section
--  in the TRP profile.
local function SaveCharacterData( user, data )
	UpdateFieldsStart()
	UpdateMSPField( user.name, "CR4", data.v )
	Me.DebugLog2( "MSP Character Data", user.name, data.v, data.CU )
	
	-- Protocol version. MSP might want to see this. LibMSP currently has this
	--  set to "3", but we're not exactly a full implementation, so we'll stick
	--  with a meek "1".
	UpdateMSPField( user.name, "VP", "1" )
	
	-- Currently, Currently OOC, IC status, Experience.
	UpdateMSPField( user.name, "CU", data.CU )
	UpdateMSPField( user.name, "CO", data.CO )
	UpdateMSPField( user.name, "FC", data.RP == 1 and "2" or "1" )
	UpdateMSPField( user.name, "FR", FR_VALUES[ data.XP ] )
	
	UpdateFieldsEnd( user )
end

-------------------------------------------------------------------------------
-- Called when we receive a TRPD message. This also respects our choices when
--             dealing with the vernum and blocking clients when they're local.
function MSP_imp.SaveProfileData( user, index, data )
	if index == 1 then -- CHS
		-- Characteristics.
		SaveCHSData( user, data )
	elseif index == 2 then -- ABOUT
		-- About.
		SaveAboutData( user, data )
	elseif index == 3 then
		-- Misc. We don't use anything from here, but update the version
		--  number for prudence. (AFAIK there's no effect, but just in case?)
		UpdateFieldsStart()
		UpdateMSPField( user.name, "CR3", data.v )
		UpdateFieldsEnd( user )
	elseif index == 4 then
		-- Character.
		SaveCharacterData( user, data )
	end
end

-------------------------------------------------------------------------------
-- Called when the parent wants to know if we know about this username in our
--  end. `crossrp` is a special field inserted when we receive any data from
--  them through crossrp. This is kind of a weird way to go about this. The
--  TRP implementation just checks if they're a valid profile in the TRP
--  registry, but we're a little more picky, and don't want to be messing with
--  anything non-Cross RP from in this module.
function MSP_imp.IsPlayerKnown( username )
	return msp.char[username].crossrp
end

-------------------------------------------------------------------------------
-- Called on Player Login. Something to worry about here is the received
--  callback race condition where we might miss the initial profile update.
--  AFAIK the new way we go about updating the TRP profile should take care of
--  that though. HOWEVER, there's also the opposite end of the race condition,
--  where we might see a bunch of junk get assigned to msp.my before the real 
--  data gets assigned. If we want to go for super-safety, we might need a 
--                                                       delay for this.
function MSP_imp.Init()
	table.insert( msp.callback.received, OnMSPReceived )
end

-------------------------------------------------------------------------------
-- Hooks and hacks for MyRolePlay.
--
function Me.HookMRP()
	if not mrp then return end
	-- This will probably be fixed soon in MyRolePlay, but currently the MRP
	--  button doesn't show up when you target someone of the opposing faction.
	--  MRP does otherwise work cross-faction with Chomp and Battle.net
	--  messages. We're basically re-implementing a couple of these functions
	--                               ourself. Not the most future-proof stuff.
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
		-- There's a few extra checks in here from the original handler, but
		--  that's because we don't support unhooking when MRP disables itself.
		if mrp.Enabled and UnitIsPlayer( "target" )
			   and mrp:UnitNameWithRealm( "target" ) == player then
			MyRolePlayButton:Show()
		end
	end
	
	-- There's a race condition here with PLAYER_LOGIN, where MRP also sets
	--  up its hooks, so delay a little bit.
	C_Timer.After( 0.1, function()
		for k,v in pairs( msp.callback.received ) do
			if v == mrp_MSPButtonCallback then
				Me.DebugLog2( "Replaced MRP Button Callback." )
				msp.callback.received[k] = fixed_callback
				break
			end
		end
	end)
	
	-- When the profile page opens, we need to do this to transfer the
	--                                         remaining bits of their profile.
	hooksecurefunc( mrp, "Show", function( self, username )
		if username ~= UnitName("player") then
			Me.TRP_OnProfileOpened( username )
		end
	end)
end

-------------------------------------------------------------------------------
-- Hooks and hacks for XRP Roleplay Profiles.
--
function Me.HookXRP()
	if not xrp then return end
	
	hooksecurefunc( XRPViewer, "View", function( self, player )
		Me.DebugLog2( "XRP On View.", player )
		if not player then return end
		
		-- This function can be called with either a unit name or a player
		--  name. The realm is also optional, or at least it is when using the
		--  command line.
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
-- GnomeTEC Badge
--
function Me.HookGnomTEC()
	if not GnomTEC_Badge then return end
	
	MSP_imp.OnTargetChanged = function()
		Me.TRP_OnProfileOpened( Me.GetFullName( "target" ) )
	end
end

function MSP_imp.OnTargetChanged() end

-------------------------------------------------------------------------------
-- Things in here are initialized before the TRP side, so we can set up the
--  TRP_imp structure and such.
function Me.MSP_Init()
	if TRP3_API then return end -- Don't use any of this if we have TRP loaded.
	
	if not mrp and not xrp and not GnomTEC_Badge then return end
	
	local crossrp_version = GetAddOnMetadata( "CrossRP", "Version" )
	if mrp then
		Me.msp_addon = "MyRolePlay;" .. GetAddOnMetadata( "MyRolePlay", 
		                                                            "Version" )
	elseif xrp then
		Me.msp_addon = "XRP;" .. GetAddOnMetadata( "XRP", "Version" )
	elseif GnomTEC_Badge then
		Me.msp_addon = "GnomTEC_Badge;" 
		                     .. GetAddOnMetadata( "GnomTEC_Badge", "Version" )
	else
		return
	end
	Me.DebugLog2( "Compatible profile addon version", Me.msp_addon )
	Me.TRP_imp = MSP_imp
	
	-- We use a simple cache for the version numbers and fields, so we know
	--  what hasn't changed and shouldn't be re-sent across sessions. The
	--  target user still needs a cache in their RP addon for MSP fields for
	--  it to not resend data. This works for TRP and XRP at least. MRP doesn't
	--                                                          have a cache.
	if not Me.db.char.msp_data 
	            or Me.db.char.msp_data.addon ~= Me.msp_addon 
				         or Me.db.char.msp_data.crossrp ~= crossrp_version then
		-- If there's any mismatch in versions, we wipe this table. It's just
		--  cache data anyway, so clearing it outright doesn't have any serious
		--  implications.
		Me.db.char.msp_data = {
			addon   = Me.msp_addon;
			crossrp = crossrp_version;
			msp_cache = {
				ver = {}
			};
		}
	end
	
	-- `trp_profile` is what we upgrade our MSP data into so it can be
	--  transferred. Everything uses a TRP-like protocol so we can stay as
	--  native as possible with TRP-users, while having the MSP end as more
	--  of a compatibility thing.
	Me.trp_profile = Me.MSP_CreateTRPTemplate()
	Me.msp_cache   = Me.db.char.msp_data.msp_cache
	
	-- This causes the first profile update to cache everything into the 
	--  TRP profile. I'm not too sold on this approach, and maybe we should
	--  just always update when we see anything changed (and the version cache
	--                  or checks are purely just so we don't bump our vernum).
	Me.msp_force_update = true
	
	Me.HookMRP()
	Me.HookXRP()
	Me.HookGnomTEC()
end
