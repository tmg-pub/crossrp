-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2019)
--
-- TRP sharing protocol.
--
-- Please note that while this is all my code below, the data 
--  structures/formats used are the TRP3 authors' work. Ideally we would have a
--  more flexible format, but this way is extra safe for TRP3 users. For MSP 
--  compatiblity, we actually upgrade the MSP data into TRP3 data, transfer it,
--  and then downgrade it for MSP clients, or use it as-is for TRP3 clients.
-- MSP compatibility is done through TRP_imp, which basically delegates the
--  implementation-defined bits to whatever wants to implement them. The MSP
--  implemenation is written in msp.lua.
-------------------------------------------------------------------------------

local _, Me = ...
local G     = _G
local L     = Me.Locale
local TRP   = {
	MyImpl = {}
}
Me.TRP = TRP

-------------------------------------------------------------------------------
-- Function caching definitions here. Done so that we avoid table lookups for
--  every function call.
local TryRequest, 
    IsLocal, GetFullName, 
	TRP3_API, TRP3_Globals, TRP3_IsUnitIDKnown, TRP3_GetUnitIDProfile,
	TRP3_GetProfile, TRP3_ProfileExists, TRP3_GetPlayerCurrentProfileID,
	TRP3_GetPlayerCurrentProfile, TRP3_GetData,
    UnitFactionGroup
	
local TRP3_INFO_TYPES 

TRP3_API = _G.TRP3_API -- (Might need this before things are cached.)
-------------------------------------------------------------------------------
function TRP.CacheRefs()
	TryRequest  = TRP.TryRequest
	
	IsLocal, GetFullName = Me.IsLocal, Me.GetFullName
	
	if _G.TRP3_API then
		TRP3_API                       = _G.TRP3_API
		TRP3_Globals                   = TRP3_API.globals
		
		TRP3_IsUnitIDKnown             = TRP3_API.register.isUnitIDKnown
		TRP3_GetUnitIDProfile          = TRP3_API.register.getUnitIDProfile
		TRP3_GetProfile                = TRP3_API.register.getProfile
		TRP3_ProfileExists             = TRP3_API.register.profileExists
		TRP3_GetPlayerCurrentProfileID = TRP3_API.profile.getPlayerCurrentProfileID
		TRP3_GetPlayerCurrentProfile   = TRP3_API.profile.getPlayerCurrentProfile
		TRP3_GetData                   = TRP3_API.profile.getData
		
		TRP3_INFO_TYPES = {
			TRP3_API.register.registerInfoTypes.CHARACTER;
			TRP3_API.register.registerInfoTypes.CHARACTERISTICS;
			TRP3_API.register.registerInfoTypes.MISC;
			TRP3_API.register.registerInfoTypes.ABOUT;
		}
	end
	
	UnitFactionGroup = _G.UnitFactionGroup
end

-- sections we have:
-- 1: tooltip (TRP CHAR) update on mouseover
-- 2: brief (TRP CHS) update on mouseover
-- 3: misc (TRP MISC) update on target
-- 4: full profile (TRP ABOUT) update on inspect

-------------------------------------------------------------------------------
-- TIMING
-------------------------------------------------------------------------------
-- A profile part can only be requested from a user this often. This is per
--  part requested, and per user.
local REQUEST_COOLDOWN = 30.0
-------------------------------------------------------------------------------
-- We will only respond to someone's request this often. This is per part, so
--  they can make a few requests at around the same time, so long as they're
--  for different parts.
local SEND_COOLDOWN = 25.0
-------------------------------------------------------------------------------
-- The last time we requested data from someone, so we can enforce the
--  cooldown above `REQUEST_COOLDOWN`.
-- Indexed as [FULLNAME..PART]
local m_request_times = {}
-------------------------------------------------------------------------------
-- An entry is added into here when we make a profile request from someone.
-- The key is [FULLNAME..PART], and the value is a unique ID. We transfer this
--  ID, and then when we get a profile response from someone, they need to
--  mirror it (and then we close the slot, when we get their data). This is to
--  deter malicious users from overwriting data in our registry when we aren't
--                                                           making a request.
local m_request_slots = {}
-------------------------------------------------------------------------------
-- Incrementing number to generate unique IDs for request slots.
local m_next_request_slot = 1
-------------------------------------------------------------------------------
-- The last time we sent data to someone, so we can enforce the cooldown above
--  `SEND_COOLDOWN`
-- Indexed as [FULLNAME..PART], i.e. time that we sent profile PART to 
--  FULLNAME.
local m_send_times = {}
-------------------------------------------------------------------------------
-- This module is called TRP because originally it was more tightly integrated
--  with TRP3. Now, all profile interfacing is implemented through here. See
--  MyImpl functions below for the implementation for TRP3. msp.lua has the 
--                                            implementation for MSP users.
local m_imp = nil
-------------------------------------------------------------------------------
-- Utility functions to escape TPR profile ID strings. Newer versions of TRP
--  don't use special characters in their generated profile strings, but older
--  versions have, and users may still have an old profile ID with special
--  characters in it, so we need to escape those when transferring.
-- We're doing a bit more than what's necessary with our protocol, but this is
--  so we're compatible in case we switch back to a strict text protocol.
-- This is what characters are escaped:
local PROFILE_ESCAPE_CHARS = { "|", "\\", ":", "~", " " }

-- Populating the two maps to convert to and from escaped characters:
-- e.g. "|" -> "~1" in one table, and then "~1" -> "|" in the other.
local PROFILE_ESCAPE_MAP, PROFILE_UNESCAPE_MAP = {}, {}
for k, v in pairs( PROFILE_ESCAPE_CHARS ) do
	PROFILE_ESCAPE_MAP[v] = "~" .. k
	PROFILE_UNESCAPE_MAP["~" .. k] = v
end
-- Convert our character set to a Lua pattern for gsub.
PROFILE_ESCAPE_CHARS = "[" .. table.concat( PROFILE_ESCAPE_CHARS ) .. "]"
-- Result:
--   PROFILE_ESCAPE_CHARS  Lua pattern to match characters to be escaped.
--   PROFILE_ESCAPE_MAP    Map of normal -> escaped character.
--   PROFILE_UNESCAPE_MAP  Map of escaped character -> normal.

-------------------------------------------------------------------------------
-- Escape special characters from a profile ID.
--
function TRP.EscapeProfileID( text )
	return text:gsub( PROFILE_ESCAPE_CHARS, function( ch )
		return PROFILE_ESCAPE_MAP[ch]
	end)
end

-------------------------------------------------------------------------------
-- Restore special characters to an escaped profile ID.
--
function TRP.UnescapeProfileID( text )
	return text:gsub( "~[1-9]", function( ch )
		return PROFILE_UNESCAPE_MAP[ch]
	end)
end

-------------------------------------------------------------------------------
-- PROFILE IMPLEMENTATION
-------------------------------------------------------------------------------
-- This returns the versions of a profile in our registry. That is: a table
--  of version numbers for someone's four profile sections. Also returns our
--  profile ID, which is like a master version number. This is to populate our
--  profile request to someone with what version numbers we have for them, and
--  then they reply with updated data if the versions don't match theirs.
--
-- Returns { 
--           [PART A VERSION], [PART B VERSION], 
--           [PART C VERSION], [PART D VERSION] 
--         }, [PROFILE ID]
function TRP.MyImpl.GetVersions( username )
	if not TRP3_IsUnitIDKnown( username ) 
	               or not TRP3_ProfileExists( username ) then 
		return
	end
	local profile, profile_id = TRP3_GetUnitIDProfile( username )
	local a, b, c, d = profile.character, profile.characteristics,
	                   profile.misc, profile.about
	return {
		a and a.v;
		b and b.v;
		c and c.v;
		d and d.v;
	}, profile_id
end

-------------------------------------------------------------------------------
-- This returns the versions of our profile, for testing against any version
--  numbers we get in requests (or other reasons?).
-- 
-- Returns { (Our Versions), ... }, (Our Profile ID)
function TRP.MyImpl.GetMyVersions()
	local profile_id, profile = TRP3_GetPlayerCurrentProfileID(), TRP3_GetPlayerCurrentProfile().player
	if not profile_id then return end
	local a, b, c, d = profile.character, profile.characteristics, profile.misc, profile.about
	return {
		a and a.v;
		b and b.v;
		c and c.v;
		d and d.v;
	}, profile_id
end

-------------------------------------------------------------------------------
-- Returns our current profile ID, which is basically a key to the [personal]
--  TRP profile register. For MSP implementations, we don't really support
--  different profiles, and instead just treat the user's character as a 
--  profile, and it looks something like "[CMSP]Username" as the profile.
--
function TRP.MyImpl.GetMyProfileID()
	return TRP3_GetPlayerCurrentProfileID()
end

-------------------------------------------------------------------------------
-- Returns the "exchange data" for what part specified. Part is 1, 2, 3, or 4
--  for differing levels of the profile. 1 is the volatile tooltip data, 2 is
--  the basic information about a character, 3 is the miscellaneous data, and 4
--                               is the deep info (the full description page).
-- For MSP implementations, the profile data needs to be upgraded into our
--  format, which is basically identical to the TRP3 profile structure.
function TRP.MyImpl.GetExchangeData( part )
	if part == 1 then
		return TRP3_GetData( "player/character" )
	elseif part == 2 then
		local data = TRP3_GetData( "player/characteristics" )
		
		-- We don't want to modify the data returned there.
		local data2 = {}
		for k,v in pairs(data) do
			data2[k] = v
		end
		
		-- We moved the addon version into the B table. This is unversioned,
		--                             but this is also static information.
		data2.VA = TRP3_Globals.addon_name .. ";" 
				  .. TRP3_Globals.version_display .. ";" 
				  .. (TRP3_Globals.isTrialAccount and "1" or "0")
	
		return data2
	elseif part == 3 then
		local data = TRP3_API.register.player.getMiscExchangeData()
		if type(data) == "string" then
			-- We can't use TRP's compression because in MSP implementations, 
			--  we don't have this function. (Not sure if this is necessary 
			--  anymore as TRP shouldn't use compression anymore.)
			data = TRP3_API.utils.serial.safeDecompressCodedStructure(data, {});
		end
		return data
	elseif part == 4 then
		-- The reason we don't read the profile data directly in here, is
		--  because the get*ExchangeData functions do some optimizations like
		--  cut out unused profile data (such as Template 2/3 text when using
		--  Template 1).
		local data = TRP3_API.register.player.getAboutExchangeData()
		if type(data) == "string" then
			-- I'm not proud of this.
			data = TRP3_API.utils.serial.safeDecompressCodedStructure(data, {});
		end
		return data
	end
end

-------------------------------------------------------------------------------
-- After 

function TRP.MyImpl.SaveExchangeData( username, profile_id, part, data )
	if not TRP3_IsUnitIDKnown( username ) then
		TRP3_API.register.addCharacter( username );
		
		-- If this is a new character spotted, then they'll show up as a
		--  Cross RP user until VA is received in the section B data.
		local addon_name = "Cross RP"
		TRP3_API.register.saveClientInformation( username, 
							                addon_name, "", false, nil, false )
	end
	TRP3_API.register.saveCurrentProfileID( username, profile_id )
	
	local infotype = TRP3_INFO_TYPES[part]
	if not infotype then return end
	
	if part == 2 then
		local client = data.VA
		if client then
			-- don't store anything foreign in the registry or trp team will have a cow
			data.VA = nil
			local client_name, client_version, trial = client:match( "([^;]+);([^;]+);([0-9])" )
			if client_name then
				local character = TRP3_API.register.getUnitIDCharacter( username )
				character.client        = client_name
				character.clientVersion = client_version
				character.msp           = false
				character.extended      = false
				character.isTrial       = trial == "1"
			end
		end
	end
	
	TRP3_API.register.saveInformation( username, TRP3_INFO_TYPES[part], data )
end

function TRP.MyImpl.OnTargetChanged()
	-- Dummy; only used for MSP implementation.
end

function TRP.MyImpl.Init()
	-- Callback for when the user opens the profile page, which must call
	--               TRP.OnProfileOpened. Must be done for each implementation.
	TRP3_API.Events.registerCallback( TRP3_API.Events.PAGE_OPENED,
	  function( pageId, context )
		if pageId == "player_main" and context.source == "directory" then
		
			local profile_id  = context.profileID
			local unit_id     = context.unitID
			local has_unit_id = context.openedWithUnitID
			
			Me.DebugLog2( "TRP profile opened.", profile_id, unit_id,
															  has_unit_id )
			if has_unit_id then
				-- Definitely have a unit ID
				Me.TRP_OnProfileOpened( unit_id )
				return
			elseif unit_id then
				-- Maybe have a unit ID, double check with our registry.
				if Me.touched_users[unit_id] then
					TRP.OnProfileOpened( unit_id )
					return
				end
			end
			
			local profile = TRP3_GetProfile(profile_id)
			local best_match, best_time = nil, 900
			for k,v in pairs( profile.link or {} ) do
				local tdata = Me.touched_users[k] or ""
				local _, _, touchtime = strsplit( ":", tdata )
				if touchtime and tonumber(touchtime) < best_time then
					-- We saw this character, but they might have switched
					--  characters while using the same profile, so we'll
					--  still search to see if there's a shorter idle time
					--  in here.
					best_match = k
					best_time  = touchtime
				end
			end
			
			if best_match then
				Me.TRP_OnProfileOpened( best_match )
			end
		end
	end)	
end

-------------------------------------------------------------------------------
-- This is a data request from someone.
--
function TRP.OnTRMessage( source, message, complete )
	if not m_imp then return end
	
	local tr_slot, tr_profile_id, tr_serials = message:match( "^TR (%S+) (%S+) (%S+)" )
	if not tr_slot then return end
	tr_profile_id = TRP.UnescapeProfileID( tr_profile_id )
	
	local my_versions, my_profile_id = m_imp.GetMyVersions()
	if not my_profile_id then return end
	
	tr_serials = {strsplit( ":", tr_serials )}
	
	for i = 1, 4 do
		local serialcheck = tr_serials[i] -- can be string number or "?" or ""
		local myversion = my_versions[i]
		
		if serialcheck == "" then
			serialcheck = nil
		elseif serialcheck == "?" then
			serialcheck = -1
		else
			serialcheck = tonumber(serialcheck)
			if not serialcheck then 
				Me.DebugLog( "Bad TR serials from %s.", source )
				return
			end
		end
		
		if myversion and serialcheck then
			-- This bit is being requested.
			if my_profile_id ~= tr_profile_id or myversion ~= serialcheck then
				-- send this bit, if we're off CD
				TRP.SendProfilePart( source, tr_slot, i )
			end
		end
	end
end

-------------------------------------------------------------------------------
function TRP.SendProfilePart( dest, slot, part )
	local key = dest .. part
	local sendtime = m_send_times[key] or -999
	local time = GetTime()
	if time < sendtime + SEND_COOLDOWN then return end
	m_send_times[key] = GetTime()
	
	local data = m_imp.GetExchangeData( part )
	local pid = TRP.EscapeProfileID(m_imp.GetMyProfileID())
	data = Me.Serializer:Serialize(data)
	Me.DebugLog2( "Sending Profile (TD):", dest, slot, part, pid, #data )
	Me.Proto.Send( dest, { "TD", slot, part, pid, data } )
end

-------------------------------------------------------------------------------
function TRP.OnTDMessage( source, message, complete )
	print( "DEBUG TD1", source, complete )
	local slot, part, pid = message:match( "^TD (%S+) (%S+) (%S+)" )
	if not slot then return end
	part = tonumber(part)
	if not part or part < 1 or part > 4 then return end
	
	local fullname = Me.Proto.DestToFullname( source )
	local time = GetTime()
	
	if tostring(m_request_slots[fullname .. part]) ~= slot then
		Me.DebugLog2( "Got TD with bad request slot.", source, slot, part, pid )
		return
	end
	print( "DEBUG TD2", source, complete )
	m_request_times[fullname .. part] = GetTime()
	
	if not complete then return end -- Wait for the message to complete.
	
	-- close slot
	m_request_slots[fullname .. part] = nil
	
	local data = message:match( "^TD %S+ %S+ %S+ (.*)" )
	if not data then return end
	local good, data = Me.Serializer:Deserialize( data )
	if not good or not data then
		Me.DebugLog( "Corrupt profile data from %s (Part %d).", source, part )
		return
	end
	Me.DebugLog( "Got profile data from %s (Part %d).", source, part )
	m_imp.SaveExchangeData( fullname, pid, part, data )
end

-------------------------------------------------------------------------------
-- Send out our exchange data. Use as sparingly as possible, as this is 
--  broadcasted to everyone.
--
function Me.TRP_SendProfile( slot )
	if not Me.relay_on then 
		-- Don't send anything if the relay is turned off at some point.
		Me.TRP_sending[slot] = nil
		return
	end
	
	if Me.TRP_sending[slot] then
		Me.TRP_sending[slot] = nil
		Me.TRP_last_sent[slot] = GetTime()
		local data = nil
		if TRP3_API then
			data = EXCHANGE_DATA_FUNCS[slot]()
		else
			if Me.TRP_imp then
				data = Me.TRP_imp.GetExchangeData(slot)
			end
		end
		
		if data then
			Me.DebugLog( "Sending profile piece %d", slot )
			Me.SendTextData( "TRPD" .. slot, data )
		end
	end
end
-------------------------------------------------------------------------------
function TRP.GetRequestSlot()
	local slot = m_next_request_slot
	m_next_request_slot = m_next_request_slot + 1
	return slot
end

-------------------------------------------------------------------------------
function TRP.RequestProfile( username, parts )

	if not m_imp then
		return
	end
	
	local tdata = Me.touched_users[username]
	if not tdata then return end
	local faction = tdata:sub(1,1)
	
	local time = GetTime()
	local request_filtered = ""
	
	parts = parts:gsub( ".", function( part )
		local key = part .. username
		local request_time = m_request_times[key] or 0
		if time < request_time + REQUEST_COOLDOWN then
			-- still within cooldown, erase that request
			return ""
		else
			m_request_times[key] = time
		end
	end)
	
	if parts == "" then
		-- everything is on cd
		return
	end
	
	local versions, profile_id = m_imp.GetVersions( username )
	versions = versions or {}
	local slot = TRP.GetRequestSlot()
	
	for i = 1, 4 do
		if parts:find(i) then
			versions[i] = versions[i] or "?"
			m_request_slots[username .. i] = slot
		else
			versions[i] = ""
		end
	end
	
	local dest = Me.Proto.DestFromFullname( username, faction )
	if profile_id then
		profile_id = TRP.EscapeProfileID( profile_id )
	else
		profile_id = "?"
	end
	
	Me.DebugLog( "Sending TR to %s.", username )
	Me.Proto.Send( dest, {"TR", slot, profile_id, table.concat( versions, ":" )} )
end

-------------------------------------------------------------------------------
-- Call this to start a request from a user. This can be called excessively,
--  and the internal mechanisms will throttle requests appropriately. `parts`
--  is a string that tells which profile parts to request, examples are "12"
--            for part 1 and 2, "3" for part 3, "312" for parts 1, 2, and 3.
function TRP.TryRequest( username, parts )
	if not username then return end
	if not Me.Proto.startup_complete then return end
	local islocal = IsLocal( username )
	if islocal == nil or islocal == true then
		Me.DebugLog( "TRP not requesting from local user %s.", username )
		return
	end
	
	TRP.RequestProfile( username, parts )
end

-------------------------------------------------------------------------------
-- When we interact with people through mouseover, targeting, or opening their
--  profile, we request different parts of their profile. TRP_needs_update
--                               erases its entries after we receive the data.
function TRP.OnMouseoverUnit()
	local username, faction = GetFullName( "mouseover" ), UnitFactionGroup( "mouseover" )
	TryRequest( username, "12" )
end

-------------------------------------------------------------------------------
function TRP.OnTargetChanged()
	local username, faction = GetFullName( "mouseover" ), UnitFactionGroup( "mouseover" )
	TryRequest( username, "123" )
	
	if m_imp then
		m_imp.OnTargetChanged()
	end
end

-------------------------------------------------------------------------------
-- This is part of the implementation's end, and needs to be called whenever
--  the user opens up someone's profile, so we can start transferring
--                                             description data.
function TRP.OnProfileOpened( username )
	if username == Me.fullname then return end
	TryRequest( username, "1234" )
end

function TRP.SetImplementation( imp )
	TRP.Impl = imp
	m_imp    = imp
end

-------------------------------------------------------------------------------
function TRP.Init()
	if TRP3_API then
		TRP.SetImplementation( TRP.MyImpl )
	end
	
	m_imp.Init()
	
	Me.Proto.SetMessageHandler( "TR", TRP.OnTRMessage )
	Me.Proto.SetMessageHandler( "TD", TRP.OnTDMessage )
end

