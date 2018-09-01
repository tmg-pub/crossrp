-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- For showing the startup message of the day.
-------------------------------------------------------------------------------
local _, Me        = ...
local L            = Me.Locale
local LibRealmInfo = LibStub("LibRealmInfo")
-------------------------------------------------------------------------------
-- Typically, the message of the day should be nothing. Humans ignore things 
--  that are regular occurrences, so the this should be used for temporary,
--  important announcements only.
-------------------------------------------------------------------------------
Me.MOTD_TICKETS = {
	["US-enUS"] = "bnzWziz97"; -- Cross RP Support
	["EU-enUS"] = "Zvm40YH2mG"; -- Cross RP Info EU
}

function Me.ShowMOTD()
	
	-- Fetch realm data. The messages are region specific, and we should also
	--  handle different locales.
	local _,_,_,_,_,_, user_region = 
		                    LibRealmInfo:GetRealmInfoByGUID(UnitGUID("player"))
	local user_locale = GetLocale()
	
	local key = user_region .. "-" .. user_locale
	if not Me.MOTD_TICKETS[key] then
		key = user_region .. "-" .. "enUS"
		if not Me.MOTD_TICKETS[key] then
			Me.DebugLog2( "MOTD not supported.", user_region, user_locale )
			-- This region or locale isn't supported.
			return
		end
	end
	
	Me.DebugLog2( "Requesting MOTD.", user_region, user_locale )
	
	-- Fetch MOTD from our community server.
	LibClubMessage.Request( Me.MOTD_TICKETS[key], Me.OnGetMOTDData )
end

function Me.OnGetMOTDData( message )
	Me.DebugLog2( "Got MOTD data.", message )
	local myversion = Me.GetVersionCode( GetAddOnMetadata( "CrossRP", "Version" ) )
	if not myversion then
		error( "Invalid version code in TOC." )
	end
	
	local latest = message:match( "{new}%s*(%d+%.%d+%.%d+%S*)" )
	if latest then
		-- Save latest version
	end
	
	local required = message:match( "{req}%s*(%d+%.%d+%.%d+%S*)" )
	if required then
		required = Me.GetVersionCode( required )
		if required then
			if myversion < required then
				Me.Print( L.VERSION_TOO_OLD )
				
				if latest then
					Me.PrintL( L.LATEST_VERSION, latest )
				end
			end
		end
	end

	message:gsub( "{msg}%s*([<=>])(%d+%.%d+%.%d+%S*)%s+([^{]+)", 
		function( version_operator, version, text )
			version = Me.GetVersionCode( version )
			if not version then return end
		
			if version_operator == "=" and myversion == version
			       or version_operator == "<" and myversion < version
			            or version_operator == ">" and myversion > version then
				
				text = text:match( "(.-)%s*$" )
				Me.Print( text )
			end
		end)
end

function Me.GetVersionCode( text )
	local major, phase, minor, revision = 
	                            text:match("^%s*(%d+)%.(%d+)%.(%d+)%.(%d+)%s*$")
	if not major then
		major, phase, minor = text:match("^%s*(%d+)%.(%d+)%.(%d+)%s*$")
		revision = 0
		if not major then
			-- Invalid version code.
			return
		end
	end
	
	return tonumber(major) * 1000000000 + tonumber(phase) * 1000000 
	       + tonumber(minor) * 1000 + tonumber(revision)
end
