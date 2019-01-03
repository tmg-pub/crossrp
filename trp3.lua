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
local TryRequest

-------------------------------------------------------------------------------
local IsLocal

-------------------------------------------------------------------------------
local TRP3_IsUnitIDKnown, TRP3_GetUnitIDCurrentProfile, TRP3_GetProfile

function TRP.CacheRefs()
	TryRequest = TRP.TryRequest
	
	IsLocal    = Me.IsLocal
	
	if TRP3_API then
		TRP3_IsUnitIDKnown = TRP3_API.register.isUnitIDKnown
		TRP3_GetUnitIDCurrentProfile = TRP3_API.register.getUnitIDCurrentProfile
		TRP3_GetProfile = TRP3_API.register.getProfile
	end
end

-- sections we have:
-- 1: tooltip (TRP CHAR) update on mouseover
-- 2: brief (TRP CHS) update on mouseover
-- 3: misc (TRP MISC) update on target
-- 4: full profile (TRP ABOUT) update on inspect

-------------------------------------------------------------------------------
-- Info types in the registry for each update slot.
--
local INFO_TYPES
-------------------------------------------------------------------------------
-- TIMING
-------------------------------------------------------------------------------
local REQUEST_COOLDOWN = 30.0
local SEND_COOLDOWN = 25.0

-------------------------------------------------------------------------------
-- The last time we requested data from someone, so we can have a cooldown.
--  Indexed as [FULLNAME+TYPE]
local m_request_times = {}
-------------------------------------------------------------------------------
-- Request slots are opened when we make a profile request from someone. They
--  need to match the ID we give, otherwise we ignore their message. This is to
--  deter malicious users from overwriting data in our registry when we aren't
--                                                           making a request.
local m_request_slots = {}
-------------------------------------------------------------------------------
-- The last time we sent data to someone, so we can have a cooldown.
-- Indexed as [FULLNAME+TYPE]
local m_send_times = {}
-------------------------------------------------------------------------------
-- For users without TRP3, this is populated with a fallback interface that
--  replaces various functions. e.g. a different implementation of where the
--                                                   profile data comes from.
local m_imp = nil
-------------------------------------------------------------------------------
-- This tells us whether or not we should accept profile bits from people.
-- We don't want to intercept any profile transfers unless we start from the
--  vernum stage, otherwise we could be left in a wonky state, overwriting the
--  wrong profile with data, or saving data when we don't want to, like when
--  dealing with local MSP users.
-- Set to true when accepting their vernum, and revoke it when you discard
--  their vernum.
Me.TRP_accept_profile = {}
-------------------------------------------------------------------------------
-- Utility functions to escape TPR profile ID strings.
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
function TRP.MyImpl.GetVersions( username )
	if not TRP3_API.register.profileExists( username ) then return end
	local profile, profile_id = TRP3_API.register.getUnitIDProfile( username )
	local a, b, c, d = profile.character, profile.characteristics, profile.misc, profile.about
	return {
		a and a.v;
		b and b.v;
		c and c.v;
		d and d.v;
	}, profile_id
end

-------------------------------------------------------------------------------
function TRP.MyImpl.GetMyVersions()
	local profile_id, profile = TRP3_API.profile.getPlayerCurrentProfileID(), TRP3_API.profile.getPlayerCurrentProfile()
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
function TRP.MyImpl.GetMyProfileID()
	return TRP3_API.profile.getPlayerCurrentProfileID()
end

-------------------------------------------------------------------------------
function TRP.MyImpl.GetExchangeData( part )
	-- The reason we don't read the profile data directly in here, is because
	--  the get*ExchangeData functions do some optimizations like cut out
	--  unused profile data (such as Template 2/3 text when using Template 1).
	if part == 1 then
		return TRP3_API.profile.getData( "player/character" )
	elseif part == 2 then
		local data = TRP3_API.profile.getData( "player/characteristics" )
		
		-- We don't want to modify the data returned there.
		local data2 = {}
		for k,v in pairs(data) do
			data2[k] = v
		end
		
		-- We moved the addon version into the B table. This is unversioned,
		--                             but this is also static information.
		data2.VA = TRP3_API.globals.addon_name .. ";" 
				  .. TRP3_API.globals.version_display .. ";" 
				  .. (TRP3_API.globals.isTrialAccount and "1" or "0")
	
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
		local data = TRP3_API.register.player.getAboutExchangeData()
		if type(data) == "string" then
			-- I'm not proud of this.
			data = TRP3_API.utils.serial.safeDecompressCodedStructure(data, {});
		end
		return data
	end
end


local TRP3_INFO_TYPES 

if TRP3_API then
	TRP3_INFO_TYPES = {
		TRP3_API.register.registerInfoTypes.CHARACTER;
		TRP3_API.register.registerInfoTypes.CHARACTERISTICS;
		TRP3_API.register.registerInfoTypes.MISC;
		TRP3_API.register.registerInfoTypes.ABOUT;
	}
end

function TRP.MyImpl.SaveExchangeData( username, profile_id, part, data )
	if not TRP3_API.register.isUnitIDKnown( username ) then
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
	
	TRP3_API.register.saveInformation( user.name, TRP3_INFO_TYPES[part], data )
end

-------------------------------------------------------------------------------
-- This is a data request from someone.
--
function TRP.OnTRMessage( source, message, complete )
	if not m_imp then return end
	
	local tr_slot, tr_profile_id, tr_serials = message:match( "^TR (%S+) (%S+) (%S+)" )
	if not tr_slot then return end
	tr_profile_id = TRP.UnescapeProfileID( tr_profile_id )
	
	local my_versions, my_profile_id = m_imp.GetVersions()
	if not my_profile_id then return end
	
	tr_serials = strsplit( ":", tr_serials )
	
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
		
		if myversion and serialcheck ~= "" then
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
	local sendtime = m_send_times[key]
	local time = GetTime()
	if time < sendtime + SEND_COOLDOWN then return end
	m_send_times[key] = GetTime()
	
	local data = m_imp.GetExchangeData( part )
	local pid = TRP.EscapeProfileID(m_imp.GetMyProfileID())
	data = Me.Serializer:Serialize(data)
	Me.Proto.Send( dest, { "TD", slot, part, pid, data } )
end

-------------------------------------------------------------------------------
function TRP.OnTDMessage( source, message, complete )
	local slot, part, pid = message:match( "^TD %S+ %S+ %S+ (.*)" )
	if not slot then return end
	part = tonumber(part)
	if not part or part < 1 or part > 4 then return end
	
	local fullname = Me.Proto.DestToFullname( source )
	local time = GetTime()
	
	if tostring(m_request_slots[fullname .. part]) ~= slot then
		Me.DebugLog2( "Got TD with bad request slot.", source, slot, part, pid )
		return
	end
	
	m_request_times[fullname .. part] = GetTime()
	
	if not complete then return end -- Wait for the message to complete.
	
	-- close slot
	m_request_slots[fullname .. part] = nil
	
	local data = message:match( "^TD %S+ %S+ %S+ (.*)" )
	if not data then return end
	data = Me.Serializer:Deserialize( data )
	if not data then return end
	
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
-- Request profile data from someone. This reads from Me.TRP_needs_update[user]
--  to see what we want to get from them. It's also safe to spam (from
--                                    mouseover and such) as it has a cooldown.
function TRP.RequestProfile( username, faction, parts )

	if not m_imp then
		return
	end
	
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
--  and the internal mechanisms will throttle requests appropriately. `bits`
--  is a string that tells which profile parts to request, examples are "12"
--            for part 1 and 2, "3" for part 3, "312" for parts 1, 2, and 3.
function TRP.TryRequest( username, bits )
	if not username then return end
	
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
	local username, faction = Me.GetFullName( "mouseover" ), UnitFactionGroup( "mouseover" )
	TryRequest( username, "12" )
end

-------------------------------------------------------------------------------
function TRP.OnTargetChanged()
	local username, faction = Me.GetFullName( "mouseover" ), UnitFactionGroup( "mouseover" )
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
	m_imp = imp
end

-------------------------------------------------------------------------------
function Me.TRP_Init()
	
	if not TRP3_API then
		if Me.TRP_imp then
			Me.TRP_imp.Init()
		end
		return
	end
	
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
				if Me.crossrp_users[unit_id] then
					Me.TRP_OnProfileOpened( unit_id )
					return
				end
			end
			
			local profile = TRP3_API.register.getProfile(profile_id)
			local best_match, best_time = nil, 900
			for k,v in pairs( profile.link or {} ) do
				if Me.touched_users[k]
						  and Me.touched_users[k] < best_time then
					-- We saw this character, but they might have switched
					--  characters while using the same profile, so we'll
					--  still search to see if there's a shorter idle time
					--  in here.
					best_match = k
					best_time  = Me.touched_users[k]
				end
			end
			
			if best_match then
				Me.TRP_OnProfileOpened( best_match )
			end
		end
	end)	
end
