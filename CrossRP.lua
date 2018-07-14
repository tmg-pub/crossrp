-------------------------------------------------------------------------------
-- Cross RP
-- by Tammya-MoonGuard (2018)
--
-- All Rights Reserved
--
-- Turns a Battle.net community into a relay channel for friends to communicate
--  cross-faction for some super fun RP time!
--
-- Project concerns and goals:
--  * Easy setup - anyone should easily understand what they need to do to
--     setup a relay for their RP event.
--  * Privacy - emphasis on care for privacy on some features, as some people
--     might not understand how the relay and message logging works.
--  * Seamless translations when talking to players of opposing faction.
--     Everything should be invisible and chat bubbles are updated too. In
--     other words, once you're connected, everything should seem natural.
--  * RP profiles - one of the biggest divides between cross-faction RP, 
--     solved! This should bridge cross-realm too.
--  * Efficient protocol - we don't want to be using too much data on the 
--     logged community servers.
--  * Respect for the faction divide. We don't want this to be an "exploit".
--     We're merely using the features that are offered to us, i.e. the 
--     Battle.net community chat.
-------------------------------------------------------------------------------

local AddonName, Me = ...
local L             = Me.Locale
local Gopher        = LibGopher

-------------------------------------------------------------------------------
-- Exposed to the outside world as CrossRP. It's an easy way to see if the
--              addon is installed.
CrossRP = Me
-------------------------------------------------------------------------------
-- Embedding AceAddon into it. I like the way AceHook handles hooks and it 
--  leaves everything a bit neater for us. We'll embed that and AceEvent
--                                  for the slew of events that we handle.
LibStub("AceAddon-3.0"):NewAddon( Me, AddonName, 
                                        "AceEvent-3.0", "AceHook-3.0" )
-------------------------------------------------------------------------------
-- Our main connection settings. `connected` is when we have a server selected.
--  When `connected` is true, `club` is set with the club ID of our server of 
--  choice, and `stream` is set with the stream ID of the RELAY channel.
-- Connected just means that we're parsing messages from that server. It's
--  strictly and deliberately one-sided. Only when `relay_on` is set do we
Me.connected = false  -- actually send any data. `connected` is reading;
Me.relay_on  = false  --  `relay_on` is writing.
Me.club      = nil
Me.stream    = nil
-------------------------------------------------------------------------------
-- There's a trust system in play during normal operation. There's no way to
--  easily verify when a person on the Bnet community claims they're someone.
-- An example of something bad that can happen easily is someone on the 
--  community speaking as one of the moderators with nasty text. Hopefully
--  in a future patch we'll have more information other than a vague
--  (ambiguous, even) BattleTag name. In the end, you can just kick people
--  who misbehave from your community, but this little thing helps identify
--  them. Whenever you get data from someone, the name they're posting under
--  gets locked to that ID. If another person tries to use that name with their
--  different account, Cross RP ignores that message and prints a warning.
-- [username] = bnetAccountID
-- `username` is used often throughout the code. It's a full character name.
--                  e.g. "Tammya-MoonGuard" – properly capitalized.
Me.name_locks = {}
-------------------------------------------------------------------------------
-- When we add messages into the chatbox, we need a lineid for them. I'd prefer
--  to just use line ID `0`, but that's going to need a patch in TRP's code to
--  work right. What we're doing right now is using a decrementing number so we
--  aren't selecting any valid messages. I'm not exactly sure how safe that is
--                    with the chat frame code, or with other addons.
Me.fake_lineid = -1
-------------------------------------------------------------------------------
-- We don't always have GUIDs for players, especially since we're getting their
--  messages over a Bnet channel, which uses bnetAccountIDs rather than GUIDs.
-- Whenever we do see a normal chat message, we log the name and GUID in here.
-- [username] = GUID
Me.player_guids = {}
-------------------------------------------------------------------------------
-- One of the design decisions was to use plain Bnet whispers rather than
--  "Game Data" (or an addon/hidden message) for when we reroute whispers to
--  the opposing faction. This is for two reasons. One, so that the message
--  is logged and everything like text. Two, so that if someone doesn't have
--  the addon, they can still see the whispered text. This of course comes with
--  a few problems, since there are multiple game accounts that could receive
--  the whisper, as well as you don't know who you're WHISPER_INFORM message
--  is for if someone is logged in on two accounts. This saves the name of who
--  you're whispering to. 
-- [bnetAccountId] = Character name
Me.bnet_whisper_names = {}
-------------------------------------------------------------------------------
-- This is to keep track of user data when we're handling incoming chat, both
--  from the relayed messages and normal ingame messages. It's only used for
--  characters from the opposing faction, for translations.
-- chat_data[username] = {...}
Me.chat_data = {
	-- last_orcish = The last orcish phrase they've said. We call any mangled
	--                text `orcish`, and this means Common on Horde side.
	-- last_event_time = The last time we received a public chat event from
	--                    them. This value is used as a filter. Messages from
	--                    public channels are only printed to chat when we
	--                    see a recent chat event from them, mixed together
	--                    with simple distance filtering encoded in the 
	--                    relay message.
	-- translations = Table of pending chat messages from the relay. If we
	--                 don't see any chat events for them, they get discarded
	--                 as they're out of range.
	--                   { time, map, x, y, type, message }
}
-------------------------------------------------------------------------------
-- A table indexed by username that tells us if we've received a Cross RP
--  addon message from this user during this session.
Me.crossrp_users = {}
-------------------------------------------------------------------------------
-- 5 seconds is a VERY generous value for this, and perhaps a little bit too
--  high. This is to account for some corner cases where someone is lagging
--  nearly to death. While this is a pretty big corner case, missing a chat
--  messages is terrible for the user experience. Once this period expires,
--  (from the time since last event) then the user is filtered again. We also
--  have distance encoded into the text, which helps to properly prune messages
--  that are out of range, but that doesn't account for vertical space.
local CHAT_TRANSLATION_TIMEOUT = 5
-------------------------------------------------------------------------------
-- The distances from a player where you can no longer hear their /say, /emote
--  or /yell. Testing showed something more like 198 or 199 for yell, but it 
--  may have just been from inaccuracies of the--my computer crashed right here
--  while typing. I need a new graphics card... Anyway, that may have just been
--  inaccuracies from measuring distance to an invisible/distance-phased
local CHAT_HEAR_RANGE      = 25.0   -- player. 
local CHAT_HEAR_RANGE_YELL = 200.0
-------------------------------------------------------------------------------
-- This is populated with club IDs when we detect players in our area using
--  Cross RP. If we open a popup for that, ths prevents it from being done
--                                             twice in the same session.
Me.club_connect_prompted = {}
Me.club_connect_prompt_shown = nil

-------------------------------------------------------------------------------
-- A simple helper function to return the name of the language the opposing
--                                                  faction uses by default.
local function HordeLanguage()
	return UnitFactionGroup( "player" ) == "Alliance" and "Orcish" or "Common"
end

-------------------------------------------------------------------------------
-- InWorld returns true when the player is in the open world and not in their
--  garrison. We don't want players to accidentally relay their garrison ERP.
local GARRISON_MAPS = {
	-- Horde-side garrison maps level 0-3.
	[1152] = true; [1330] = true; [1153] = true; [1154] = true;
	
	-- Alliance-side garrison maps level 0-3.
	[1158] = true; [1331] = true; [1159] = true; [1160] = true;
}

function Me.InWorld()
	if IsInInstance() then return false end
	-- Instance map IDs are a bit different from normal map IDs. Map IDs are
	--  for the world map display, where each section of the map has its own
	--  map ID. Instance IDs are the bigger encapsulation of these, and can
	--  also be referred to as a continent ID.
	local instanceMapID = select( 8, GetInstanceInfo() )
	if GARRISON_MAPS[instanceMapID] then return false end
	return true
end

-------------------------------------------------------------------------------
-- When we hear orcish, we outright block it if our connection is active.
--  In a future version we might have some time-outs where we allow the orcish
--                     to go through, but currently it's just plain discarded.
function Me.ChatFilter_Say( _, _, msg, sender, language )
	if Me.connected and language == HordeLanguage() then
		return true
	end
end

-------------------------------------------------------------------------------
-- This is for 'makes some strange gestures'. We want to block that too.
--  Localized strings are CHAT_EMOTE_UNKNOWN and CHAT_SAY_UNKNOWN.
--  CHAT_SAY_UNKNOWN is actually from /say. If you say something like
--  REEEEEEEEEEEEEEEEEE then it gets converted to an emote of you "saying
--                                            something unintelligible".
function Me.ChatFilter_Emote( _, _, msg, sender, language )
	if Me.connected and msg == CHAT_EMOTE_UNKNOWN 
	                                  or msg == CHAT_SAY_UNKNOWN then
		return true
	end
end

-------------------------------------------------------------------------------
-- Called after all of the initialization events.
--
function Me:OnEnable()
	Me.CreateDB()
	
	-- Setup user. UnitFullName always returns the realm name when you're 
	--  querying the "player". For other units, the name is ambiguated. We use
	--  these values a bunch so we cache them in our main table. `user_prefix`
	--  is what we prefix our messages with. It looks like this when 
	--    formatted: "1A Tammya-MoonGuard". `fullname` is the name part.
	--    `faction` is 'A' or 'H'.
	do
		local my_name, my_realm = UnitFullName( "player" )
		Me.realm       = my_realm
		Me.fullname    = my_name .. "-" .. my_realm
		local faction = UnitFactionGroup( "player" )
		Me.faction     = faction == "Alliance" and "A" or "H"
		Me.user_prefix = string.format( "1%s %s", Me.faction, Me.fullname )
		Me.user_prefix_short = string.format( "1C" )
	end
	
	---------------------------------------------------------------------------
	-- Event Routing
	---------------------------------------------------------------------------
	-- This is the main event for the text-comm channel.
	Me:RegisterEvent( "CHAT_MSG_COMMUNITIES_CHANNEL", 
	                                           Me.OnChatMsgCommunitiesChannel )
											   
	-- Battle.net related events. We use these to catch our custom whispers.
	Me:RegisterEvent( "CHAT_MSG_BN_WHISPER",        Me.OnChatMsgBnWhisper )
	Me:RegisterEvent( "CHAT_MSG_BN_WHISPER_INFORM", Me.OnChatMsgBnWhisper )
	
	-- These three events are the public emote events. As soon as we see them,
	--  we allow printing messages from the relay from the user, so it works
	--  as a sort of distance filter. We also save the orcish from them to
	--                                                 translate chat bubbles.
	Me:RegisterEvent( "CHAT_MSG_SAY",   Me.OnChatMsg )
	Me:RegisterEvent( "CHAT_MSG_EMOTE", Me.OnChatMsg )
	Me:RegisterEvent( "CHAT_MSG_YELL",  Me.OnChatMsg )
	
	-- This is used to see when the guild/community panel opens up, so we can
	--                                       add our hooks to the channel menu.
	Me:RegisterEvent( "ADDON_LOADED",  Me.OnAddonLoaded )
	
	-- These trigger when the player is kicked from the community, or if the
	--  relay channel is deleted, so we want to verify if it's still a valid
	--                                                            connection.
	Me:RegisterEvent( "CLUB_STREAM_REMOVED", Me.VerifyConnection )
	Me:RegisterEvent( "CLUB_REMOVED", Me.VerifyConnection )
	
	-- When the user logs out, we save the time. When they log in again, if
	--  they weren't gone too long, then we enable the relay automatically.
	--  Otherwise, the relay is always enabled manually. We don't want
	--  players to be caught offguard by the relay being active when they
	--                                               don't expect it to be.
	Me:RegisterEvent( "PLAYER_LOGOUT", function()
		Me.db.char.logout_time = time()
	end)
	
	-- Something pretty annoying with the chat channels is the stream marker.
	-- Clearly, the channels are not meant for addons streaming data through
	--  them, but we hook this so we can clear the "unread messages" marker
	--                                      ...every time we get a message...
	Me:RegisterEvent( "STREAM_VIEW_MARKER_UPDATED", 
	                                           Me.OnStreamViewMarkerUpdated )
	-- Not actually using this yet.
	Me:RegisterEvent( "CHAT_MSG_ADDON", Me.OnChatMsgAddon )
	---------------------------------------------------------------------------
	-- UI Hooks
	---------------------------------------------------------------------------
	Me:RawHook( ItemRefTooltip, "SetHyperlink", Me.SetHyperlinkHook, true )
	-- There's another one in SimulateChatMessage, HookPlayerLinks.
	
	---------------------------------------------------------------------------
	-- These are for blocking orcish messages from the chatbox. See their 
	--                                      headers for additional information.
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_SAY", Me.ChatFilter_Say )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_YELL", Me.ChatFilter_Say )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_EMOTE", Me.ChatFilter_Emote )
	
	-- For Bnet whispers, we catch when we have a Cross RP tag applied, and 
	--  then block the chat, re-submitting them as a normal character whisper.
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_BN_WHISPER", 
	                                              Me.ChatFilter_BNetWhisper )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_BN_WHISPER_INFORM", 
	                                              Me.ChatFilter_BNetWhisper )
	-- We depend on Gopher for some core
	--  functionality. The CHAT_NEW hook isn't too important; it's just so we
	--  can block the user from posting in a #RELAY# channel. The QUEUE hook 
	--  is mainly for catching our custom types, and then re-routing them. 
	--  We're doing it this way so we can still use Gopher's cutter, 
	--                       and we send one relay packet per split message.
	-- The POST queue is to catch outgoing public chat and then inserting
	--  translation messages that are relayed. Gopher's API has been
	--  designed to accommodate this specifically, in regard to sending these
	--                                                 messages in tandem.
	Gopher.Listen( "CHAT_NEW",       Me.GopherChatNew       )
	Gopher.Listen( "CHAT_QUEUE",     Me.GopherChatQueue     )
	Gopher.Listen( "CHAT_POSTQUEUE", Me.GopherChatPostQueue )
	Gopher.Listen( "SEND_DEATH", function()
		-- Reset this flag if chat fails for whatever reason.
		Me.protocol_user_short = nil
	end)
	
	-- For the /rp, /rpw command, the chatbox is actually going to try and
	--  send those chat types as if they're legitimate. We tell Gopher
	--  to cut them up at the 400-character mark (fat paras!), and then the
	--           hooks re-route them to be sent as tagged packets in the relay.
	for i = 1,9 do
		Gopher.SetChunkSizeOverride( "RP" .. i, 400 )
	end
	Gopher.SetChunkSizeOverride( "RPW", 400 )
	
	-- This is a feature in progress; commands to query players if they're
	--  who they say they are. There are some privacy issues with this, so
	--                                it's still on the backburner. (TODO)
	C_ChatInfo.RegisterAddonMessagePrefix( "RPL" )
	
	-- Our little obnoxious relay indicator. 
	-- See this function's header for more info.
	Me.CreateIndicator()
	
	Me.Map_Init()
	
	-- Hook the unit popup frame to add the whisper button back when
	--  right-clicking on a Horde target. Again, we just call it horde, 
	--                          when it just means the opposing faction.
	Me.SetupHordeWhisperButton()
	
	-- Hook the community frame so that we can disallow 
	--                      them from viewing the relay.
	Me.FuckUpCommunitiesFrame()
	
	-- Add other RP profile addon setup here. It's gonna be hell when we start
	--  adding MRP/XRP, since we need to make them all cross-compatible
	--             with each other.
	Me.MSP_Init()
	Me.TRP_Init()
	
	Me.FixupTRPChatNames()
	
	-- Initialize our DataBroker source and such.
	Me.SetupMinimapButton()
	
	-- Call this after everything to apply our saved options from the database.
	Me.ApplyOptions()
	
	-- This checks our settings to see if we want to autoconnect, as well as
	-- cleans up any relay stream markers.
	Me.CleanAndAutoconnect()
	
	Me.startup_time = GetTime()
end

-------------------------------------------------------------------------------
-- Scan all streams and advance the read markers. Also, check for a club to
--           connect to in the database and then make a connection if we can.
function Me.CleanAndAutoconnect()
	-- We save the amount of seconds since the PLAYER_LOGOUT event. If they
	--  log in within 15 minutes, then we enable the relay automatically along-
	--  side the autoconnect. Otherwise, we want that action to be manual, as 
	--  we want to avoid the player being caught offguard by the relay, or the
	--  relay server having excess load from people leaving the option on
	--  recklessly.
	local seconds_since_logout = time() - Me.db.char.logout_time
	local enable_relay = Me.db.char.relay_on and seconds_since_logout < 900
	
	if not enable_relay then
		-- If you don't reset this, then they can /reload UI and get a shorter
		--  time since logout, and it'll enable the relay.
		Me.db.char.relay_on = false
	end
	
	-- Some random timer periods here, just to give the game ample time to
	--  finish up some initialization. Maybe if addons did a lot more of this
	--                                     then we'd get faster loadup times?
	-- No this isn't for a faster loadup time. It's just so that we can catch
	--  when the streams are live. It minimizes the chances of this firing
	--  twice at startup, as we reschedule it if we hit it when the streams
	--  are loaded.
	Me.Timer_Start( "clean_relays", "push", 3.0, Me.CleanRelayMarkers )
	
	if Me.db.char.connected_club then
		local a = C_Club.GetClubInfo( Me.db.char.connected_club )
		if a then
			-- A lot of speculation going on here how the system starts up.
			--  If we can read the club info, then I assume that the streams
			--  are loaded. However, all we need is to read the stream's
			--  info to connect, and it should be visible here. For prudence
			--                                       we do a short delay.
			Me.Timer_Start( "auto_connect", "ignore", 2.0, function()
				if not Me.connected then
					Me.Connect( Me.db.char.connected_club, enable_relay )
				end
			end)
		end
	else
		Me.autoconnect_finished = true
	end
	
	Me:RegisterEvent( "CLUB_STREAMS_LOADED", function( event, club_id )
		-- Delay so we're not doing this scan for every club loaded. This scan
		--  goes through all clubs and advances the message markers for all 
		--  relay channels.
		Me.Timer_Start( "clean_relays", "push", 2.0, Me.CleanRelayMarkers )
		
		if not Me.connected then
			if club_id == Me.db.char.connected_club then
				-- During login, this usually fires. During reload, the 
				--    autoconnect is handled outside in the upper code.
				Me.Timer_Cancel( "auto_connect" )
				Me.Connect( Me.db.char.connected_club, enable_relay )
			end
		end
	end)
end

-------------------------------------------------------------------------------
-- Go through the list of streams and then mark any #RELAY# channels as read,
--                         so you don't have a blip in your communities panel.
function Me.CleanRelayMarkers()
	local servers = Me.GetServerList()
	for k,v in pairs( servers ) do
		C_Club.AdvanceStreamViewMarker( v.club, v.stream )
	end
end

-------------------------------------------------------------------------------
-- A simple function to turn a hex color string into normalized values for
--  vertex colors and things.
-- Returns r, g, b.
--
local function Hexc( hex )
	return 
		tonumber( hex:sub(1,2), 16 )/255,
		tonumber( hex:sub(3,4), 16 )/255,
		tonumber( hex:sub(5,6), 16 )/255
end

-------------------------------------------------------------------------------
-- Creating our `indicator`. It's the one at the top of the screen that tells 
--  you the relay is active. It's not the most prettiest thing, but it's meant 
--  to be /visible/, always, so you realize that your text is being printed 
--                                                           to the relay.
function Me.CreateIndicator()
	-- Here be dragons, huh? We should move the indicator stuff to its own
	--  file. 
	-- `indicator` is just an anchor frame.
	Me.indicator = CreateFrame( "Frame", nil, UIParent )
	local base = Me.indicator
	base:SetFrameStrata( "DIALOG" )
	base:SetSize( 16,16 )
	base:SetPoint( "TOP" )
	base:Hide()
	
	-- `indicator.text` is the actual label, and then we anchor the background
	--  to this fontstring, so that it resizes automatically with the string's
	--                                         width when we change the text.
	base.text = Me.indicator:CreateFontString( nil, "OVERLAY" )
	-- It might be considered primitive to be doing a lot of this in LUA. For
	--       quick things it's a lot quicker than writing up a proper XML file.
	base.text:SetFont( "Fonts\\FRIZQT__.ttf", 12 ) 
	base.text:SetPoint( "TOP", 0, -4 )
	base.text:SetText( "Hello World" )
	base.text:SetShadowOffset( 1, -1 )
	base.text:SetShadowColor( 0.0, 0.0, 0.0 )
	
	-- The `bg` is the solid color behind the text. It also has a skirt
	--  underneath, `bg2`, so it doesn't appear /too/ plain. I imagine some
	--  of this will be redesigned when people complain about it being ugly.
	base.bg = base:CreateTexture( nil, "ARTWORK" )
	base.bg:SetPoint( "TOPLEFT", base.text, "TOPLEFT", -12, 4 )
	base.bg:SetPoint( "BOTTOMRIGHT", base.text, "BOTTOMRIGHT", 12, -6 )
	local r, g, b = Hexc "22CC22"
	--base.bg:SetColorTexture( r*3, g*3, b*3, 0.25 )
	base.bg:SetColorTexture( 0.2,1,0.1,0.6 )
	--base.bg:SetBlendMode( "MOD" )
	--base.bg2 = base:CreateTexture( nil, "BACKGROUND" )
	--base.bg2:SetPoint( "TOPLEFT", base.bg, "BOTTOMLEFT", 0, 3 )
	--base.bg2:SetPoint( "BOTTOMRIGHT", base.bg, "BOTTOMRIGHT", 0, -3 )
	--base.bg2:SetColorTexture( r * 0.9, g * 0.9, b * 0.9 )
	-- Adjust the shadow color to better blend with the skirt. You can maybe
	--                              tell that I'm not the best UI designer.
	--base.text:SetShadowColor( r * 0.7, g * 0.7, b * 0.7, 1 )
	base.text:SetShadowColor( 0,0,0, 0.55 )
	-- The `thumb` is what you can actually click on. It lies on top of
	--                                           everything transparently.
	base.thumb = CreateFrame( "Button", "CrossRPIndicatorThumb", base )
	base.thumb:SetPoint( "TOPLEFT", base.bg, "TOPLEFT" )
	base.thumb:SetPoint( "BOTTOMRIGHT", base.bg, "BOTTOMRIGHT", 0, -3 )
	base.thumb:EnableMouse(true)
	base.thumb:RegisterForClicks( "LeftButtonUp", "RightButtonUp" )
	-- We aren't doing anything too special, so this can be linked directly
	--                to the minimap functions to make it work the same way.
	base.thumb:SetScript( "OnClick", Me.OnMinimapButtonClick )
	base.thumb:SetScript( "OnEnter", Me.OnMinimapButtonEnter )
	base.thumb:SetScript( "OnLeave", Me.OnMinimapButtonLeave )
end

-------------------------------------------------------------------------------
-- Does what it says on the tin. Well, not so much anymore. We have a much
--  safer way now, thanks to Solanya, who is a genius by the way, we just
--                                    disable the button in the dropdown.
function Me.FuckUpCommunitiesFrame()
	if not CommunitiesFrame then
		-- The communities addon hasn't loaded yet, and we wait for it via
		--  our ADDON_LOADED listener.
		return
	end
	
	local function LockRelay()
		-- One little disappointment here is that the functions to edit the
		--  stream info are protected, so we need to leave untainted access to
		--  that panel, if an admin wants to delete it or add the #mute tag.
		local club = CommunitiesFrame.selectedClubId
		local privs = C_Club.GetClubPrivileges( club ) or {}
		if privs.canSetStreamSubject then return end
		
		for i = 1,99 do
			local button = _G["DropDownList1Button"..i]
			if button and button:IsShown() then
				-- As of the latest patch, the text is prefixed by a blue
				--  color code in Bnet communities. And if it has unread
				--  messages, it's also postfixed with an indicator texture.
				if button:GetText():match( "#RELAY#" ) then
					button:SetEnabled(false)
					button:SetText( "#RELAY# " .. L.LOCKED_NOTE )
					break
				end
			else
				break
			end
		end
	end
	
	-- CommunitiesFrame.StreamDropDownMenu.initialize is the menu 
	--                                   initialization function.
	hooksecurefunc( CommunitiesFrame.StreamDropDownMenu, 
	                "initialize", LockRelay )
end

-------------------------------------------------------------------------------
-- Used to catch when the Communities/Guild addon loads.
--
function Me.OnAddonLoaded( event, name )
	if name == "Blizzard_Communities" then
		Me.FuckUpCommunitiesFrame()
	end
end

-------------------------------------------------------------------------------
-- Gathers up a list of relay servers. A community is considered a relay
--  server if they have any channel named #RELAY#.
-- Returns a list of table entries:
--  {
--    name   = Name of community.
--    club   = Club ID.
--    stream = Stream ID.
--  }
-- The list is sorted alphabetically by names.
--
function Me.GetServerList()
	local servers = {}
	for _,club in pairs( C_Club.GetSubscribedClubs() ) do
		if club.clubType == Enum.ClubType.BattleNet then
			for _, stream in pairs( C_Club.GetStreams( club.clubId )) do
				-- Maybe we should do a string match instead, or adjust the
				--  way we do it in the locking hook.
				if stream.name == "#RELAY#" then
					table.insert( servers, {
						name   = club.name;
						club   = club.clubId;
						stream = stream.streamId;
					})
				end
			end
		end
	end
	
	table.sort( servers, function(a,b)
		-- Not actually sure if lua string comparison is case-sensitive or not.
		return a.name:lower() < b.name:lower()
	end)
	return servers
end

-------------------------------------------------------------------------------
-- Returns the "full name" of a unit, that is Name-RealmName in proper
--  capitalization. Returns nil if the unit is too far away (and only a valid
--  unit due to being in a party). The reason for that limitation is because
--  we CAN'T query their server name if they're invisible, and therefore can't
--                                      really reliably do anything with them.
function Me.GetFullName( unit )
	local name, realm = UnitName( unit )
	if not name or not UnitIsVisible( unit ) then return end
	realm = realm or Me.realm
	realm = realm:gsub("%s*%-*", "")
	return name .. "-" .. realm, realm
end

-------------------------------------------------------------------------------
-- Helper function to get our current server's name.
-- If `short` is set, it tries to get the club's short name, and falls back to
--  the long name. If it can't figure out what name it is, then it returns
--  (Unknown).
function Me.GetServerName( short )
	if not Me.connected then return "(" .. L.NOT_CONNECTED .. ")" end
	
	local club_info = C_Club.GetClubInfo( Me.club )
	if not club_info then return L.UNKNOWN_SERVER end
	local name = ""
	
	if short then
		-- Currently on the PTR, shortName is often empty. I'm not sure
		--  whether or not it's actually a required field. It seems like
		--  it should be, with the ability to add the streams into the
		--  chat frames, which should be using those short names.
		name = club_info.shortName or ""
	end
	
	if name == "" then
		name = club_info.name or ""
	end
	
	-- Gotta be careful with Lua patterns. One little mistake and your match
	--  won't go through, likely causing some errors.
	name = name:match( "^%s*(%S+)%s*$" ) or ""
	if name == "" then
		return L.UNKNOWN_SERVER
	end
	
	return name
end

local BUTTON_ICONS = {
	ON   = "Interface\\Icons\\INV_Jewelcrafting_ArgusGemCut_Green_MiscIcons";
	HALF = "Interface\\Icons\\INV_Jewelcrafting_ArgusGemCut_Yellow_MiscIcons";
	OFF  = "Interface\\Icons\\INV_Jewelcrafting_ArgusGemCut_Red_MiscIcons";
}

-------------------------------------------------------------------------------
-- Called when we connect, disconnect, enable/disable the relay, or anything
--  else which otherwise needs to update our connection indicators and 
--                                               front-end stuff.
function Me.ConnectionChanged()
	-- While these sorts of functions aren't SUPER efficient, i.e. re-setting
	--  everything for when only a single element is potentially changed, it's
	--  a nice pattern to have for less performance intensive parts of things.
	-- Just keeps things simple.
	if Me.connected then
		Me.indicator.text:SetText( L( "INDICATOR_CONNECTED", Me.club_name ))
		if Me.db.global.indicator and Me.relay_on then
			Me.indicator:Show()
		else
			Me.indicator:Hide()
		end
	
		if Me.relay_on then
			--Me.ldb.iconR, Me.ldb.iconG, Me.ldb.iconB = Hexc "22CC22"
			Me.ldb.icon = BUTTON_ICONS.ON
			--Me.MinimapButtonSpinner:Show()
		else
			-- Yellow for relay-disabled.
			Me.ldb.icon = BUTTON_ICONS.HALF
			--Me.ldb.iconR, Me.ldb.iconG, Me.ldb.iconB = Hexc "CCCC11"
			--Me.MinimapButtonSpinner:Hide()
		end
	else
		Me.indicator:Hide()
		--Me.MinimapButtonSpinner:Hide()
		Me.ldb.icon = BUTTON_ICONS.OFF
		--Me.ldb.iconR, Me.ldb.iconG, Me.ldb.iconB = Hexc "CC2211"
	end
	
	-- We also disable using /rp, etc. in chat if they don't have the relay on.
	Me.UpdateChatTypeHashes()
end

-------------------------------------------------------------------------------
-- Enable or disable the chat relay. This is meant to be used by the user 
--                      through the UI, with message printing and everything.
function Me.EnableRelay( enabled )
	-- Good APIs should always have little checks like this so you don't have
	--                                        to do it in the outside code.
	if not Me.connected then return end
	if (not Me.relay_on) == (not enabled) then return end
	
	Me.relay_on = enabled
	-- We also save this to the database, so we can automatically enable the 
	--  relay so long as our other constraints for this are met (like how we
	--          only do that if they've logged for less than three minutes).
	Me.db.char.relay_on = enabled
	Me.ConnectionChanged()
	
	if Me.relay_on then
		Me.Print( L.RELAY_NOTICE )
		Me.protocol_user_short = nil
		
		-- This is potentially dangerous, since the user can easily spam-click
		--  the relay button to call this repeatedly. Something to keep an eye 
		--                        on for future features.
		Me.SendPacket( "HENLO" )
		Me.TRP_OnConnected()
	else
		-- Nice and verbose.
		Me.Print( L.RELAY_DISABLED )
		Me.showed_relay_off_warning = nil
	end
end

-------------------------------------------------------------------------------
-- Establish server connection.
-- club_id: ID of club with a relay channel.
-- enable_relay: Enable relay as well as connect.
function Me.Connect( club_id, enable_relay )

	-- Reset everything.
	Me.Disconnect()
	Me.Timer_Cancel( "auto_connect" )
	Me.name_locks  = {}
	Me.autoconnect_finished = true

	-- The club must be a valid Battle.net community.
	local club_info = C_Club.GetClubInfo( club_id )
	if not club_info then return end
	if club_info.clubType ~= Enum.ClubType.BattleNet then return end
	
	for _, stream in pairs( C_Club.GetStreams( club_id )) do
		if stream.name == "#RELAY#" 
		                     and not stream.leadersAndModeratorsOnly then
			-- A funny thing to note is that unlike traditional applications
			--  which connect to servers, this is instant. There's no initial
			--  handshake or anything. Once you flip the switch on, you're
			--  then processing incoming data.
			Me.connected  = true
			Me.club       = club_id
			Me.stream     = stream.streamId
			-- We need to save the club name for the disconnect message.
			--  Otherwise, we won't know what it is if we get kicked from the
			--  server.
			Me.club_name  = club_info.name
			-- This is for auto-connecting on the next login or reload.
			Me.db.char.connected_club = club_id
			
			Me.showed_relay_off_warning = nil
			
			-- This is a bit of an iffy part. Focusing a stream is for when
			--  the communities panel navigates to one of the streams, and
			--  the API documentation states that you can only have one
			--  focused at a time. But, as far as I know, this is the only
			--  way to ensure that we will be able to send and receive messages
			--  from that stream.
			C_Club.FocusStream( Me.club, Me.stream )
			
			Me.PrintL( "CONNECTED_MESSAGE", club_info.name )
			
			Me.ConnectionChanged()
			
			-- `enable_relay` is set either when the user presses a connect
			--  button manually, or when they log in within the grace
			--  period. Otherwise, we don't want to do this automatically to
			--                              protect privacy and server load.
			Me.EnableRelay( enable_relay )
			
			Me.Map_ResetPlayers()
		end
	end
end

-------------------------------------------------------------------------------
-- Disconnect from the current server. `silent` will suppress the chat message
--                                  for system things.
function Me.Disconnect( silent )
	if Me.connected then
		-- We don't want to prompt people to rejoin a club they just left.
		Me.club_connect_prompted[Me.club] = true
		
		-- We do, however, want to show them alternatives again...
		Me.club_connect_prompt_shown      = false
		
		Me.connected              = false
		Me.relay_on               = false
		Me.db.char.connected_club = nil
		Me.db.char.relay_on       = nil
		
		Me.Map_ResetPlayers()
		
		-- We call this here to prevent any data queued from being sent if we
		--  start another connection soon.
		Me.KillProtocol()
		if not silent then
			Me.PrintL( "DISCONNECTED_FROM_SERVER", Me.club_name )
		end
		Me.ConnectionChanged()
	end
end

-------------------------------------------------------------------------------
-- Called from certain events to verify that we still have a valid connection.
--
function Me.VerifyConnection()
	if not Me.connected then return end
	local club_info = C_Club.GetClubInfo( Me.club )
	
	if not club_info or club_info.clubType ~= Enum.ClubType.BattleNet then
		-- Either the club was deleted, the player was removed from it, or the
		--  club is otherwise not available.
		Me.Disconnect()
		return
	end
	
	local stream = C_Club.GetStreamInfo( Me.club, Me.stream )
	if not stream or stream.leadersAndModeratorsOnly then
		-- Either our #RELAY# channel was deleted, or we otherwise can't access
		--  it.
		Me.Disconnect()
		return
	end
end

-------------------------------------------------------------------------------
-- Work in progress!
function Me.OnChatMsgAddon( prefix, msg, dist, sender )
	if prefix == "RPL" then
	
		-- TODO: This needs more work.
		-- The sender needs to be checked if they're in the same community.
		-- We don't want to verify battle tag for people outside randomly.
		-- It's a privacy issue.
	--[[
		local name = msg:match( "^CHECK (.+)" )
		if name then
			if not Me.connected then
				SendAddonMessage( "RPL", "CHECKR OFFLINE", "WHISPER", sender )
			else
				if name:lower() == Me.fullname:lower() then
					SendAddonMessage( "RPL", "CHECKR YES", "WHISPER", sender )
				else
					SendAddonMessage( "RPL", "CHECKR NO", "WHISPER", sender )
				end
			end
			return
		end
		
		local reply = msg:match( "^CHECKR (.+)" )
		if reply then
			if reply == "YES" then
				
		end]]
	end
end

-------------------------------------------------------------------------------
StaticPopupDialogs["CROSSRP_RELAY_OFF"] = {
	text         = L.RELAY_OFF_WARNING;
	button1      = YES;
	button2      = NO;
	hideOnEscape = true;
	whileDead    = true;
	timeout      = 0;
	OnAccept = function( self )
		Me.EnableRelay( true )
	end;
}

-------------------------------------------------------------------------------
-- This is called to process our chat buffers when either side receives a
--  message, side 1 being the game-event side (CHAT_MSG_XYZ), side 2 being
--  the relay channel with translations.
function Me.FlushChat( username )
	local chat_data = Me.GetChatData( username )
	
	-- We'll be removing table entries, so we have to suffer through a while
	--  loop.
	local index = 1
	while index <= #chat_data.translations do
		
		local translation = chat_data.translations[index]
		
		if GetTime() - translation.time > CHAT_TRANSLATION_TIMEOUT then
			-- This message is too old to be worth anything; discard it.
			table.remove( chat_data.translations, index )
		else
			-- We can receive translations first or chat messages first.
			-- If we  receive  the  translation  first,  it's  buffered  for  X
			--  seconds,  until  we  get  a  chat event,  in which  they're all
			--  handled or otherwise pass our distance filtering.  If we don't
			--  get the chat event, then it times out and is discarded. If we
			--  get the chat event first, then translations are printed
			--  as they pop up for X seconds. Ideally this period of seconds
			--  could be much shorter, but someone may have a latency spike,
			--                 and we don't want them to miss any messages.
			local time_from_event = 
			         math.abs(translation.time - chat_data.last_event_time)
			if time_from_event < CHAT_TRANSLATION_TIMEOUT then
				-- This message is within the window; show it!
				table.remove( chat_data.translations, index )
				
				-- The bubbles subsystem automatically handles saving messages
				--  or applying them directly.
				Me.Bubbles_Translate( username, translation.text )
				
				Me.SimulateChatMessage( translation.type, translation.text, 
				                        username )
				
				if not Me.relay_on and not Me.showed_relay_off_warning then
							
					-- The user might want to do something about this already.
					Me.showed_relay_off_warning = true
					--Me.Print( L.RELAY_OFF_WARNING )
					StaticPopup_Show( "CROSSRP_RELAY_OFF" )
				end
			else
				index = index + 1
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Get or create chat data for a user.
--
function Me.GetChatData( username )
	local data = Me.chat_data[username]
	if not data then
		data = {
			orcish          = nil; -- The last orcish phrase that we've heard
			                       --  from them.
			last_event_time = 0;   -- The last time we received a chat event
			                       --  from them.
			translations    = {};  -- A list of translations that are pending
			                       --  which we get from the relay channel.
		}
		Me.chat_data[username] = data
	end
	return data
end

-------------------------------------------------------------------------------
-- Handler for when we receive a CHAT_MSG_SAY/EMOTE/YELL event, a public chat
--  event.
function Me.OnChatMsg( event, text, sender, language, 
                                                _,_,_,_,_,_,_, lineID, guid )
	if not Me.connected then return end
	
	-- I'm fairly certain that this should never trigger, but a little bit
	--  of prudence goes a long way. We need sender to be a fullname for most
	--  of our functions.
	if not sender:find( "-" ) then
		sender = sender .. "-" .. GetNormalizedRealmName()
	end
	
	-- We don't pass around GUIDs, we simply record them in a global table like
	--  this as we see them, and then reference them if we can. If we don't
	--  have a GUID for someone, it's not a huge deal. The Blizzard chat frames
	--  don't crash if you don't give them a GUID with a message.
	if guid then
		Me.player_guids[sender] = guid
	end
	
	event = event:sub( 10 )
	-- If you didn't notice by now, I like to keep the indentation to a
	--  minimum. Return or break when you can. Sometimes I suffer from a lack
	--                               of a `continue` keyword in this regard.
	if event ~= "SAY" and event ~= "EMOTE" and event ~= "YELL" then return end
	
	-- We only want to intercept foreign messages.
	-- CHAT_EMOTE_UNKNOWN is "does some strange gestures."
	-- CHAT_SAY_UNKNOWN is "says something unintelligible."
	-- CHAT_SAY_UNKNOWN is an EMOTE that spawns from /say when you type in
	--  something like "reeeeeeeeeeeeeee".
	if ((event == "SAY" or event == "YELL") and language ~= HordeLanguage())
	   or (event == "EMOTE" and text ~= CHAT_EMOTE_UNKNOWN 
	                                         and text ~= CHAT_SAY_UNKNOWN) then
		return
	end
	
	local chat_data = Me.GetChatData( sender )
	chat_data.last_event_time = GetTime()
	
	if event == "SAY" and text ~= "" then
		-- We don't actually use this value currently, but it was a good idea
		--  at the time.
		chat_data.last_orcish = text
		
		-- The chat bubble isn't actually available until next frame, but our
		--  Bubbles system handles that magically.
		Me.Bubbles_Capture( sender, text )
	end
	
	-- Process the queue.
	Me.FlushChat( sender )
end

-------------------------------------------------------------------------------
-- Prints a chat message to the chat boxes, as well as forwards it to addons
--  like Listener and WIM (via LibChatHandler).
-- event_type: SAY, EMOTE... Can also be our custom types "RP", "RP2" etc.
-- msg:        Message text.
-- username:  Sender's fullname.
-- language:  Language being spoken. Leave nil to use default language.
-- lineid:    Message line ID. Leave nil to generate one.
-- guid:      Sender's GUID. Leave nil to try to pull it from our data.
--
function Me.SimulateChatMessage( event_type, msg, username, 
                                                      language, lineid, guid )
	if username == Me.fullname then
		guid = UnitGUID( "player" )
	else
		guid = guid or Me.player_guids[username]
	end
	
	if not lineid then
		-- Not actually sure if this is safe, using negative line IDs. It's
		--  something that we do for TRP compatibility. Other way we can fix
		--  this is if we patch TRP to process their chat messages differently.
		-- MIGHT WANT TO LOOK AT THAT BEFORE THE 8.0 PATCH, SO EVERYONE
		--  WILL HAVE IT.
		lineid = Me.fake_lineid
		Me.fake_lineid = Me.fake_lineid - 1
	end
	
	language = langauge or (GetDefaultLanguage())
	local event_check = event_type
	
	-- Catch if we're simulating one of our super special RP types.
	-- For the normal ones we use the chatbox filter RAID, and
	--                                for /rpw, RAID_WARNING.
	local is_rp_type = event_type:match( "^RP[1-9W]" )
	if is_rp_type then
		if event_type == "RPW" then
			event_check = "RAID_WARNING"
		else
			event_check = "RAID" 
		end
	end
	
	-- Check our filters too (set in the minimap menu). If any of them are
	--  unset, then we skip passing it to the chatbox, but we can still pass
	--                       it to Listener, which has its own chat filters.
	local show_in_chatboxes = true
	if is_rp_type and not Me.db.global["show_"..event_type:lower()] then
		show_in_chatboxes = false
	end
	
	if show_in_chatboxes then
		-- We save this hook until we're about to abuse the chatboxes. That
		--  way, if the person isn't actively using Cross RP (which is most
		--  of the time), link construction isn't going to be touched.
		Me.HookPlayerLinks()
		
		for i = 1, NUM_CHAT_WINDOWS do
			local frame = _G["ChatFrame" .. i]
			-- I feel like we /might/ be missing another check here. TODO
			--  do some more investigating on how the chat boxes filter
			--  events.
			if frame:IsEventRegistered( "CHAT_MSG_" .. event_check ) then
				ChatFrame_MessageEventHandler( frame, 
				       "CHAT_MSG_" .. event_type, msg, username, language, "", 
					                    "", "", 0, 0, "", 0, lineid, guid, 0 )
			end
		end
	end
	
	-- Listener support. Listener handles the RP messages just fine, even if
	--  an older version is being used. (I think...)
	if ListenerAddon then
		ListenerAddon:OnChatMsg( "CHAT_MSG_" .. event_type, msg, username, 
		                 language, "", "", "", 0, 0, "", 0, lineid, guid, 0 )
	end
	
	if (not is_rp_type) then -- Only pass valid to here. (Or maybe not?)
		if LibChatHander_EventHandler then
			local lib = LibStub:GetLibrary("LibChatHandler-1.0")
			if lib.GetDelegatedEventsTable()[event_type] then
				-- GetDelegatedEventsTable is actually a hidden function, but
				--  it's the only way that we can tell if the library is
				--  setup to handle the event we're going to give it. It's a
				--  bit nicer when a lot more of a library is exposed so
				--  people like me can hack as they please without requiring
				local event_script =               -- the lib to be updated.
				              LibChatHander_EventHandler:GetScript( "OnEvent" )
				if event_script then
					event_script( LibChatHander_EventHandler, 
					       "CHAT_MSG_" .. event_type, msg, username, language, 
						             "", "", "", 0, 0, "", 0, lineid, guid, 0 )
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.ParseLocationArgs( arg1, arg2, arg3 )
	local continent, x, y = tonumber( arg1 ), Me.UnpackCoord( arg2 ), 
	                                                     Me.UnpackCoord( arg3 )
	if not continent or not x or not y then
		-- It's one thing to account for human input, another thing entirely
		--  to account for every human's input. Networking security is a
		--  daunting thing.
		return false
	end
	
	return continent, x, y
end

-------------------------------------------------------------------------------
-- Returns the distance squared between two points.
--
local function Distance2( x, y, x2, y2 )
	x = x - x2
	y = y - y2
	return x*x + y*y
end

-------------------------------------------------------------------------------
-- Returns true if the point on the map specified is within `range` units
--  from the player's position.
--
local function PointWithinRange( instancemapid, x, y, range )
	if (not instancemapid) or (not x) or (not y) then return end
	local my_mapid = select( 8, GetInstanceInfo() )
	if my_mapid ~= instancemapid then return end
	local my_y, my_x = UnitPosition( "player" )
	if not my_y then return end
	local distance2 = Distance2( my_x, my_y, x, y )
	return distance2 < range*range
end

-------------------------------------------------------------------------------
-- Called when we receive a public chat packet, a "translation". We're going 
--  to receive these from both factions, from whoever is connected to the 
--                    relay. We're only interested in the ones from Horde.
function Me.ProcessPacketPublicChat( user, command, msg, args )
	if user.self or not msg then return end
	-- Args for this packet are: LEN, COMMAND, CONTINENT, X, Y
	-- X, Y are packed using our special function.
	local continent, chat_x, chat_y = 
	                          Me.ParseLocationArgs( args[3], args[4], args[5] )
	if not continent then
		-- Invalid message.
		return
	end
	
	if not user.connected then
		-- We aren't connected to their server, and we don't want to display
		--  their message, but we still want to see if we want to connect to 
		--  them.
		Me.ShowConnectPromptIfNearby( user, continent, chat_x, chat_y )
		
		return
	end
	
	Me.Map_SetPlayer( user.name, continent, chat_x, chat_y, user.faction )
	
	-- After setting the blip, we only care if this message is from Horde.
	if not user.horde then return end
	local type = command -- Special handling here if needed

	-- Range check, SAY/EMOTE is 25 units. YELL is 200 units.
	local range = CHAT_HEAR_RANGE
	if type == "YELL" then
		range = CHAT_HEAR_RANGE_YELL
	end
	
	-- This is the hard filter. We also have another filter which is the chat
	--  events. We don't print anything even if it's within range if we don't
	--  see the chat event for them. That way we're accounting for vertical
	--  height too.
	if not PointWithinRange( continent, chat_x, chat_y, range ) then
		return
	end

	-- Add this entry to the translations and then process the chat data.
	local chat_data = Me.GetChatData( user.name )
	table.insert( chat_data.translations, {
		time = GetTime();
		type = type;
		text = msg;
	})
	Me.FlushChat( user.name )
end

Me.ProcessPacket.SAY   = Me.ProcessPacketPublicChat
Me.ProcessPacket.EMOTE = Me.ProcessPacketPublicChat
Me.ProcessPacket.YELL  = Me.ProcessPacketPublicChat

-------------------------------------------------------------------------------
-- Returns the current "role" for the player in their connected club. Defaults
--  to 4/"Member".
function Me.GetRole( user )
	if not Me.connected then return 4 end
	local members = C_Club.GetClubMembers( Me.club )
	if not members then return 4 end
	local role = 4
	
	-- Doesn't actually seem like you can query the player's roll without going
	--  through the entire list.
	for k, index in pairs( members ) do
		local info = C_Club.GetMemberInfo( Me.club, index )
		if user then
			if info.bnetAccountId == user.bnet then
				role = info.role
				break
			end
		else
			if info.isSelf then
				role = info.role
				break
			end
		end
	end
	return role
end

-------------------------------------------------------------------------------
StaticPopupDialogs["CROSSRP_CONNECT"] = {
	text         = "Connect!";
	button1      = YES;
	button2      = NO;
	hideOnEscape = true;
	whileDead    = true;
	timeout      = 0;
	OnAccept = function( self )
		Me.Connect( StaticPopupDialogs.CROSSRP_CONNECT.server, true )
	end;
}

-------------------------------------------------------------------------------
function Me.ShowConnectPromptIfNearby( user, map, x, y )
	if not map then return end
	if PointWithinRange( map, x, y, 500 ) then
		if Me.connected and Me.club == user.club then return end
		
		-- The user might want to do something about this already.
		if not Me.autoconnect_finished 
		                           and GetTime() - Me.startup_time < 10.0 then
			-- Give autoconnect some time to work. This will trigger often when
			--  /reloading in a crowded area and messages are queued up when
			--  the UI is loading.
			return 
		end
		
		if not Me.club_connect_prompted[ user.club ] 
		                              and not Me.club_connect_prompt_shown then
			Me.club_connect_prompted[ user.club ] = true
			Me.club_connect_prompt_shown = true
			local name = C_Club.GetClubInfo( user.club ).name
			StaticPopupDialogs.CROSSRP_CONNECT.text 
			                                  = L( "CONNECT_POPUP", name )
			StaticPopupDialogs.CROSSRP_CONNECT.server = user.club
			StaticPopup_Show( "CROSSRP_CONNECT" )
		end
	end
end

-------------------------------------------------------------------------------
-- Packet handler for custom RP chats: RP1-9 and RPW.
--
local function ProcessRPxPacket( user, command, msg, args )
	if not msg then return end
	
	local continent, chat_x, chat_y = 
	                          Me.ParseLocationArgs( args[3], args[4], args[5] )
	
	if not user.connected then
		-- We aren't connected to them, and we don't want to display their
		--  message, but we still want to see if we want to connect to them.
		Me.ShowConnectPromptIfNearby( user, continent, chat_x, chat_y )
		return
	end
	
	if command == "RP1" then
		-- For RP1, we check for the #mute flag in the relay channel. If that's
		--  set then the user needs to be a moderator or higher to post.
		local role = Me.GetRole( user )
		local streaminfo = C_Club.GetStreamInfo( Me.club, Me.stream )
		if streaminfo then
			-- 4 is basic member.
			if role >= 4 and streaminfo.subject:lower():find( "#mute" ) then
				-- RP channel is muted.
				return
			end
		else
			-- If we don't get stream info for whatever reason, 
			--  we let it slide.
		end
	elseif command == "RPW" then
		
		-- Only leaders can /rpw.
		local role = Me.GetRole( user )
		if role > 2 then return end 
		
	end
	
	Me.Map_SetPlayer( user.name, continent, chat_x, chat_y, user.faction )
	
	Me.SimulateChatMessage( command, msg, user.name )
	
	if command == "RPW" then
		-- Simulate a raid-warning too; taken from Blizzard's chat frame code.
		msg = ChatFrame_ReplaceIconAndGroupExpressions( msg );
		RaidNotice_AddMessage( RaidWarningFrame, msg, ChatTypeInfo["RPW"] );
		PlaySound( SOUNDKIT.RAID_WARNING );
	end
end

for i = 1,9 do
	Me.ProcessPacket["RP"..i] = ProcessRPxPacket
end
Me.ProcessPacket["RPW"] = ProcessRPxPacket

-------------------------------------------------------------------------------
-- HENLO is the packet that people send as soon as they enable their relay.
--
function Me.ProcessPacket.HENLO( user, command, msg )
	if user.self then return end
	if not user.connected then return end
	
	-- We use this as a way to sync some data between players. HENLO is like
	--  a request for everyone to broadcast their state. For now, we just 
	--  have our TRP vernum as the only state needed.
	
	-- And we should try to keep it that way.
	if (user.xrealm or user.horde) and not Me.GetBnetInfo( user.name ) then
		-- We don't have normal communication to this player.
		Me.TRP_SendVernumDelayed()
	end
	
	-- The next time we broadcast a message, they'll get our username.
	Me.protocol_user_short = nil
	
	-- Todo: this needs to be adjusted if you add more RP addons.
	--if user.xrealm or user.horde and TRP3_API then
	--	Me.TRP_SendVernumDelayed()
	--else
	--	-- If we don't have anything else to send back when we see HENLO, then
	--	--  we just send a simple packet back. This is to let them know that
	--	--  we're using Cross RP.
	--	-- (On second thought, we need to keep broadcast replies to an absolute
	--	--  minimum, as EVERYONE is going to be sending these.)
	--	--Me.Timer_Start( "send_hi", "push", math.random( 4, 9 ), Me.SendHi )
	--end
end

-------------------------------------------------------------------------------
--function Me.SendHi()
--	Me.SendPacket( "HI" )
--end

-------------------------------------------------------------------------------
-- Checks if a username belongs to a player that you can addon-whisper to.
--  `party_is_local` will make xrealm players return true if they're in your
--  party. Returns `nil` when we don't have enough information on the player
--                                      to properly determine the result.
function Me.IsLocal( username, party_is_local )
	
	if Me.GetBnetInfo( username ) then return true end -- Bnet friend.
	
	local user = Me.crossrp_users[username]
	if not user then return end
	
	if user.horde then
		return false
	end
	
	if user.xrealm then
		if party_is_local and UnitExists(username) then
			-- Cross-realm but in a party.
			return true
		end
		return false
	end
	
	return true
end

-------------------------------------------------------------------------------
-- Fetches Bnet information if `name` is online and a btag friend.
--
-- Returns account id, game account id, faction, friend index.
--
function Me.GetBnetInfo( name )
	name = name:lower()
	for friend = 1, select( 2, BNGetNumFriends() ) do
		local accountID, _,_,_,_,_,_, is_online = BNGetFriendInfo( friend )
		if is_online then
			for account_index = 1, BNGetNumFriendGameAccounts( friend ) do
				local _, char_name, client, realm,_, faction, 
				        _,_,_,_,_,_,_,_,_, game_account_id 
				          = BNGetFriendGameAccountInfo( friend, account_index )
				
				if client == BNET_CLIENT_WOW then
					char_name = char_name .. "-" .. realm:gsub( "%s*%-*", "" )
					if char_name:lower() == name then
						return accountID, game_account_id, faction, friend
					end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Scan through our friends list and then see if a bnetAccountId is logged into
--  a character name.
local function BNetFriendOwnsName( bnet_id, name )
	-- We can't use the direct lookup functions because they only support one
	--  game account. The user might be on multiple WoW accounts, and we want
	--  to check all of them for the character name.
	local found = Me.GetBnetInfo( name )
	return found == bnet_id
end

-------------------------------------------------------------------------------
-- Handler for Bnet whispers.
function Me.OnChatMsgBnWhisper( event, text, _,_,_,_,_,_,_,_,_,_,_, bnet_id )
	-- We encode special to-character whispers like this:
	--  [W:Ourname-RealmName] message...
	--
	-- If we see that pattern, then we translate it to a character whisper.
	--  Perks of not using game data are that the message is logged in the
	--  chat log file, and that people without Cross RP can see it too.
	local sender, text = text:match( "^%[([^%-]+%-[^%]]+)%] (.+)" )
	if sender then
		if event == "CHAT_MSG_BN_WHISPER" then
			local prefix = ""
			if not BNetFriendOwnsName( bnet_id, sender ) then
				-- The function above returns `false` if they're offline.
				-- Otherwise it returns true or nil, telling us if its their
				--  character or not. I don't really trust the system to always
				--  work, so we aren't going to raise any red flags until a
				--  later version. Just say it's unverified.
				prefix = L.WHISPER_UNVERIFIED .. " "
			end
			Me.SimulateChatMessage( "WHISPER", prefix .. text, sender )
		elseif event == "CHAT_MSG_BN_WHISPER_INFORM" then
			if Me.bnet_whisper_names[bnet_id] then
				Me.SimulateChatMessage( "WHISPER_INFORM", text, 
				                               Me.bnet_whisper_names[bnet_id] )
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Our chat filter to hide our special Bnet whisper messages.
--
function Me.ChatFilter_BNetWhisper( self, event, text, 
                                              _,_,_,_,_,_,_,_,_,_,_, bnet_id )
	local sender, text = text:match( "^%[([^%-]+%-[^%]]+)%] (.+)" )
	if sender then
		if event == "CHAT_MSG_BN_WHISPER_INFORM" 
		                            and not Me.bnet_whisper_names[bnet_id] then
			-- We didn't send this or we lost track, so just make it show up
			--  normally...
			-- The former case might show up when we're running two WoW
			--  accounts on the same Bnet account; both will probably receive
			--  the whisper inform.
			return
		end
		
		return true
	end
end

-------------------------------------------------------------------------------
-- A simple event handler to mark any #RELAY# channel as read. i.e. hide the
--  "new messages" blip. Normal users can't even open the channel in the 
--  communities panel.
function Me.OnStreamViewMarkerUpdated( event, club, stream, last_read_time )
	if last_read_time then
		local stream_info = C_Club.GetStreamInfo( club, stream )
		if stream_info.name == "#RELAY#" then
			C_Club.AdvanceStreamViewMarker( club, stream )
		end
	end
end

-------------------------------------------------------------------------------
-- Called from our Gopher CHAT_QUEUE hook, which means that the message
--                                 passed into here is already a cut slice.
function Me.HandleOutgoingWhisper( msg, type, arg3, target )
	if msg == "" then return end
	
	-- Fixup target for a full name.
	if not target:find('-') then
		target = target .. "-" .. Me.realm
	end
	
	local account_id, game_account_id, faction, friend 
	                                                 = Me.GetBnetInfo( target )
	if account_id and faction ~= UnitFactionGroup("player") then
		
		-- This is a cross-faction whisper.
		-- TODO: If the recipient is on 2 wow accounts, both 
		--  will see this message and not know who it is to!
		-- TODO: This probably needs a SUPPRESS.
		BNSendWhisper( account_id, "[" .. Me.fullname .. "] " .. msg )
		-- Save their name so we know what the INFORM message
		--  is for.
		Me.bnet_whisper_names[account_id] = target
		return false
	end
end

-------------------------------------------------------------------------------
-- Gopher's START hook.
function Me.GopherChatNew( event, msg, type, arg3, target )
	if Me.sending_to_relay then return end
	
	-- This is just to cancel the user from sending to the relay. If they 
	--  wanna do that, then they gotta dig through this code.
	-- There's two ways to send to the relay. One is through 
	--  C_Club.SendMessage, and the other is through SendChatMessage when the
	--  club stream is added to the chatbox. What we do is check if the channel
	--                            target is a stream, and then change the args.
	if type == "CHANNEL" then
		local _, channel_name = GetChannelName( target )
		if channel_name then
			local club_id, stream_id = 
			                      channel_name:match( "Community:(%d+):(%d+)" )
			if club_id then
				type   = "CLUB"
				arg3   = club_id
				target = stream_id
			end
		end
	end
	
	if type == "CLUB" then
		local stream_info = C_Club.GetStreamInfo( arg3, target )
		if not stream_info then return end
		local name = stream_info.name
		if name and name == "#RELAY#" then
			-- This is a relay channel.
			Me.Print( L.CANNOT_SEND_TO_CHANNEL )
			return false
		end
	end
end

-------------------------------------------------------------------------------
-- Gopher QUEUE hook. This triggers after the message its handling is
--  cut up, but before it sends it. We can still modify things in here or
--  cancel the message.
function Me.GopherChatQueue( event, msg, type, arg3, target )
	
	-- Handle whisper. This is one of the only cases where we do something
	--  without being connected - and without the relay active. For
	--  everything else, the relay must be active for us to send any
	--  outgoing data automatically. We're strict like that to keep the spam 
	--                                   in the relay channel to a minimum.  
	if type == "WHISPER" then
		return Me.HandleOutgoingWhisper( msg, type, arg3, target )
	end
	
	-- TODO: I don't think we're actually using in_relay. Investigate that.
	if Me.in_relay then return end
	if not Me.connected then return end
	
	local rptype, rpindex = type:match( "^(RP)(.)" )
	
	-- Basically we want to intercept when the user is trying to send our
	--  [invalid] chat types RPW, RP1, RP2, etc... and then we catch them
	--               in here to reroute them to our own system as packets.
	if rptype then
		local y, x = UnitPosition( "player" )
		if not y then 
			y = 0
			x = 0
		end
		local mapid, px, py = select( 8, GetInstanceInfo() ),
									         Me.PackCoord(x), Me.PackCoord(y)
		if rpindex == "1" then -- "RP"
			-- For RP, the user needs to be a moderator if the relay channel
			--  is "muted". You can set the mute by typing #mute in the 
			--  channel description.
			if Me.GetRole() == 4 and Me.IsMuted() then
				Me.Print( L.RP_CHANNEL_IS_MUTED )
				return false
			end
			Me.SendPacketInstant( "RP1", msg, mapid, px, py )
		elseif rpindex:match "[2-9]" then
			-- Channels 2-9 have no such restrictions and you can always send
			--  chat to them.
			Me.SendPacketInstant( "RP" .. rpindex, msg, mapid, px, py )
		elseif rpindex == "W" then
			-- Only leaders can use RP Warning. These are the few things that
			--  we can reliably pull from the community settings.
			if Me.GetRole() > 2 then
				Me.Print( L.CANT_POST_RPW )
				return false
			end
			Me.SendPacketInstant( "RPW", msg, mapid, px, py  )
		end
		return false -- Block the original message.
	elseif type == "SAY" or type == "YELL" and ( arg3 == 1 or arg3 == 7 ) then
		-- This is a hint for Gopher, telling it that we want to send
		--  the next couple of messages together. When we're about to send
		--  a SAY message, we insert a BREAK before it, so that it stocks
		--  bandwidth, and then we queue the SAY and the relay message right
		--  after (the relay message is done in the POSTQUEUE hook).
		if Me.InWorld() and not IsStealthed() then
			Gopher.QueueBreak()
		end
	end
end

-------------------------------------------------------------------------------
-- Let's have a little bit of fun, hm? Here's something like a base64
--  implementation, for packing map coordinates.
-- 
-- Max number range is +-2^32 / 2 / 5
--
local PACKCOORD_DIGITS 
--          0          11                         38                       63
         = "0123456789+@ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
--          48-57     |64-90                      97-122
--                 43-'
-------------------------------------------------------------------------------
-- Returns a fixed point packed number.
--
function Me.PackCoord( number )
	-- We store the number as units of fifths, and then we add one more bit 
	--  which is the sign. In other words, odd numbers (packed) are negative
	--  when unpacked, and we discard this LSB.
	number = math.floor( number * 5 )
	if number < 0 then
		number = (-number * 2) + 1
	else
		number = number * 2
	end
	local result = ""
	while number > 0 do
		-- Iterate through 6-bit chunks, select a digit from our string up
		--  there, and then append it to the result.
		local a = bit.band( number, 63 ) + 1
		result  = PACKCOORD_DIGITS:sub(a,a) .. result
		number  = bit.rshift( number, 6 )
	end
	if result == "" then result = "0" end
	return result
end

------------------------------------------------------------------------
-- Reverts a fixed point packed number.
--
function Me.UnpackCoord( packed )
	if not packed then return nil end
	
	local result = 0
	for i = 0, #packed-1 do
		-- Go through the string backward, and then convert the digits
		--  back into 6-bit numbers, shifting them accordingly and adding
		--  them to the results.
		-- We can have some fun sometime benchmarking a few different ways
		--  how to do this:
		-- (1) Using string:find with our string above to convert it easily.
		--     (Likely slow)
		-- (2) This way, below.
		-- (3) Add some code above to generate a lookup map.
		--
		local digit = packed:byte( #packed - i )
		if digit >= 48 and digit <= 57 then
			digit = digit - 48
		elseif digit == 43 then
			digit = 10
		elseif digit >= 64 and digit <= 90 then
			digit = digit - 64 + 11
		elseif digit >= 97 and digit <= 122 then
			digit = digit - 97 + 38
		else
			-- Bad input.
			return nil
		end
		result = result + bit.lshift( digit, i*6 )
	end
	
	-- The unpacked number is in units of fifths (fixed point), with an
	--  additional sign-bit appended.
	if bit.band( result, 1 ) == 1 then
		result = -bit.rshift( result, 1 )
	else
		result = bit.rshift( result, 1 )
	end
	return result / 5
end

-------------------------------------------------------------------------------
-- Gopher Post Queue hook. This is after the message is put out on the
--  line, so we can't modify anyting.
function Me.GopherChatPostQueue( event, msg, type, arg3, target )
	if Me.in_relay then return end
	if not Me.connected then return end
	
	-- 1, 7 = Orcish, Common
	if type == "SAY" or type == "EMOTE" or type == "YELL" 
	    and (arg3 == 1 or arg3 == 7) 
		      and (Me.InWorld() and not IsStealthed()) then
		-- In this hook we do the relay work. Firstly we ONLY send these if
		--  the user is visible and out in the world. We don't want to
		--  relay from any instances or things like that, because that's a
		--  clear privacy breach. We might want to check for some way to 
		--  test if the unit is invisible or something.
		local y, x = UnitPosition( "player" )
		if not y then return end
		local mapid = select( 8, GetInstanceInfo() )
		Me.SendPacketInstant( type, msg, mapid, 
									         Me.PackCoord(x), Me.PackCoord(y) )
		if type == "SAY" or type == "YELL" then
			-- For SAY and YELL we insert a queue break to keep things
			--  tidy for our chat bubble replacements. If the messages
			--  don't come at the same time, it's gonna throw off those
			--  bubbles!
			Gopher.QueueBreak()
		end
	end
end

-------------------------------------------------------------------------------
-- Returns true if the user can edit channels of the club they're connected to.
--
function Me.CanEditMute()
	if not Me.connected then return end
	local privs = C_Club.GetClubPrivileges( Me.club )
	return privs.canSetStreamSubject
end

-------------------------------------------------------------------------------
-- Returns true if the relay has "mute" set, meaning that /rp is reserved for
--  moderators or higher. This is set with putting a "#mute" tag in the relay
--  stream description.
function Me.IsMuted()
	local stream_info = C_Club.GetStreamInfo( Me.club, Me.stream )
	return stream_info and stream_info.subject:lower():find( "#mute" )
end

-------------------------------------------------------------------------------
-- Doesn't work. C_Club.EditStream is a protected function.
--
function Me.ToggleMute()
	if not Me.connected then return end
	local stream_info = C_Club.GetStreamInfo( Me.club, Me.stream )
	local desc = stream_info.subject
	if desc:find( "#mute" ) then
		desc = desc:gsub( "%s*#mute", "" )
	else
		desc = desc .. " #mute"
	end
	C_Club.EditStream( Me.club, Me.stream, nil, desc )
end

-------------------------------------------------------------------------------
-- Print formatted text prefixed with our Cross RP tag.
-- If additional args are given, they're passed to string.format.
function Me.Print( text, ... )
	if select( "#", ... ) > 0 then
		text = text:format( ... )
	end
	text = "|cFF22CC22<"..L.CROSS_RP..">|r |cFFc3f2c3" .. text:gsub("|r", "|cFFc3f2c3")
	print( text )
end

-------------------------------------------------------------------------------
-- Print formatted localized text. Prefixes it with our Cross RP tag.
-- Additional args are passed to the localization substitution, 
--  e.g. L( "STRING", ... )
function Me.PrintL( key, ... )
	local text = L( key, ... )
	print( "|cFF22CC22<"..L.CROSS_RP..">|r |cFFc3f2c3" .. text:gsub("|r", "|cFFc3f2c3") )
end

-------------------------------------------------------------------------------
-- After spending all night trying to add the WHISPER button back to the target
--  unit popup without tainting everything else (Set Focus), here's a bit more
--  of a basic solution. UnitPopup_ShowMenu is what populates it, and
--  I don't /really/ like this solution, because it still taints a bunch of
--  things after UnitPopup_ShowMenu returns. It might be better to rework this
--              in a hook inside of the function that calls ToggleDropDownMenu.
function Me.SetupHordeWhisperButton()
	hooksecurefunc( "UnitPopup_ShowMenu", function( menu, which, unit, 
	                                                          name, userData )
		if not Me.db.global.whisper_horde then return end
		
		if UIDROPDOWNMENU_MENU_LEVEL == 1 and unit == "target" and unit then
			local is_player = UnitIsPlayer( unit )
			local is_online = UnitIsConnected( unit )
			local name    = UIDROPDOWNMENU_INIT_MENU.name
			local server  = UIDROPDOWNMENU_INIT_MENU.server
			local add_whisper_button = is_player 
			   and (UnitFactionGroup("player") ~= UnitFactionGroup("target"))
				      and is_online and Me.GetBnetInfo( name .. "-" .. server )
			local info
			
			-- We're adding the whisper button at the very end here. It's
			--  somewhat impossible to add it where it usually is without
			--                      corrupting everything else with taint.
			-- We have redundant ifs here, in case we want to add more
			--  options below the whisper button. This if would contain
			--  all of the conditions together to add the separator and
			--  Cross RP section, and then below we add the different
			--  items.
			if add_whisper_button then
				UIDropDownMenu_AddSeparator( UIDROPDOWNMENU_MENU_LEVEL );
				info = UIDropDownMenu_CreateInfo();
				info.text         = L.CROSS_RP;
				info.isTitle      = true;
				info.notCheckable = true;
				UIDropDownMenu_AddButton( info );
			end
			
			if add_whisper_button then
				info = UIDropDownMenu_CreateInfo();
				info.text         = L.WHISPER;
				info.notCheckable = true;
				info.func         = function()
					-- A lot of magic going on here, when dealing with hooking
					--  and hacking something else up. `name` and `server`
					--  are set in the menu base by the upper code.
					-- Not 100% sure if `server` is really optional.
					if not server then server = GetNormalizedRealmName() end
					ChatFrame_SendTell( name .. "-" .. server, 
					                       UIDROPDOWNMENU_INIT_MENU.chatFrame )
				end
				-- A good interface has tooltips on everything.
				info.tooltipTitle    = info.text
				info.tooltipText     = L.WHISPER_TIP;
				info.tooltipOnButton = true
				UIDropDownMenu_AddButton( info );
			end
		end
	end)
end

-------------------------------------------------------------------------------
-- Enables or disables listening to an RP channel type. `index` may be 1-9 or
--                                         'W'. `enable` turns it on or off.
function Me.ListenToChannel( index, enable )
	local key = "RP" .. index
	Me.db.global["show_" .. key:lower()] = enable
	
	-- We also disable the chatbox from accessing it.
	Me.UpdateChatTypeHashes()
end

-------------------------------------------------------------------------------
-- Chat link hook.
--
function Me.SetHyperlinkHook( self, link, ... )
	if strsub(link, 1, 8) == "CrossRP:" then
		if IsModifiedClick("CHATLINK") then
			-- Shift-clicked?
		else
			local link_type, command = strsplit(":", link)
			if command == "enable_relay" then
				Me.EnableRelay( true )
			end
		end
		
		return
	end
	
	Me.hooks[ItemRefTooltip].SetHyperlink( self, link, ... )
end

-------------------------------------------------------------------------------
-- This allows us to insert invalid line IDs into the chatbox.
--
function Me.HookPlayerLinks()
	if not Me.hooked_player_links then
		Me.hooked_player_links = true
		Me:RawHook( "GetPlayerLink", Me.GetPlayerLinkHook, true )
	end
end

-------------------------------------------------------------------------------
-- Fixup for GetPlayerLink when using an invalid line ID
--
function Me.GetPlayerLinkHook( character_name, link_display_text, line_id, 
                                                                          ... )
	if not line_id or line_id <= 0 then
		-- What Blizzard's code does is uses 0 for line IDs that are invalid.
		--  That zero slips through in some places though, and causes the
		--  report system to fuck up, so we're obliterating it in here. There
		--  are proper checks inside GetPlayerLink. This may break targeting
		--  players from the chat frame...?
		return Me.hooks.GetPlayerLink( character_name, link_display_text )
	end
	return Me.hooks.GetPlayerLink( character_name, link_display_text, 
	                                                             line_id, ... )
end

-------------------------------------------------------------------------------
function Me.FixupTRPChatNames()
	if not TRP3_API then return end
	
	Me:RawHook( TRP3_API.utils, "customGetColoredNameWithCustomFallbackFunction",
		function( fallback, event, ...)
			if event:match( "CHAT_MSG_RP[1-9]" ) then
				event = "CHAT_MSG_RAID"
			elseif event == "CHAT_MSG_RPW" then
				event = "CHAT_MSG_RAID_WARNING"
			end
			return Me.hooks[TRP3_API.utils].customGetColoredNameWithCustomFallbackFunction( fallback, event, ... )
		end)
end

function Me.DebugLog()
	
end

--@debug@                                
-- Any special diagnostic stuff we can insert here, and curse packaging pulls
--  it out. Keep in mind that this is potentially risky, and you want to test
--  /without/ the debug info, in case anything arises from doing just that.
C_Timer.After( 1, function()

	--Me.Connect( 32381,1 )
end)

LibGopher.Internal.print_listener_errors = true

function Me.DebugLog( text, ... )
	if select( "#", ... ) > 0 then
		text = text:format(...)
	end
	print( "|cFF0099FF[CRP]|r", text )
end

function Me.DebugLog2( ... )
	print( "|cFF0099FF[CRP]|r", ... )
end

--@end-debug@
--                                   **whale**
--                                             __   __
--                                            __ \ / __
--                                           /  \ | /  \
--                                               \|/
--                                          _,.---v---._
--                                 /\__/\  /            \
--                                 \_  _/ /              \ 
--                                   \ \_|           @ __|
--                                hjw \                \_
--                                `97  \     ,__/       /
--~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`~~~~~~~~~~~~~~/~~~~~~~~~~~~~~~~~~~~~~~