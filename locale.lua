-------------------------------------------------------------------------------
-- Some nice localization to make those other people in the world feel right
--  at home too.
-------------------------------------------------------------------------------

local _, Me = ...

-------------------------------------------------------------------------------
-- First of all, we have this table filled with localization strings.
-- In bigger projects, this can get quite massive. We don't have that many
-- strings, but we'll still use some decent practices so we don't have a bunch 
-- of stuff lying around in memory;
local Locales = {} -- For example, we'll delete this big table after 
Locales.enUS = {      --  we get what we want from it.
	CROSS_RP = "Cross RP";
	CONNECTED_TO_SERVER = "|cFF03FF11Connected to {1}";
	DISCONNECT = "Disconnect";
	DISCONNECT_TOOLTIP = "Disconnect from the relay server.";
	RELAY = "Relay";
	RELAY_TIP = "While the relay is active, your /say, /emote, and /yell are logged by everyone. Turn it off for privacy.";
	CONNECT = "Connect";
	CONNECT_TOOLTIP = "Connect to an RP relay!";
	NO_SERVERS_AVAILABLE = "No servers available.";
	RP_CHANNELS = "RP Channels";
	RP_CHANNELS_TOOLTIP = "Select which RP channels you want to listen to in your chat boxes.";
	RP_IS_MUTED = "RP Is Muted";
	RP_IS_MUTED_TOOLTIP = "When RP is muted, normal community members cannot post in /rp. They can still post in /rp2-9.";
	SETTINGS = "Settings";
	SETTINGS_TIP = "Open Interface options panel.";
	CONNECT_TO_SERVER_TOOLTIP = "Click to connect.";
	RP_WARNING = "RP Warning";
	RP_WARNING_TOOLTIP = "The global alert channel. This is accessed by community Leaders only with /rpw.";
	RP_CHANNEL = "RP Channel";
	RP_CHANNEL_X = "RP Channel {1}";
	RP_CHANNEL_1_TOOLTIP = "The global RP channel for this community. May be limited to announcements only. Access through /rp.";
	RP_CHANNEL_X_TOOLTIP = "Channels 2-9 are meant for smaller sub-groups. Access through /rp#.";
	MINIMAP_TOOLTIP_LEFTCLICK = "|cff00ff00Left-click|r to open menu.";
	MINIMAP_TOOLTIP_RIGHTCLICK = "|cff00ff00Right-click|r for options.";
	VERSION_LABEL = "Version: {1}";
	BY_AUTHOR = "by Tammya-MoonGuard";
	OPTION_MINIMAP_BUTTON = "Show Minimap Button";
	OPTION_MINIMAP_BUTTON_TIP = "Show or hide the minimap button (if you're using something else like Titan Panel to access it).";
	OPTION_TRANSLATE_CHAT_BUBBLES = "Translate Chat Bubbles";
	OPTION_TRANSLATE_CHAT_BUBBLES_TIP = "Try and translate chat bubbles alongside text.";
	OPTION_WHISPER_BUTTON = "Whisper Button";
	OPTION_WHISPER_BUTTON_TIP = "Adds a \"Whisper\" button when right-clicking on players from opposing faction if they're Battle.net friends. This may or may not break some things in the Blizzard UI, and you don't need it to /w someone cross-faction.";
	OPTION_INDICATOR = "Show Relay Indicator";
	OPTION_INDICATOR_TIP = "Enables/disables the relay indicator at the top of the screen. This is meant to be visible and obnoxious to REMIND YOU THAT YOUR PUBLIC CHAT (/SAY, /EM, /YELL) IS BEING LOGGED BY EVERYONE IN THE COMMUNITY.";
	OPTION_CHAT_COLORS = "Chat Colors";
	
	CONNECTED_MESSAGE = "Connected to {1}.";
	RELAY_NOTICE = "Relay Enabled. Please keep in mind that your /say, /emote, and /yell are now logged by everyone in the community. Turn it off using the minimap button if you want some privacy.";
	RELAY_DISABLED = "Relay Disabled.";
	INDICATOR_CONNECTED = "Relay Active – {1}"; -- no period
	DISCONNECTED_FROM_SERVER = "Disconnected from {1}.";
	WHISPER_UNVERIFIED = "(Unverified!)";
	POLICE_POSTING_YOUR_NAME = "[CROSS RP POLICE!] {1} is posting under YOUR character name.";
	POLICE_POSTING_LOCKED_NAME = "[CROSS RP POLICE!] {1} is trying to post under a name in-use already.";
	CANNOT_SEND_TO_CHANNEL = "Cannot send chat to that channel.";
	RP_CHANNEL_IS_MUTED = "RP Channel is muted. Only moderators can post.";
	CANT_POST_RPW = "Only leaders can post in RP Warning.";
	WHISPER = "Whisper";
	WHISPER_TIP = "Whisper opposing faction. (This is sent safely over a direct Battle.net whisper, privately, and doesn't use the community relay.)";
	TRAFFIC = "Traffic";
	KBPS = "KB/s";
	BPS = "B/s";
	UNKNOWN_SERVER = "(Unknown)";
	RELAY_ACTIVE = "Relay Active!";
	NOT_CONNECTED = "Not Connected";
	LOCKED_NOTE = "(Locked)";
	RELAY_OFF_WARNING = "Cross RP\n\nYou received a translated message from someone nearby, but your relay is off. Do you want to turn it on?";
	CONNECT_POPUP = "{1} is using Cross RP in this area. Would you like to connect to them?";
};

---------------------------------------------------------------------------
-- Other languages imported from Curse during packaging.
---------------------------------------------------------------------------

--[===[@non-debug@

Locales.frFR = 
--@localization(locale="frFR", format="lua_table", handle-unlocalized="ignore")@
Locales.deDE = 
--@localization(locale="deDE", format="lua_table", handle-unlocalized="ignore")@
Locales.itIT = 
--@localization(locale="itIT", format="lua_table", handle-unlocalized="ignore")@
Locales.koKR = 
--@localization(locale="koKR", format="lua_table", handle-unlocalized="ignore")@
Locales.zhCN = 
--@localization(locale="zhCN", format="lua_table", handle-unlocalized="ignore")@
Locales.zhTW = 
--@localization(locale="zhTW", format="lua_table", handle-unlocalized="ignore")@
Locales.ruRU = 
--@localization(locale="ruRU", format="lua_table", handle-unlocalized="ignore")@
Locales.esES = 
--@localization(locale="esES", format="lua_table", handle-unlocalized="ignore")@
Locales.esMX = 
--@localization(locale="esMX", format="lua_table", handle-unlocalized="ignore")@
Locales.ptBR = 
--@localization(locale="ptBR", format="lua_table", handle-unlocalized="ignore")@

--@end-non-debug@]===]


-------------------------------------------------------------------------------
-- What we do now is take the enUS table, and then merge it with whatever
-- locale the client is using. Just paste it on top, and any untranslated
local locale_strings = Locales.enUS  -- strings will remain English.

do
	local client_locale = GetLocale() -- Gets the WoW locale.
	
	-- Skip this if they're using the English client, or if we don't support
	-- the locale they're using (no strings defined).
	if client_locale ~= "enUS" and Locales[client_locale] then
		-- Go through the foreign locale strings and overwrite the English
		--  entries. I hate using the word "foreign"; it seems like I'm
		--  treating non-English speakers as aliens, ehe...
		for k, v in pairs( Locales[client_locale] ) do
			locale_strings[k] = v
		end
	end
end

-------------------------------------------------------------------------------
-- Now we've got our merged table, so we can throw away the original data for
Locales = nil -- everything. Just blow up this old Locales table.

-------------------------------------------------------------------------------
-- And here we have the main Locale API. It's simple, but has some cool
Me.Locale = setmetatable( {}, { -- features. Normally, this table will be 
                                  --  stored in a local variable called L.

	-- If we access it like L["KEY"] or L.KEY then it's a direct lookup into
	--  our locale table. If it doesn't exist, then it uses the key directly.
	__index = function( table, key ) -- Most of the translations' keys are
		return locale_strings[key]   --  literal English translations.
		       or key
	end;
	
	-- If we treat the locale table like a function, then we can do 
	--  substitutions, like `L( "string {1}", value )`.
	__call = function( table, key, ... )
		-- First we get the translation. Note this isn't a raw access, so
		key = table[key] -- this goes through the __index metamethod 
		                 -- too if it doesn't exist.
		-- Pack args into a table; iterate over them.
		local args = {...}
		for i = 1, #args do
			-- And replace {1}, {2} etc with them.
			key = key:gsub( "{" .. i .. "}", args[i] )
		end
		return key
	end;
})
