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
local 
	TRP3_API, TRP3_Globals, TRP3_IsUnitIDKnown, TRP3_GetUnitIDProfile,
	TRP3_GetProfile, TRP3_ProfileExists, TRP3_GetPlayerCurrentProfileID,
	TRP3_GetPlayerCurrentProfile, TRP3_GetData

local UnitFactionGroup = 
      UnitFactionGroup
	
local TRP3_INFO_TYPES
-------------------------------------------------------------------------------
-- I'm a bit torn on what sort of method we should use to cache locals. This
--  method seems like a good idea, especially if TRP3_API isn't available when
--  our script loads. This also lets a user recache locals if they want to
--  modify one of these functions. A bit of a rare case, that, but I like to
--  allow flexibility with interfacing with my code, expose everything.
-- Only problem with this method is it looks pretty dirty... I don't like these
--  names duplicate above and below. Easy to forget something and then tamper
--  with the global environment or something.
function TRP.CacheRefs()
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
end

-------------------------------------------------------------------------------
-- Sections we have:
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
		a and tonumber(a.v);
		b and tonumber(b.v);
		c and tonumber(c.v);
		d and tonumber(d.v);
	}, profile_id
end

-------------------------------------------------------------------------------
-- This returns the versions of our profile, for testing against any version
--  numbers we get in requests (or other reasons?).
-- 
-- Returns { (Our Versions), ... }, (Our Profile ID)
function TRP.MyImpl.GetMyVersions()
	local profile_id, profile = TRP3_GetPlayerCurrentProfileID(),
	                                      TRP3_GetPlayerCurrentProfile().player
	if not profile_id then return end
	local a, b, c, d = profile.character, profile.characteristics,
	                                                profile.misc, profile.about
	return {
		a and tonumber(a.v);
		b and tonumber(b.v);
		c and tonumber(c.v);
		d and tonumber(d.v);
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
		
		local istrial = IsTrialAccount() or IsVeteranTrialAccount()
		
		-- We moved the addon version into the B table. This is unversioned,
		--                             but this is also static information.
		data2.VA = TRP3_Globals.addon_name .. ";" 
				  .. TRP3_Globals.version_display .. ";" 
				  .. (istrial and "1" or "0")
	
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
-- After receiving exchange data from someone, the implementation is
--  responsible for moving it into the appropriate storage. For TRP3, there are
--  function exposed to save the data (and since we use the TRP format for the
--  exchange data, it can be passed directly).
-- For XRP and MRP, those both use the MSP API, and the data is downgraded into
--  an appropriate medium for them. (XRP automatically caches data in the MSP
--  tables.)
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
	
	-- One exception to "storing data directly" is our little modification to
	--  the charcteristics table (part 2), we store VA there which has the
	--  TRP version info (and the trial bit).
	if part == 2 then
		local client = data.VA
		if client then
			-- We wan't to remove it before storing. Don't store anything
			--  foreign in the registry or trp team will have a cow. :)
			data.VA = nil
			local client_name, client_version, trial =
			                          client:match( "([^;]+);([^;]+);([0-9])" )
			if client_name then
				-- In the TRP3 protocol, this version setting stuff is done at
				--  the beginning before any data is transferred, when the
				--  vernums are exchanged.
				local char = TRP3_API.register.getUnitIDCharacter( username )
				char.client        = client_name
				char.clientVersion = client_version
				char.msp           = false
				char.extended      = false
				char.isTrial       = trial == "1"
			end
		end
	end
	
	TRP3_API.register.saveInformation( username, TRP3_INFO_TYPES[part], data )
end

-------------------------------------------------------------------------------
-- PLAYER_TARGET_CHANGED also triggers an implementation defined function.
function TRP.MyImpl.OnTargetChanged()
	-- Dummy; only used for MSP implementation.
end

-------------------------------------------------------------------------------
-- Called when this module starts up, to do any implementation-specific
--  initialization.
function TRP.MyImpl.Init()

	-- Callback for when the user opens the profile page, which must call
	--               TRP.OnProfileOpened. Must be done for each implementation.
	TRP3_API.Events.registerCallback( TRP3_API.Events.PAGE_OPENED,
	  function( pageId, context )
		if pageId == "player_main" and context.source == "directory" then
			Me.DebugLog2( "PAGEOPEN", pageId, context )
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
-- Send a profile part to a user. `dest` is a Proto destination. `slot` is the
--  slot they have send us in the TR. `part` can be 1-4, selecting which
--  profile part to send to them.
function TRP.SendProfilePart( dest, slot, part )
	local key = dest .. part
	local sendtime = m_send_times[key] or -999
	local time = GetTime()
	if time < sendtime + SEND_COOLDOWN then return end
	m_send_times[key] = GetTime()
	
	-- The GetExchangeData implementation is responsible for providing TRP3
	--  compatible data (with a few minor nuances specific to Cross RP).
	local data = m_imp.GetExchangeData( part )
	local pid = TRP.EscapeProfileID( m_imp.GetMyProfileID() )
	data = Me.Serializer:Serialize( data )
	Me.DebugLog2( "Sending Profile (TD):", dest, slot, part, pid, #data )
	
	-- TD format is "TD <slot> <part> <profile_id> <data...>", `data` being
	--  serialized profile data, directly from TRP3.
	Me.Proto.Send( dest, { "TD", slot, part, pid, data } )
end

-------------------------------------------------------------------------------
-- TR: Someone is requesting our profile data.
--
function TRP.OnTRMessage( source, message, complete )
	if not m_imp then return end
	
	-- TR comes in the format "TR <slot> <profile_id> <serials>"
	-- If profile_id doesn't match our profile ID, then we ignore serials
	--  and send them everything that they request (i.e. they don't know
	--  anything about our character in that case).
	-- If profile_id does match, then we check each serial they send, and then
	--  for any mismatches (if we update something) we resend those bits.
	-- <serials> is up to 4 numbers, looks like 1:2:3:4, but they can be
	--  omitted, like 1:2:: - what this would do is make a request for the
	--  first two profile parts only, ignoring the other two.
	-- Serials can also be "?" for "unknown", where they are making an
	--  unconditional request, e.g. ::?: is an unconditional request for part 3
	--  of our profile data.
	-- <slot> is sort of a firewall thing. We need to have this slot mirrored
	--  in our data reply, otherwise they'll ignore our message. They open up
	--  a slot when they send the TR request.
	local tr_slot, tr_profile_id, tr_serials =
	                                   message:match( "^TR (%S+) (%S+) (%S+)" )
	if not tr_slot then return end
	tr_profile_id = TRP.UnescapeProfileID( tr_profile_id )
	
	local my_versions, my_profile_id = m_imp.GetMyVersions()
	if not my_profile_id then return end
	
	tr_serials = {strsplit( ":", tr_serials )}
	
	for i = 1, 4 do
		local serialcheck = tr_serials[i]
		local myversion = my_versions[i]
		
		if serialcheck == "" then
			-- Empty string, they aren't requesting this profile part.
			serialcheck = nil
		elseif serialcheck == "?" then
			-- "?" string, they are doing an unconditional request.
			serialcheck = -1
		else
			-- Version number, they are doing an update request, and we do
			--  nothing if their version number is up-to-date with ours.
			serialcheck = tonumber(serialcheck)
			if not serialcheck then 
				Me.DebugLog( "Bad TR serials from %s.", source )
				return
			end
		end
		
		-- The MSP implementation doesn't store profile IDs, so we also check
		--  against what they might send us: "[CMSP]<fullname>".
		if tr_profile_id == "[CMSP]" .. Me.fullname then
			tr_profile_id = my_profile_id
		end
		
		if myversion and serialcheck then
			-- We have this part in our profile, and this part is being
			--  requested.
			if my_profile_id ~= tr_profile_id or myversion ~= serialcheck then
				-- Send this part, but only if we're off CD (the function
				--  below has some internal checks).
				TRP.SendProfilePart( source, tr_slot, i )
			end
		end
	end
end

-------------------------------------------------------------------------------
-- TD: Someone is sending us their profile data.
--
function TRP.OnTDMessage( source, message, complete )
	
	-- Example: TD 15 1 10510815802AJFL <serialized data...>
	local slot, part, pid = message:match( "^TD (%S+) (%S+) (%S+)" )
	if not slot then return end
	part = tonumber(part)
	if not part or part < 1 or part > 4 then return end
	
	local fullname = Me.Proto.DestToFullname( source )
	local time = GetTime()
	
	-- If we don't have a slot open for them, ignore the message. Likely some
	--  sort of network error, but this should probably not ever happen unless
	--  someone is trying something fishy.
	-- One of the big caveats with our protocol is that it's hard to trace
	--  abuse. One router could tell another router easy to say something, and
	--  there's no easy trail back to them.
	if tostring(m_request_slots[fullname .. part]) ~= slot then
		Me.DebugLog2( "Got TD with bad request slot.", source, slot, part, pid )
		return
	end
	
	m_request_times[fullname .. part] = GetTime()
	
	if not complete then return end -- Wait for the message to complete.
	
	-- close slot
	m_request_slots[fullname .. part] = nil
	
	-- Kind of nasty that we're doing two matches... Maybe it'd be better if 
	--  we just did this match above?
	local data = message:match( "^TD %S+ %S+ %S+ (.*)" )
	if not data then return end
	local good, data = Me.Serializer:Deserialize( data )
	if not good or not data then
		Me.DebugLog( "Corrupt profile data from %s (Part %d).", source, part )
		return
	end
	Me.DebugLog( "Got profile data from %s (Part %d).", source, part )
	
	-- Pass the data to the implementation-specific saving function. Done!
	m_imp.SaveExchangeData( fullname, pid, part, data )
end

-------------------------------------------------------------------------------
-- Generate a new request slot. Just an incrementing number. Request slots are
--  like ports opened in a firewall. They open up when you make a request, and
--  close when it's satisfied.
function TRP.GetRequestSlot()
	local slot = m_next_request_slot
	m_next_request_slot = m_next_request_slot + 1
	return slot
end

-------------------------------------------------------------------------------
-- Request profile parts from someone. This function can be spammed as there
--  are internal cooldowns that only allow a request every so often. `parts` is
--  what parts are being requested, formatted as a string of numbers, e.g.
--  "124" requests parts 1, 2, and 4. `username` is a fullname.
-- This doesn't work on anything. The user needs to have "touched" the user in
--  question, especially to learn what faction they're on, otherwise we don't
--  know who we're sending to.
-- This is also sort of an internal function, and TryRequest should be used
--  instead. TryRequest ignores input when dealing with local players, i.e.
--  players that you can just normally transfer profiles from.
function TRP.RequestProfile( username, parts )

	if not m_imp then
		return
	end
	
	-- Only ask players who we have touched (with the mouse). That's the only
	--  way we can know their faction for the request.
	local tdata = Me.touched_users[username]
	if not tdata then return end
	local faction = tdata:sub( 1, 1 )
	
	local time = GetTime()
	local request_filtered = ""
	
	-- Scan through parts, filter out any that are on cooldown, and then set
	--  the cooldown time for the others.
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
		-- Everything is on CD.
		return
	end
	
	local versions, profile_id = m_imp.GetVersions( username )
	versions = versions or {}
	local slot = TRP.GetRequestSlot()
	
	-- Open up request slots.
	for i = 1, 4 do
		if parts:find(i) then
			-- If we don't know their version for this part, we send "?" for an
			--  unconditional request.
			versions[i] = versions[i] or "?"
			m_request_slots[username .. i] = slot
		else
			versions[i] = ""
		end
	end
	
	local dest = Me.Proto.DestFromFullname( username, faction )
	
	if profile_id then
		-- Older TRP profile IDs can have some crazy characters in them that
		--  will screw up the protocol.
		profile_id = TRP.EscapeProfileID( profile_id )
	else
		-- We don't know anything about them, and "?" can be passed as the
		--  profile ID too.
		profile_id = "?"
	end
	
	versions = table.concat( versions, ":" )
	
	Me.DebugLog( "Sending TR to %s.", username )
	Me.Proto.Send( dest, {"TR", slot, profile_id, versions} )
end

-------------------------------------------------------------------------------
-- Call this to start a request from a user. This can be called excessively,
--  and the internal mechanisms will throttle requests appropriately. `parts`
--  is a string that tells which profile parts to request, examples are "12"
--            for part 1 and 2, "3" for part 3, "312" for parts 1, 2, and 3.
function TRP.TryRequest( username, parts )
	if IsInInstance() then return end
	if not username then return end
	if not Me.Proto.startup_complete then return end
	local islocal = Me.IsLocal( username )
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
	local username = Me.GetFullName( "mouseover" )
	TRP.TryRequest( username, "12" )
end

-------------------------------------------------------------------------------
-- Callback for PLAYER_TARGET_CHANGED.
function TRP.OnTargetChanged()
	local username = Me.GetFullName( "target" )
	TRP.TryRequest( username, "123" )
	
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
	TRP.TryRequest( username, "1234" )
end

-------------------------------------------------------------------------------
-- Set the implementation to be used to fetch and store profile data. Currently
--  we have one for TRP3 and one for MSP which handles MRP, XRP, and GnomTEC.
function TRP.SetImplementation( imp )
	TRP.Impl = imp
	m_imp    = imp
end

-------------------------------------------------------------------------------
function TRP.Init()
	if TRP3_API then
		TRP.SetImplementation( TRP.MyImpl )
	end
	
	if not m_imp then return end
	
	m_imp.Init()
	
	Me.Proto.SetMessageHandler( "TR", TRP.OnTRMessage )
	Me.Proto.SetMessageHandler( "TD", TRP.OnTDMessage )
end

