-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- For fetching data from our information server, such as announcements,
--  addon versions, and network links.
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

-------------------------------------------------------------------------------
-- List of Cross RP network links. Can also contain other special links to
--  ongoing server events. The ordering matches what appears in the MOTD data.
Me.motd_links = {}

-------------------------------------------------------------------------------
-- Kind of out of place here, but we do define the link fetching and storing
--  in this file. This prints a clickable link to the chat to join the public
--  networks.
function Me.PrintLinkToChat( link )
	-- In the future we might also allow normal communities to host Cross RP.
	-- Right now that's hardcoded otherwise.
	Me.DebugLog2( "Printing link.", link.code, link.name )
	local link_text = GetClubTicketLink( link.code, link.name, 
	                                                  Enum.ClubType.BattleNet )
	Me.Print( link_text )
end

-------------------------------------------------------------------------------
-- Makes a request to the servers for our MOTD data. This contains stuff like
--  the latest Cross RP version, the required version, network links, and of
--                                    course, "MOTD" style announcements.
function Me.ShowMOTD()
	
	-- Fetch realm data. The messages are region specific, and we should also
	--                                             handle different locales.
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

-------------------------------------------------------------------------------
-- Callback for receiving data from the community server. Parses data and 
--                                                        prints MOTD messages.
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
	
	-- Parse any links
	wipe( Me.motd_links )
	message:gsub( "{link}%s*(%S+)%s+([^{]+)", function( code, name )
		table.insert( Me.motd_links, {
			name = name:match( "(.-)%s*$" );
			code = code;
		})
	end)

	message:gsub( "{msg}%s*([+=-])(%d+%.%d+%.%d+%S*)%s+([^{]+)", 
		function( version_operator, version, text )
			version = Me.GetVersionCode( version )
			if not version then return end
		
			if version_operator == "=" and myversion == version
			       or version_operator == "-" and myversion <= version
			            or version_operator == "+" and myversion >= version then
				
				text = text:match( "(.-)%s*$" )
				Me.Print( text )
			end
		end)
end

-------------------------------------------------------------------------------
-- Helper function to convert a version string to a single number value, so you
--  can make comparisons to other versions. Format can be "x.y.z" or "x.y.z.w".
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
