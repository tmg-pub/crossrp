
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

Me.TRP_needs_update = {}

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

-- we send this whenever we change anything, and then every 
--  60 seconds to catch people who missed it
function Me.TRP_SendVernum()	
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
	if update_chs then
		
end

function Me.TRP_SendProfile( parts )
	local 
	
	--TRP3_API.register.player.getCharacteristicsExchangeData
	--TRP3_API.register.player.getAboutExchangeData
	--TRP3_API.register.player.getMiscExchangeData
	--TRP3_API.dashboard.getCharacterExchangeData
	
end

function Me.TRP_RequestProfile( 

function Me.OnMouseoverChanged()
	
end

function Me.TRP_Init()
	Me:RegisterEvent( "MOUSEOVER_UPDATE", Me.OnMouseoverUnit )
end
