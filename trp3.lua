
local _, Me = ...

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

-------------------------------------------------------------------------------
-- Indexes of parts that need updates. We use the word `update` a bunch where
--  it means a registry slice.
--
local UPDATE_CHS    = 1
local UPDATE_ABOUT  = 2
local UPDATE_MISC   = 3
local UPDATE_CHAR   = 4
local UPDATE_SLOTS  = 4

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
local REQUEST_IGNORE_PERIOD = 3.0  -- Seconds to wait before we accept new
                                   --  requests for an update slot we just
								   --  sent.
VERNUM_HENLO_DELAY = 1.0  -- DEBUG
VERNUM_HENLO_VARIATION = 1.0 
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
	if not TRP3_API then return end
	
	-- Store empty profile as "-" in the protocol.
	local profile_id = TRP3_API.profile.getPlayerCurrentProfileID()
	if not profile_id or profile_id == "" then profile_id = "-" end
	
	Me.TRP_last_sent_vernum = GetTime()
	local query = table.concat( {
		TRP3_API.globals.version; -- a number
		TRP3_API.globals.version_display; -- a string
		profile_id; -- a string
		TRP3_API.profile.getData( "player/characteristics" ).v or 0;
		TRP3_API.profile.getData( "player/about" ).v or 0;
		TRP3_API.profile.getData( "player/misc" ).v or 0;
		TRP3_API.profile.getData( "player/character" ).v or 1;
		TRP3_API.globals.isTrialAccount and 1 or 0; -- true/nil
	}, ":" )
	
	Me.SendPacket( "TRPV", query )
end

-------------------------------------------------------------------------------
-- Currently only being called from the login command from others. We add a
--  long delay here because it isn't urgent at all and want to hit as many
--  people as possible.
--
function Me.TRP_SendVernumDelayed()
	if not TRP3_API then return end
	Me.Timer_Start( "trp_vernums", "ignore", 
	               VERNUM_HENLO_DELAY + math.random(0, VERNUM_HENLO_VARIATION), 
				   Me.TRP_SendVernum )
end

-------------------------------------------------------------------------------
-- Receiving Vernum from someone.
--
function Me.ProcessPacket.TRPV( user, command, msg )
	if not TRP3_API then return end
	if user.self then return end
	
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
	args[VERNUM_TRIAL] = args[VERNUM_TRIAL] == "1" and true or nil
	if args[VERNUM_PROFILE] == "-" then args[VERNUM_PROFILE] = "" end
	
	if not args[VERNUM_VERSION] or not args[VERNUM_CHS_V]
			or not args[VERNUM_ABOUT_V] or not args[VERNUM_MISC_V] 
			or not args[VERNUM_CHAR_V] then 
		
		return 
	end
	
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
end

-------------------------------------------------------------------------------
-- This is a data request from someone.
--
function Me.ProcessPacket.TRPRQ( user, command, msg )
	if user.self then return end
	if not user.horde and not user.xrealm then 
		-- local player, don't use this protocol.
		return
	end
	
	local target, a, b, c, d = msg:match( "^([^:]+):(%d)(%d)(%d)(%d)" )
	if not target then return end
	if target ~= Me.fullname then 
		-- (Not targeting us.)
		return
	end
	
	local parts = { a, b, c, d }
	for i = 1, UPDATE_SLOTS do
		if parts[i] == "1" then
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
		end
	end
	
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
	if not TRP3_API then return end
	
	for i = 1, UPDATE_SLOTS do
		if Me.TRP_sending[i] then
			Me.TRP_sending[i] = nil
			Me.TRP_last_sent[i] = GetTime()
			local data = EXCHANGE_DATA_FUNCS[i]()
			Me.SendData( "TRPD" .. i, data )
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
	
	-- Parse out the index from the tag TRPDx, and then save the data.
	local index = tonumber(tag:match( "TRPD(%d+)" ))
	if not index then return end
	TRP3_API.register.saveInformation( user.name, INFO_TYPES[index], data );
	Me.TRP_ClearNeedsUpdate( user.name, index )
end

Me.DataHandlers.TRPD1 = HandleTRPData
Me.DataHandlers.TRPD2 = HandleTRPData
Me.DataHandlers.TRPD3 = HandleTRPData
Me.DataHandlers.TRPD4 = HandleTRPData

-------------------------------------------------------------------------------
-- Request profile data from someone. This reads from Me.TRP_needs_update[user]
--  to see what we want to get from them. It's also safe to spam (from
--  mouseover and such) as it has a cooldown.
--
function Me.TRP_RequestProfile( name )

	if not TRP3_API.register.isUnitIDKnown( name ) then return end
	if not TRP3_API.register.getUnitIDCurrentProfile( name ) then return end
	
	if Me.TRP_request_times[name] 
           and GetTime() - Me.TRP_request_times[name] < REQUEST_COOLDOWN then
		return
	end

	Me.TRP_request_times[name] = GetTime()
	
	local data = ""
	for i = 1, 4 do
		data = data .. (Me.TRP_needs_update[name][i] and "1" or "0")
	end
	
	Me.SendPacket( "TRPRQ", name .. ":" .. data )
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
		
		local name, realm = Me.GetFullName( unit )
		local xrealm = realm ~= Me.realm
		for _, v in pairs( GetAutoCompleteRealms() ) do	
			if v == realm then
				-- This isn't our realm, but it's linked.
				xrealm = false
			end
		end
		
		return xrealm
	end
end

-------------------------------------------------------------------------------
-- When we mouseover someone, we request their data. TRP_needs_update erases
--  its entries after we receive the data.
--
function Me.OnMouseoverUnit()
	if not Me.connected then return end
	if Me.HordeOrXrealmPlayerUnit( "mouseover" ) then
		local name = Me.GetFullName( "mouseover" )
		if Me.TRP_needs_update[name] then
			Me.TRP_RequestProfile( name )
		end
	end
end

-------------------------------------------------------------------------------
-- Called after we connect to the relay stream.
--
function Me.TRP_OnConnected()
	if not TRP3_API then return end
	
	-- We dont do delay here so we can fit this message in with HENLO.
	Me.TRP_SendVernum()
end

-------------------------------------------------------------------------------
function Me.TRP_Init()
	if not TRP3_API then return end
	Me:RegisterEvent( "UPDATE_MOUSEOVER_UNIT", Me.OnMouseoverUnit )
	
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
	
	TRP3_API.events.listenToEvent( TRP3_API.events.REGISTER_DATA_UPDATED, 
		function( player_id, profileID )
			if player_id == TRP3_API.globals.player_id then
			
				if Me.connected then
					Me.Timer_Start( "trp_vernums", "push", VERNUM_UPDATE_DELAY,
									Me.TRP_SendVernum )
				end
			end
		end)
end
