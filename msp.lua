-------------------------------------------------------------------------------
-- Cross RP
-- by Tammya-MoonGuard (2019)
--
-- Time to get messy...
-------------------------------------------------------------------------------
local _, Me = ...
local L     = Me.Locale
local TRP   = Me.TRP

-------------------------------------------------------------------------------
local MSP = {

	-- Contains our implementation functions for loading/saving profiles.
	Impl = {};
}
Me.MSP = MSP

-------------------------------------------------------------------------------
local m_trp_profile
local m_msp_cache
local m_msp_force_update

-------------------------------------------------------------------------------
-- The way this works, is that we load everything from the MSP side into a TRP
--  profile, transfer that, and then parse it natively by our TRP code, or
--  translate it back down into MSP fields for MSP addons. It's not the
--  prettiest thing in the world, but it allows us to have a clean TRP side at
--  least, where everything is using native functions. After all, TRP is our
--                                  priority when it comes to compatibility.
local function CreateTRPTemplate()
	CreateTRPTemplate = nil
	
	local trial = (IsTrialAccount() or IsVeteranTrialAccount()) and "1" or "0"
	local va = MSP.addon .. ";" .. trial
	
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
-- MSP requires these to be exactly two uppercase letters, and XRP enforces
--  that standard. I wish I could use numbers. These are special custom fields
--  that hold our versioning information. Maybe in the future these could be
--  stored directly in one of the valid fields, rather than using these.
local VERSION_KEYS = { "VH", "VI", "VJ", "VK" }

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
	local data = m_trp_profile.B.MI
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
		m_trp_profile.D.TE = 3
		m_trp_profile.D.T1 = nil
		m_trp_profile.D.T3 = {
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
		m_trp_profile.D.TE = 1
		m_trp_profile.D.T1 = {
			TX = tx
		}
		m_trp_profile.D.T3 = nil
	end
end

-------------------------------------------------------------------------------
-- Convert centimeters to a localized string for body height.
--
local function LocalizeHeight( centimeters )
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
local function LocalizeWeight( kg )
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
	if m_msp_cache[field] == value then
		-- Field is up to date, but we might want to do that first-time cache.
		if not m_msp_force_update then
			return
		end
	else
		m_section_dirty[section] = true
		m_msp_cache[field] = value
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
		m_trp_profile[section][simple] = vornil
	end
	
	local tv = TrimString(value)
	
	if field == "NA" and tv == "" then
		-- TRP exchange always has name present.
		m_trp_profile.B.FN = UnitName( "player" )
	elseif field == "RA" and tv == "" then
		-- TRP exchange always has RA and CL present. This is kind of odd
		--  because then we can't do localization on the client end for
		--  default values. Upside is that it doesn't need to depend on the
		--  game to provide that data (MSP has special fields to transfer that
		--  sort of data).
		m_trp_profile.B.RA = UnitRace( "player" )
	elseif field == "RC" and tv == "" then
		m_trp_profile.B.CL = UnitClass( "player" )
	elseif field == "DE" or field == "HI" then
		RebuildAboutData()
	elseif field == "FC" then
		-- This isn't confusing at all. :)
		-- "1" in MSP is in-character, which is 2 in TRP. I think...
		m_trp_profile.A.RP = value == "1" and 2 or 1
	elseif field == "FR" then
		-- "4" is beginner roleplayer in FR.
		m_trp_profile.A.XP = value == "4" and 1 or 2
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
			m_trp_profile.B.HE = LocalizeHeight( value )
		end
	end
	
	if field == "AW" then
		if isnumber then
			m_trp_profile.B.WE = LocalizeWeight( value )
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
	local a = (m_msp_cache.ver[key] or 0)
	a = a + 1
	if a >= 100 then a = 1 end
	m_msp_cache.ver[key] = a
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
	--Me.TRP.OnProfileChanged()
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
	
	m_trp_profile.A.v = m_msp_cache.ver.A or 1
	m_trp_profile.B.v = m_msp_cache.ver.B or 1
	m_trp_profile.C.v = m_msp_cache.ver.C or 1
	m_trp_profile.D.v = m_msp_cache.ver.D or 1
	
	-- This is to make sure that the profile is filled at the start; we're not
	--  putting it in save data anymore.
	m_msp_force_update = false
end

-------------------------------------------------------------------------------
-- Here's where it gets a little messy; we're inserting data into the msp.char
--  fields ourself, and then triggering the callbacks manually. This
--  semi-global is to keep track of any change when updating fields, and then
--                      in UpdateFieldsEnd it'll trigger the received callback.
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
		-- One scary thing we're doing here is not having a proper version
		--  value. We don't have it, and we can't really generate it easily.
		--  The good news is that the RP addon should usually not care about
		--  it, as LibMSP should be handling any versioning and transfers.
		--  The bad news is that it can be cached to help LibMSP out later. 
		--  This is one of the reasons why we shut down our MSP compatibility
		--  protocol when dealing with any local players.
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

local function UpdateFieldsEnd( username )
	-- This is a semi-global passed around by the MSP updating functions for
	--  ease of use.
	if m_updated_field then
		TriggerReceivedCallback( username )
	end
end

-------------------------------------------------------------------------------
-- Builds the NA field from TRP data.
--
local function PullName( username, data )
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
		firstname = username:match( "^[^%-]*" )
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
local function SaveCHSData( username, data )
	UpdateFieldsStart()
	UpdateMSPField( username, VERSION_KEYS[2], data.v )
	
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
	UpdateMSPField( username, "VA", va )
	
	-- Name, Title, Icon, Race, Class, Height, Age, Eye Color, Weight,
	--  Birthplace, Residence, Motto, Nickname, House Name.
	UpdateMSPField( username, "NA", PullName( username, data ))
	UpdateMSPField( username, "NT", data.FT  )
	UpdateMSPField( username, "IC", data.IC  )
	UpdateMSPField( username, "RA", data.RA  )
	UpdateMSPField( username, "RC", data.CL  )
	UpdateMSPField( username, "AH", data.HE  )
	UpdateMSPField( username, "AG", data.AG  )
	UpdateMSPField( username, "AE", data.EC  )
	UpdateMSPField( username, "AW", data.WE  )
	UpdateMSPField( username, "HB", data.BP  )
	UpdateMSPField( username, "HH", data.RE  )
	UpdateMSPField( username, "MO", GetMIString( data, "motto"      ))
	UpdateMSPField( username, "NI", GetMIString( data, "nickname"   ))
	UpdateMSPField( username, "NH", GetMIString( data, "house name" ))
	
	UpdateFieldsEnd( username )
end

-------------------------------------------------------------------------------
local function SaveAboutData( username, data )
	UpdateFieldsStart()
	-- Some of the code below might error, so we want to make sure that we save
	--  the version first and foremost so nobody is going to be re-transferring
	--  their profile again and again due to it not being able to be saved.
	UpdateMSPField( username, VERSION_KEYS[4], data.v )
	
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
		
		UpdateMSPField( username, "DE", text )
		UpdateMSPField( username, "HI", "" )
		
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
		UpdateMSPField( username, "DE", text )
		UpdateMSPField( username, "HI", "" )
		
	elseif data.TE == 3 then
		-- Template 3
		-- MSP compatible template.
		UpdateMSPField( username, "DE", data.T3.PH.TX )
		UpdateMSPField( username, "HI", data.T3.HI.TX )
	end
	
	UpdateFieldsEnd( username )
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
local function SaveCharacterData( username, data )
	UpdateFieldsStart()
	UpdateMSPField( username, VERSION_KEYS[1], data.v )
	
	-- Protocol version. MSP might want to see this. LibMSP currently has this
	--  set to "3", but we're not exactly a full implementation, so we'll stick
	--  with a meek "1".
	UpdateMSPField( username, "VP", "1" )
	
	-- Currently, Currently OOC, IC status, Experience.
	UpdateMSPField( username, "CU", data.CU )
	UpdateMSPField( username, "CO", data.CO )
	UpdateMSPField( username, "FC", data.RP == 1 and "2" or "1" )
	UpdateMSPField( username, "FR", FR_VALUES[ data.XP ] )
	
	UpdateFieldsEnd( username )
end

-------------------------------------------------------------------------------
-- PROFILE IMPLEMENTATION
-------------------------------------------------------------------------------
-- Returns our version numbers for a user, or nil if we don't know them.
-- These are stored in nonstandard MSP fields. XRP caches them while other
--                             MSP addons still offer this as session storage.
function MSP.Impl.GetVersions( username )
	if not msp.char[username].supported then return end
	
	local fields = msp.char[username].field
	if not fields[VERSION_KEYS[1]] then return end
	
	local a,b,c,d = fields[VERSION_KEYS[1]], fields[VERSION_KEYS[2]],
	                fields[VERSION_KEYS[3]], fields[VERSION_KEYS[4]]

	-- MSP stores all empty fields as empty strings "" instead.
	if a == "" then a = nil end
	if b == "" then b = nil end
	if c == "" then c = nil end
	if d == "" then d = nil end
	
	return { tonumber(a), tonumber(b), tonumber(c), tonumber(d) }, "[CMSP]" .. username
end

-------------------------------------------------------------------------------
-- Returns our version numbers. MSP doesn't actually have the version numbers
--  we need, so we have additional data tracked when profile data changes.
function MSP.Impl.GetMyVersions()
	UpdateTRPProfile()
	return {
		tonumber(m_msp_cache.ver.A or 1);
		tonumber(m_msp_cache.ver.B or 1);
		tonumber(m_msp_cache.ver.C or 1);
		tonumber(m_msp_cache.ver.D or 1);
	}, "[CMSP]" .. Me.fullname
end

-------------------------------------------------------------------------------
-- Simple wrapper to turn our name into a profile ID, as our implementation
--  doesn't actually use profile IDs, and the character name is the ID.
function MSP.Impl.GetMyProfileID()
	return "[CMSP]" .. Me.fullname
end

-------------------------------------------------------------------------------
-- Returns our generated TRP profile data. All of our MSP data is upgraded into
--                our TRP data struct for transferring to other Cross RP users.
function MSP.Impl.GetExchangeData( part )
	UpdateTRPProfile()
	
	if part == 1 then
		return m_trp_profile.A
	elseif part == 2 then
		return m_trp_profile.B
	elseif part == 3 then
		return m_trp_profile.C
	elseif part == 4 then
		return m_trp_profile.D
	end
end

-------------------------------------------------------------------------------
-- Implementation specific method for when we receive profile data from
--  someone. For our MSP implementation, the profile_id is ignored, and we
--  just downgrade the TRP data received into MSP fields and put it in the MSP
--  storage.
function MSP.Impl.SaveExchangeData( username, profile_id, part, data )
	if part == 1 then
		-- Character.
		SaveCharacterData( username, data )
	elseif part == 2 then -- CHS
		-- Characteristics.
		SaveCHSData( username, data )
	elseif part == 3 then
		-- Misc. We don't use anything from here, but update the version
		--  number for prudence. (AFAIK there's no effect, but just in case?)
		UpdateFieldsStart()
		UpdateMSPField( username, VERSION_KEYS[3], data.v )
		UpdateFieldsEnd( username )
	elseif part == 4 then -- ABOUT
		-- About.
		SaveAboutData( username, data )
	end
	
	if not msp.char[username].supported then
		msp.char[username].supported = true
		-- todo: set temporary version here?
	end
end

-------------------------------------------------------------------------------
-- Not using this for anything.
function MSP.Impl.OnTargetChanged()
end


-------------------------------------------------------------------------------
-- Called on Player Login. Something to worry about here is the received
--  callback race condition where we might miss the initial profile update.
--  AFAIK the new way we go about updating the TRP profile should take care of
--  that though. HOWEVER, there's also the opposite end of the race condition,
--  where we might see a bunch of junk get assigned to msp.my before the real 
--  data gets assigned. If we want to go for super-safety, we might need a 
--                                                       delay for this.
function MSP.Impl.Init()
	table.insert( msp.callback.received, OnMSPReceived )
end

-------------------------------------------------------------------------------
-- Hooks and hacks for MyRolePlay.
--
function MSP.HookMRP()
	if not mrp then return end
	
	-- When the profile page opens, we need to do this to transfer the
	--                                         remaining bits of their profile.
	hooksecurefunc( mrp, "Show", function( self, username )
		if username ~= UnitName("player") then
			TRP.OnProfileOpened( username )
		end
	end)
	
end

-------------------------------------------------------------------------------
-- Hooks and hacks for XRP Roleplay Profiles.
--
function MSP.HookXRP()
	if not xrp and not AddOn_XRP then return end
	-- This should be compatible with pre and post XRP 2.0
	-- The Notes panel has an attribute called "character" that's updated with
	--  a reference to the current character data being viewed. `id` is the
	--  player name.
	XRPViewer.Notes:HookScript( "OnAttributeChanged", 
		function( self, key, character )
			if key ~= "character" then return end
			
			local username = character.id
			Me.DebugLog2( "XRP On View.", username )
			if not username then return end
			
			if not username:find("-") then
				username = username .. "-" .. Me.realm
			end
			
			if username == Me.fullname then return end
			
			TRP.OnProfileOpened( username )
		end)
end

-------------------------------------------------------------------------------
-- GnomeTEC Badge
--
function MSP.HookGnomTEC()
	if not GnomTEC_Badge then return end
	
	-- GnomeTEC views the main profile payload whenever you target someone, so
	--  this will be transferring the entire profile when someone is targeted.
	-- Ideally, and with the other implementations, OnProfileOpened is only 
	--  called after a conscious user action to open the profile page.
	MSP.Impl.OnTargetChanged = function()
		if UnitIsPlayer( "target" ) then
			TRP.OnProfileOpened( Me.GetFullName( "target" ))
		end
	end
end

-------------------------------------------------------------------------------
-- Things in here are initialized before the TRP side, so we can set up the
--  TRP_imp structure and such.
function MSP.Init()
	if TRP3_API then return end -- Don't use any of this if we have TRP loaded.
	
	local crossrp_version = Me.version
	if mrp then
		MSP.addon = "MyRolePlay;" .. GetAddOnMetadata( "MyRolePlay", 
		                                                            "Version" )
	elseif xrp or AddOn_XRP then
		MSP.addon = "XRP;" .. GetAddOnMetadata( "XRP", "Version" )
	elseif GnomTEC_Badge then
		MSP.addon = "GnomTEC_Badge;" 
		                     .. GetAddOnMetadata( "GnomTEC_Badge", "Version" )
	else
		return
	end
	
	--msp.my.VA = (msp.my.VA or "") .. "Cross RP"
	Me.DebugLog2( "Compatible profile addon version", MSP.addon )
	TRP.SetImplementation( MSP.Impl )
	
	-- We use a simple cache for the version numbers and fields, so we know
	--  what hasn't changed and shouldn't be re-sent across sessions. The
	--  target user still needs a cache in their RP addon for MSP fields for
	--  it to not resend data. This works for TRP and XRP at least. MRP doesn't
	--                                                          have a cache.
	if not Me.db.char.msp_data 
	            or Me.db.char.msp_data.addon ~= MSP.addon 
				         or Me.db.char.msp_data.crossrp ~= crossrp_version then
		-- If there's any mismatch in versions, we wipe this table. It's just
		--  cache data anyway, so clearing it outright doesn't have any serious
		--  implications.
		Me.db.char.msp_data = {
			addon   = MSP.addon;
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
	m_trp_profile   = CreateTRPTemplate()
	MSP.trp_profile = m_trp_profile
	m_msp_cache     = Me.db.char.msp_data.msp_cache
	MSP.msp_cache   = m_msp_cache
	
	-- This causes the first profile update to cache everything into the 
	--  TRP profile. I'm not too sold on this approach, and maybe we should
	--  just always update when we see anything changed (and the version cache
	--                  or checks are purely just so we don't bump our vernum).
	m_msp_force_update = true
	
	MSP.HookMRP()
	MSP.HookXRP()
	MSP.HookGnomTEC()
end
