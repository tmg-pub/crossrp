
local _, Me = ...


local VERNUM_VERSION           = 1
local VERNUM_VERSION_TEXT      = 2
local VERNUM_PROFILE           = 3
local VERNUM_CHS_V             = 4
local VERNUM_ABOUT_V           = 5
local VERNUM_MISC_V            = 6
local VERNUM_CHAR_V            = 7
local VERNUM_TRIAL             = 8

local UPDATE_CHS    = 1
local UPDATE_ABOUT  = 2
local UPDATE_MISC   = 3
local UPDATE_CHAR   = 4

local SEND_COOLDOWN = 20.0
local VERNUM_REFRESH_TIME = 30.0
local REQUEST_COOLDOWN = 15.0

Me.TRP_needs_update = {} -- what players we see out of data
Me.TRP_sending = {}     -- what we are about to send
Me.TRP_last_sent = 0    -- last time we sent our profile
Me.TRP_request_cds = {} -- cooldowns for requesting data from players

-- PROTOCOL
-- TRPV:a:b:c:d:e:f:g:h
--  a,b,c,d,e,f,g,h = vernum entries
-- TRPRQ:user:abcd
--  a: request chs (if == "1")
--  b: request about
--  c: request misc
--  d: request char
-- TRPD:I:page/pages:packed_data
--  I = data index (chs/about/misc/char)

function Me.TRP_SetNeedsUpdate( user, slot )
	Me.TRP_needs_update[user] = Me.TRP_needs_update[user] or {}
	Me.TRP_needs_update[user][slot] = true
end

function Me.TRP_ClearNeedsUpdate( user, slot )
	if not Me.TRP_needs_update[user] then return end
	Me.TRP_needs_update[user][slot] = nil
	for k, v in pairs( Me.TRP_needs_update[user] ) do
		return
	end
	Me.TRP_needs_update[user] = nil
end

-- we send this whenever we change anything, and then every 
--  60 seconds to catch people who missed it
function Me.TRP_SendVernum()	
	Me.TRP_last_sent_vernum = GetTime()
	local query = {
		TRP3_API.globals.version; -- number
		TRP3_API.globals.version_display; -- string
		TRP3_API.profile.getPlayerCurrentProfileID() or ""; -- string
		TRP3_API.profile.getData( "player/characteristics" ).v or 0;
		TRP3_API.profile.getData( "player/about" ).v or 0;
		TRP3_API.profile.getData( "player/misc" ).v or 0;
		TRP3_API.profile.getData( "player/character" ).v or 1;
		TRP3_API.globals.isTrialAccount and 1 or 0; -- true/nil
	}
	query = table.concat( query, ":" )
	Me.SendPacket( "TRPV", query )
end

function Me.TRP_RefreshVernum()
	if not Me.connected then return end
	C_Timer.After( VERNUM_REFRESH_TIME, Me.TRP_RefreshVernum )
	
	if GetTime() - Me.TRP_last_sent_vernum >= VERNUM_REFRESH_TIME then
		 Me.TRP_SendVernum()
	end
end

function Me.ProcessPacket.TRPV( user, msg )
	local args = {}
	for v in msg:gmatch( "[^:]*" ) do
		table.insert( args, v )
	end
	
	args[VERNUM_VERSION] = tonumber(args[VERNUM_VERSION]) -- version
	args[VERNUM_CHS_V] = tonumber(args[VERNUM_CHS_V]) --characteristics.v
	args[VERNUM_ABOUT_V] = tonumber(args[VERNUM_ABOUT_V]) --about.v
	args[VERNUM_MISC_V] = tonumber(args[VERNUM_MISC_V]) --misc.v
	args[VERNUM_CHAR_V] = tonumber(args[VERNUM_CHAR_V]) --character.v
	args[VERNUM_TRIAL] = args[VERNUM_TRIAL] == "1" and true or nil
	
	if not args[VERNUM_VERSION] or not args[VERNUM_CHS_V]
			or not args[VERNUM_ABOUT_V] or not args[VERNUM_MISC_V] 
			or not args[VERNUM_CHAR_V] then 
		return 
	end
	
	TRP3_API.register.saveClientInformation( user.name, TRP3_API.globals.addon_name, args[VERNUM_VERSION_TEXT], false, nil, args[VERNUM_TRIAL] )
	TRP3_API.register.saveCurrentProfileID( user.name, args[VERNUM_PROFILE] )
	
	if TRP3_API.register.shouldUpdateInformation( user.name, TRP3_API.register.registerInfoTypes.CHARACTERISTICS, args[VERNUM_CHS_V] ) then
		Me.TRP_SetNeedsUpdate( user.name, UPDATE_CHS )
	end
	
	if TRP3_API.register.shouldUpdateInformation( user.name, TRP3_API.register.registerInfoTypes.ABOUT, args[VERNUM_ABOUT_V] ) then
		Me.TRP_SetNeedsUpdate( user.name, UPDATE_ABOUT )
	end
	
	if TRP3_API.register.shouldUpdateInformation( user.name, TRP3_API.register.registerInfoTypes.MISC, args[VERNUM_MISC_V] ) then
		Me.TRP_SetNeedsUpdate( user.name, UPDATE_MISC )
	end
	
	if TRP3_API.register.shouldUpdateInformation( user.name, TRP3_API.register.registerInfoTypes.CHARACTER, args[VERNUM_CHAR_V] ) then
		Me.TRP_SetNeedsUpdate( user.name, UPDATE_CHAR )
	end
end

function Me.ProcessPacket.TRPRQ( user, msg )
	local update_chs, update_about, update_misc, update_char = msg:match( "^(%d)(%d)(%d)(%d)" )
	local parts = {}
	
	if update_chs then Me.TRP_sending.chs = true end
	if update_about then Me.TRP_sending.about = true end
	if update_misc then Me.TRP_sending.misc = true end
	if update_char then Me.TRP_sending.char = true end
	
	Me.TRP_StartSending()
end

function Me.TRP_SendProfile()
	Me.TRP_last_sent = GetTime()
	
	if Me.TRP_sending.chs then
		local data = TRP3_API.register.player.getCharacteristicsExchangeData()
		Me.SendData( "TRP1", data )
		Me.TRP_sending.chs = false
	end
	
	if Me.TRP_sending.about then
		TRP3_API.register.player.getAboutExchangeData()
		Me.SendData( "TRP2", data )
		Me.TRP_sending.chs = false
	end
	
	if Me.TRP_sending.misc then
		TRP3_API.register.player.getMiscExchangeData()
		Me.SendData( "TRP3", data )
		Me.TRP_sending.chs = false
	end
	
	if Me.TRP_sending.char then
		TRP3_API.dashboard.getCharacterExchangeData()
		Me.SendData( "TRP4", data )
		Me.TRP_sending.chs = false
	end
end

function Me.TRP_StartSending()
	if Me.TRP_sending_timer then return end
	Me.TRP_sending_timer = true
	
	local time = Me.TRP_last_sent + SEND_COOLDOWN - GetTime()
	if time < 0.1 then time = 0.1 end
	
	C_Timer.After( time, function()
		Me.TRP_sending_timer = false
		Me.TRP_SendProfile()
	end)
end

table.insert( Me.DataHandlers, function( user, tag, istext, data )
	if tag == "TRP1" then
		TRP3_API.register.saveInformation( user.name, TRP3_API.register.registerInfoTypes.CHARACTERISTICS, data );
		Me.TRP_ClearNeedsUpdate( user.name, UPDATE_CHS )
	elseif tag == "TRP2" then
		TRP3_API.register.saveInformation( user.name, TRP3_API.register.registerInfoTypes.ABOUT, data );
		Me.TRP_ClearNeedsUpdate( user.name, UPDATE_ABOUT )
	elseif tag == "TRP3" then
		TRP3_API.register.saveInformation( user.name, TRP3_API.register.registerInfoTypes.MISC, data );
		Me.TRP_ClearNeedsUpdate( user.name, UPDATE_MISC )
	elseif tag == "TRP4" then
		TRP3_API.register.saveInformation( user.name, TRP3_API.register.registerInfoTypes.CHARACTER, data );
		Me.TRP_ClearNeedsUpdate( user.name, UPDATE_CHAR )
	end
end)

function Me.TRP_RequestProfile( user )
	if Me.TRP_request_cds[user] and GetTime() - Me.TRP_request_times[user] < REQUEST_COOLDOWN then
		return
	end
	Me.TRP_request_times[user] = GetTime()
	
	local data = ""
	for i = 1, 4 do
		data = data .. Me.TRP_needs_update[user][i] and "1" or "0"
	end
	
	Me.SendPacket( "TRPRQ", data )
end

function Me.OnMouseoverUnit()
	if not Me.connected then return end
	if UnitIsPlayer( "mouseover" ) then
		if UnitFactionGroup( "mouseover" ) ~= UnitFactionGroup( "player" ) then
			if Me.TRP_needs_update[user] then
				Me.TRP_RequestProfile( user )
			end
		end
	end
end

function Me.TRP_OnConnected()
	Me.TRP_SendVernum()
	C_Timer.After( VERNUM_REFRESH_TIME, Me.TRP_RefreshVernum )

end

function Me.TRP_Init()
	Me:RegisterEvent( "UPDATE_MOUSEOVER_UNIT", Me.OnMouseoverUnit )
end
