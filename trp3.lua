
local _, Me = ...
-- TODO: make sure you don't make duplicate requests. if you see someone else
--  make a request for something, share that cooldown!
-------------------------------------------------------------------------------
-- Entries in our vernum string.
--
local VERNUM_VERSION      = 1
local VERNUM_VERSION_TEXT = 2
local VERNUM_PROFILE      = 3
local VERNUM_CHS_V        = 4
local VERNUM_ABOUT_V      = 5
local VERNUM_MISC_V       = 6
local VERNUM_CHAR_V       = 7
local VERNUM_TRIAL        = 8

-- Exposure for other implementations.
Me.VERNUM_VERSION      = VERNUM_VERSION
Me.VERNUM_VERSION_TEXT = VERNUM_VERSION_TEXT
Me.VERNUM_PROFILE      = VERNUM_PROFILE
Me.VERNUM_CHS_V        = VERNUM_CHS_V
Me.VERNUM_ABOUT_V      = VERNUM_ABOUT_V
Me.VERNUM_MISC_V       = VERNUM_MISC_V
Me.VERNUM_CHAR_V       = VERNUM_CHAR_V
Me.VERNUM_TRIAL        = VERNUM_TRIAL

-------------------------------------------------------------------------------
-- Indexes of parts that need updates. We use the word `update` a bunch where
--  it means a registry slice.
--
local UPDATE_CHS   = 1 -- Section B, update on mouseover.
local UPDATE_ABOUT = 2 -- Section D: update on inspect.
local UPDATE_MISC  = 3 -- Section C: update on target.
local UPDATE_CHAR  = 4 -- Section A, update on mouseover.
local UPDATE_SLOTS = 4

Me.TRP_UPDATE_CHS   = UPDATE_CHS
Me.TRP_UPDATE_ABOUT = UPDATE_ABOUT
Me.TRP_UPDATE_MISC  = UPDATE_MISC
Me.TRP_UPDATE_CHAR  = UPDATE_CHAR
Me.TRP_UPDATE_SLOTS = UPDATE_SLOTS

-- Things are a bit jumbled up right now, but we want to have this work with
--  little rewriting as possible. Eventually, we will switch fully to the
--  unified protocol.

-------------------------------------------------------------------------------
-- Functions for getting exchange data for a certain update slot.
--
local EXCHANGE_DATA_FUNCS

-------------------------------------------------------------------------------
-- Info types in the registry for each update slot.
--
local INFO_TYPES

-------------------------------------------------------------------------------
local SEND_COOLDOWN = 20.0  -- Cooldown for sending profile data.
local SEND_DELAY    = 5.0   -- Delay for sending profile data when not on
                            --  cooldown.
local REQUEST_COOLDOWN = 20.0  -- Cooldown for requesting profile data when 
                               --  mousing over.
local VERNUM_HENLO_DELAY = 27.0  -- Delay after getting HENLO to send vernum.
local VERNUM_HENLO_VARIATION = 10.0 -- We add 0 to this amount of seconds
                                    --  randomly, so when clients respond with
									--  VERNUM, they're not all sending it at
									--  the same time and punching the server.
local VERNUM_UPDATE_DELAY = 5.0  -- Delay after updating our profile data (like
                                 --  currently etc) before broadcasting our
								 --  vernum.
local REQUEST_IGNORE_PERIOD = 5.0  -- Seconds to wait before we accept new
                                   --  requests for an update slot we just
								   --  sent.
--VERNUM_HENLO_DELAY = 1.0  -- DEBUG BYPASS!!
--VERNUM_HENLO_VARIATION = 1.0
-------------------------------------------------------------------------------
-- What players we see out of date.
--   [username] is nil if we think we're up to date.
--   [username][UPDATE_SLOT] is true when we want updates.
Me.TRP_needs_update = {}
-------------------------------------------------------------------------------
-- Data that we're about to send.
--   [UPDATE_SLOT] is true when we're scheduled to send something.
Me.TRP_sending = {}
-------------------------------------------------------------------------------
-- Last time we sent our profile bits.
--   [UPDATE_SLOT] = time we last sent this update slot.
-- We use this to ignore TRPRQ parts for `REQUEST_IGNORE_PERIOD` seconds.
Me.TRP_last_sent = {}
-------------------------------------------------------------------------------
-- The last time we requested data from someone, so we can have a cooldown.
Me.TRP_request_times = {}
-------------------------------------------------------------------------------
-- TRP3 can be replaced by other implementations if it isn't installed.
--
Me.TRP_imp = nil

-------------------------------------------------------------------------------
-- PROTOCOL
-- Vernum Table:
--   TRPV a:b:c:d:e:f:g:h
--        | | | | | | | |
--        '--------------- COLON SEPARATED LIST OF VERNUM_XYZ ENTRIES
--
-- Request info from user:
-- TRPRQ user:abcd
--        |    '---- UPDATE REQUESTS (1-4), "1" = update, "0" = skip
--        '--------- TARGET USER FULLNAME
--
-- Transfer data (DATA message):
-- TRPDx DATA
--     |  '---- PACKED EXCHANGE DATA
--     '------- UPDATE INDEX (1-4)
--
--
-------------------------------------------------------------------------------
-- When we see a VERNUM message, we flag users who we need updates from. We
--  don't actually do anything until we mouseover them. When we mouseover, we
--  see what we flagged and then request updates from them.
--
function Me.TRP_SetNeedsUpdate( user, slot )
	Me.TRP_needs_update[user] = Me.TRP_needs_update[user] or {}
	Me.TRP_needs_update[user][slot] = true
end

-------------------------------------------------------------------------------
-- After we receive the exchange data and update TRP's registry, we clear the
--  flags.
--
function Me.TRP_ClearNeedsUpdate( user, slot )
	if not Me.TRP_needs_update[user] then return end
	Me.TRP_needs_update[user][slot] = nil
	for k, v in pairs( Me.TRP_needs_update[user] ) do
		return
	end
	Me.TRP_needs_update[user] = nil
end

-------------------------------------------------------------------------------
-- Vernum (Version Numbers) is sent to people on the login message and after
--  we update the registry.
-- For login messages, we put a much longer delay, because that's low priority.
-- If you update your info, the delay is much shorter, just giving you enough
--  time to finish editing your currently or something before the vernum is
--  sent to everyone.
--
function Me.TRP_SendVernum()
	if not Me.relay_on then return end
	
	local query
	
	Me.TRP_last_sent_vernum = GetTime()
	
	if TRP3_API then
		-- Store empty profile as "-" in the protocol.
		local profile_id = TRP3_API.profile.getPlayerCurrentProfileID()
		if not profile_id or profile_id == "" then profile_id = "-" end
		
		query = table.concat( {
			TRP3_API.globals.version; -- a number
			TRP3_API.globals.version_display; -- a string
			profile_id; -- a string
			TRP3_API.profile.getData( "player/characteristics" ).v or 0;
			TRP3_API.profile.getData( "player/about" ).v or 0;
			TRP3_API.profile.getData( "player/misc" ).v or 0;
			TRP3_API.profile.getData( "player/character" ).v or 1;
			TRP3_API.globals.isTrialAccount and 1 or 0; -- true/nil
		}, ":" )
	elseif Me.TRP_imp then
		query = Me.TRP_imp.BuildVernum()
	else
		-- No TRP implemenation.
		return
	end
	
	Me.SendPacket( "TRPV", query )
end

-------------------------------------------------------------------------------
-- Currently only being called from the login command from others. We add a
--  long delay here because it isn't urgent at all and want to hit as many
--  people as possible.
--
function Me.TRP_SendVernumDelayed()
	--if not TRP3_API then return end
	Me.Timer_Start( "trp_vernums", "ignore", 
	               VERNUM_HENLO_DELAY + math.random(0, VERNUM_HENLO_VARIATION), 
				   Me.TRP_SendVernum )
end

-------------------------------------------------------------------------------
-- Receiving Vernum from someone.
--
function Me.ProcessPacket.TRPV( user, command, msg )
	if not TRP3_API then return end
	if user.self or not user.connected then return end
	
	-- Maybe we should cancel here for local players for compatibility reasons.
	-- It doesn't hurt to save this data for TRP though if you do it right.
	
	local args = {}
	for v in msg:gmatch( "[^:]+" ) do
		table.insert( args, v )
	end

	-- Conversion to numbers and basic sanitization.
	args[VERNUM_VERSION] = tonumber(args[VERNUM_VERSION])
	args[VERNUM_CHS_V]   = tonumber(args[VERNUM_CHS_V]) 
	args[VERNUM_ABOUT_V] = tonumber(args[VERNUM_ABOUT_V])
	args[VERNUM_MISC_V]  = tonumber(args[VERNUM_MISC_V])
	args[VERNUM_CHAR_V]  = tonumber(args[VERNUM_CHAR_V])
	args[VERNUM_TRIAL]   = args[VERNUM_TRIAL] == "1" and true or nil
	if args[VERNUM_PROFILE] == "-" then args[VERNUM_PROFILE] = "" end
	
	if not args[VERNUM_VERSION] or not args[VERNUM_CHS_V]
			or not args[VERNUM_ABOUT_V] or not args[VERNUM_MISC_V] 
			or not args[VERNUM_CHAR_V] then 
		
		return 
	end
	Me.DebugLog( "Got vernum." )
	
	if TRP3_API then
	
		-- Save info.
		if not TRP3_API.register.isUnitIDKnown( user.name ) then
			TRP3_API.register.addCharacter( user.name );
		end
		
		TRP3_API.register.saveClientInformation( user.name, 
				TRP3_API.globals.addon_name, args[VERNUM_VERSION_TEXT], false, 
				nil, args[VERNUM_TRIAL] )
		TRP3_API.register.saveCurrentProfileID( user.name, args[VERNUM_PROFILE] )
		
		-- Check the update slot version numbers to see what we are out of date
		--  with.
		for i = 1, UPDATE_SLOTS do
			if TRP3_API.register.shouldUpdateInformation( user.name, 
					INFO_TYPES[i], args[VERNUM_CHS_V+i-1] ) then
				Me.TRP_SetNeedsUpdate( user.name, i )
			end
		end
	
	elseif Me.TRP_imp then
		Me.TRP_imp.OnVernum( user, args )
		
--		for i = 1, UPDATE_SLOTS do
--			if TRP_imp.NeedsUpdate( user, i, args[VERNUM_CHS_V+i-1] ) then
--				Me.TRP_SetNeedsUpdate( user.name, i )
--			end
--		end
		
		return
	end
end

-------------------------------------------------------------------------------
-- This is a data request from someone.
--
function Me.ProcessPacket.TRPRQ( user, command, msg )
	if user.self or not user.connected then return end
	-- (This check isn't necessary. Why is anyone even doing this?)
	--if not user.horde and not user.xrealm then 
	--	-- local player, don't use this protocol.
	--	return
	--end
	if not Me.relay_on then
		-- Relay is off. Ignore this.
		return
	end
	
	local target, a, b, c, d = msg:match( "^([^:]+):(%d)(%d)(%d)(%d)" )
	if not target then return end
	local targeting_us = target == Me.fullname
	if not targeting_us then
		-- This request isn't targeting us, but we still want to update our
		--  cooldowns with it.
		Me.TRP_request_times[name] = Me.TRP_request_times[name] or {}
		local rqt = Me.TRP_request_times[name]
		
	end
	
	local parts = { a, b, c, d }
	for i = 1, UPDATE_SLOTS do
		if parts[i] == "1" then
			if targeting_us then
				if GetTime() - (Me.TRP_last_sent[i] or 0) < REQUEST_IGNORE_PERIOD then
					-- We're in the ignore period. This is set after we broadcast
					--  data, for each part, so that any additional requests that
					--  come /right after/ are ignored, as they likely have just
					--  been fulfilled. In the corner case where someone actually
					--  just logged in and missed that message, they'll have to
					--  wait out the cooldown before making another request.
				else
					Me.TRP_sending[i] = true
				end
			else
				-- Reset our cooldown. Only one person has to make a request.
				rqt[i] = GetTime()
			end
		end
	end
	
	if not targeting_us then
		return
	end
	
	Me.DebugLog2( "Received TRP request.", a, b, c, d )
	-- This timer is a mix of cooldown and normal. If it's on CD, then we run
	--  it normally - at the next CD end. If it's not on CD, we still use a 
	--  delay, to catch any additional requests before we send out
	--  data.
	-- Scenario: Player is running around like an idiot, and comes across
	--  a group of a few people. They're gonna mouse-over and then send
	--  their TRP requests all at once. We want to catch them all before we
	--  actually do the send.
	if Me.Timer_NotOnCD( "trp_sending", SEND_COOLDOWN ) then	
		Me.Timer_Start( "trp_sending", "ignore", SEND_DELAY, function()
			Me.TRP_SendProfile()
		end)
	else
		Me.Timer_Start( "trp_sending", "cooldown", SEND_COOLDOWN, function()
			Me.TRP_SendProfile()
		end)
	end
end

-------------------------------------------------------------------------------
-- Send out our exchange data. Use as sparingly as possible, as this is 
--  broadcasted to everyone.
--
function Me.TRP_SendProfile()
	if not Me.relay_on then 
		-- Don't send anything if the relay is turned off at some point.
		Me.TRP_sending = {}
		return
	end
	
	if not TRP3_API then return end
	
	Me.DebugLog( "Sending profile." )
	
	for i = 1, UPDATE_SLOTS do
		if Me.TRP_sending[i] then
			Me.TRP_sending[i] = nil
			Me.TRP_last_sent[i] = GetTime()
			local data = nil
			if TRP3_API then
				data = EXCHANGE_DATA_FUNCS[i]()
			else
				if Me.TRP_imp then
					data = Me.TRP_imp.GetExchangeData(i)
				end
			end
			
			if data then
				Me.DebugLog( "Sending profile piece %d", i )
				Me.SendData( "TRPD" .. i, data )
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Callback for receiving TRP DATA messages.
--
local function HandleTRPData( user, tag, istext, data )
	if user.self then return end
	if not user.horde and not user.xrealm then
		-- /Maybe/ we should cut out here, because otherwise we have two
		--  protocols going - one in addon whisper, and the other in the
		--  relay channel. Is this bad though? Double updates sometimes.
	end
	
	-- Parse out the index from the tag TRPDx, and then save the data.
	local index = tonumber(tag:match( "TRPD(%d+)" ))
	if not index then return end
	
	if TRP3_API then
		-- Catch unregistered unit. Maybe we should register them here? I'm not
		--  sure if you can do that without the Vernum.
		if not TRP3_API.register.isUnitIDKnown( user.name ) then
			return
		end
		
		if not TRP3_API.register.getUnitIDCurrentProfile( user.name ) then 
			return 
		end
		
		if type(data) == "string" then
			-- This might be a compressed string.
			data = TRP3_API.utils.serial.safeDecompressCodedStructure(data, {});
		end
		
		TRP3_API.register.saveInformation( user.name, INFO_TYPES[index], data );
	elseif Me.TRP_imp then
		
		TRP_imp.SaveProfileData( user, index, data )
		
	end
	Me.TRP_ClearNeedsUpdate( user.name, index )
end

Me.DataHandlers.TRPD1 = HandleTRPData
Me.DataHandlers.TRPD2 = HandleTRPData
Me.DataHandlers.TRPD3 = HandleTRPData
Me.DataHandlers.TRPD4 = HandleTRPData

-------------------------------------------------------------------------------
-- If the user has an obnoxiously long TRP, the timeouts might expire before
--  it's actually sent.
--
local function HandleDataProgress( user, tag, istext, data )
	local index = tonumber(tag:match( "TRPD(%d+)" ))
	if user.self then
		-- If we see ourself sending, update our last_sent blocker
		Me.TRP_last_sent[index] = GetTime()
	else
		-- If we see someone else sending, set our REQUEST_COOLDOWN cd, so
		--  we don't update them anytime soon.
		Me.TRP_request_times[user.name] = Me.TRP_request_times[user.name] or {}
		Me.TRP_request_times[user.name][index] = GetTime()
	end
end

Me.DataProgressHandlers.TRPD1 = HandleDataProgress
Me.DataProgressHandlers.TRPD2 = HandleDataProgress
Me.DataProgressHandlers.TRPD3 = HandleDataProgress
Me.DataProgressHandlers.TRPD4 = HandleDataProgress

-------------------------------------------------------------------------------
-- Request profile data from someone. This reads from Me.TRP_needs_update[user]
--  to see what we want to get from them. It's also safe to spam (from
--  mouseover and such) as it has a cooldown.
--
function Me.TRP_RequestProfile( name, parts )

	if TRP3_API then
		if not TRP3_API.register.isUnitIDKnown( name ) then return end
		if not TRP3_API.register.getUnitIDCurrentProfile( name ) then return end
	elseif Me.TRP_imp then
		if not Me.TRP_imp.IsPlayerKnown( name ) then return end
	else
		return
	end
	
--	if Me.TRP_request_times[name]
 --          and GetTime() - Me.TRP_request_times[name] < REQUEST_COOLDOWN then
--	--	return
	--end

	Me.TRP_request_times[name] = Me.TRP_request_times[name] or {}
	local rqt = Me.TRP_request_times[name]
	
	local data = ""
	local send = false
	
	for i = 1, 4 do
		if not parts[i] then
			data = data .. "0"
		elseif rqt[i] and GetTime() - rqt[i] < REQUEST_COOLDOWN then
			data = data .. "0"
		elseif Me.TRP_needs_update[name] and Me.TRP_needs_update[name][i] then
			rqt[i] = GetTime()
			data = data .. "1"
			send = true
		else
			data = data .. "0"
		end
		--data = data .. (Me.TRP_needs_update[name][i] and "1" or "0")
	end
	
	if send then
		Me.SendPacket( "TRPRQ", name .. ":" .. data )
	end
end

-------------------------------------------------------------------------------
-- Returns true if this unit cannot be communicated to by addon whispers. In
--  other words, we want to use our protocol on this person.
--
function Me.HordeOrXrealmPlayerUnit( unit )
	if UnitIsPlayer(unit) then
		if UnitFactionGroup( "mouseover" ) ~= UnitFactionGroup( "player" ) then
			return true
		end
		
		local rr = UnitRealmRelationship( unit )
		if rr == LE_REALM_RELATION_COALESCED then
			return true
		end
	end
end

-------------------------------------------------------------------------------
function Me.TRP_TryRequest( username, ... )
	if not Me.connected or not Me.relay_on then return end
	if not username then return end
	
	if Me.GetBnetInfo( username ) then return end -- Bnet friend.
	
	local user = Me.crossrp_users[username]
	if not user then return end
	
	if user.horde or user.xrealm then
		local parts = {}
		for k, v in pairs( {...} ) do
			parts[v] = true
		end
		
		Me.TRP_RequestProfile( username, parts )
	end
end

-------------------------------------------------------------------------------
-- When we interact with people through mouseover, targeting, or opening their
--  profile, we request different parts of their profile. TRP_needs_update
--  erases its entries after we receive the data.
--
function Me.OnMouseoverUnit()
	local username = Me.GetFullName( "mouseover" )
	Me.TRP_TryRequest( username, UPDATE_CHAR, UPDATE_CHS )
end

function Me.OnTargetChanged()
	local username = Me.GetFullName( "target" )
	Me.TRP_TryRequest( username, UPDATE_CHAR, UPDATE_CHS, UPDATE_MISC )
end

function Me.OnProfileOpened( username )
	Me.TRP_TryRequest( username, UPDATE_CHAR, UPDATE_CHS, 
	                                                UPDATE_MISC, UPDATE_ABOUT )
end

-------------------------------------------------------------------------------
-- Called after we connect to the relay stream.
--
function Me.TRP_OnConnected()
--	if not TRP3_API then return end
	if not Me.relay_on then return end
	
	-- We dont do delay here so we can fit this message in with HENLO.
	Me.TRP_SendVernum()
end

-------------------------------------------------------------------------------
function Me.TRP_Init()
	
	Me:RegisterEvent( "UPDATE_MOUSEOVER_UNIT", Me.OnMouseoverUnit )
	Me:RegisterEvent( "PLAYER_TARGET_CHANGED", Me.OnTargetChanged )
	
	if TRP3_API then
		EXCHANGE_DATA_FUNCS = {
			TRP3_API.register.player.getCharacteristicsExchangeData;
			TRP3_API.register.player.getAboutExchangeData;
			TRP3_API.register.player.getMiscExchangeData;
			TRP3_API.dashboard.getCharacterExchangeData;
		}
		
		INFO_TYPES = {
			TRP3_API.register.registerInfoTypes.CHARACTERISTICS;
			TRP3_API.register.registerInfoTypes.ABOUT;
			TRP3_API.register.registerInfoTypes.MISC;
			TRP3_API.register.registerInfoTypes.CHARACTER;
		}
		
		TRP3_API.Events.registerCallback( TRP3_API.Events.REGISTER_DATA_UPDATED, 
			function( player_id, profileID )
				if player_id == TRP3_API.globals.player_id then
				
					if Me.connected and Me.relay_on then
						Me.Timer_Start( "trp_vernums", "push", 
						               VERNUM_UPDATE_DELAY, Me.TRP_SendVernum )
					end
				end
			end)
			
		TRP3_API.Events.registerCallback( TRP3_API.Events.REGISTER_PROFILE_OPENED,
			function( context )
				if context.source == "directory" then
				
					local profile_id  = context.profileID
					local unit_id     = context.unitID
					local has_unit_id = context.openedWithUnitID
					
					if has_unit_id then
						-- Definitely have a unit ID
						Me.OnProfileOpened( unit_id )
						return
					elseif unit_id then
						-- Maybe have a unit ID, double check with our registry.
						if Me.crossrp_users[unit_id] then
							Me.OnProfileOpened( unit_id )
							return
						end
					end
					
					local profile = TRP3_API.register.getProfile(profile_id)
					local best_match, best_time = nil, 900
					for k,v in pairs( profile.link or {} ) do
						if Me.crossrp_users[k] 
						          and Me.crossrp_users[k].time < best_time then
							-- We saw this character using cross RP, but they 
							--  might have switched characters while using the
							--  same profile, so we'll still search to see if
							--  there's a shorter idle time in here.
							best_match = k
							best_time  = Me.crossrp_users[k].time
						end
					end
					
					if best_match then
						Me.OnProfileOpened( best_match )
					end
				end
				Me.DebugLog2( "REGISTER_PROFILE_OPENED", context.unitID )
			end)
	else
		Me.TRP_imp.Init()
	end
end
