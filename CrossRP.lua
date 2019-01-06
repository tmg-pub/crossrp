-------------------------------------------------------------------------------
-- Cross RP
-- by Tammya-MoonGuard (2019)
--
-- All Rights Reserved
--
-- Provides tools for roleplayers to have a smooth cross-faction RP experience.
--
-- Project concerns and goals:
--  * Compatibility - players without Cross RP should be able to engage easily
--     with Cross RP users, just without its conveniences.
--  * Easy setup - things should be even easier this time around, with the
--     internal mechanisms being mostly invisible.
--  * Seamless feel - when RPing with the opposing faction, it should be just
--     like your own faction, with /e handled as well.
--  * RP profiles - one of the biggest divides between cross-faction RP, 
--     solved! This should bridge cross-realm too.
--  * Event tools - things like dice rolls, raid/rp chat, and such, to emulate
--     a normal RP raid environment.
-------------------------------------------------------------------------------

local _, Me         = ...
local L             = Me.Locale
local Gopher        = LibGopher
local LibRealmInfo  = LibStub("LibRealmInfo")

-------------------------------------------------------------------------------
-- Exposed to the outside world as CrossRP. It's an easy way to see if the
--              addon is installed.
CrossRP = Me
-------------------------------------------------------------------------------
-- Embedding AceAddon into it. I like the way AceHook handles hooks and it 
--  leaves everything a bit neater for us. We'll embed that and AceEvent
--                                  for the slew of events that we handle.
LibStub("AceAddon-3.0"):NewAddon( Me, "CrossRP", 
                                        "AceEvent-3.0", "AceHook-3.0" )
-------------------------------------------------------------------------------
Me.version        = "1.7.3"
Me.version_flavor = "|cFFFFFF00" .. "Alpha Testing"
-------------------------------------------------------------------------------
-- The name of the channel that we join during startup, shared for all
--                          Cross RP users to make local data broadcasts.
Me.data_channel = "crossrp"
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
-- Tracks the time when we touch a player of the opposite faction. Used for
--  detecting an "active" state, which is having the opposite faction nearby
--  with the flask enabled.
Me.horde_touched = 0
-------------------------------------------------------------------------------
-- This contains some user information for players we come across.
-- Formatted as "F:R:TIME"
--  * F     "A" or "H" (faction).
--  * R     Realm relation (UnitRealmRelationship)
--  * TIME  Game time.
-- Indexed by fullname.
Me.touched_users = {}

-------------------------------------------------------------------------------
-- If "Translate Emotes" is checked in the minimap menu. This isn't a
--  persistent option because that will just lead to users accidentally leaving
--  it off for whatever reason.
Me.translate_emotes_option = true

-------------------------------------------------------------------------------
-- A simple helper function to return the name of the language the opposing
--                                                  faction uses by default.
local function HordeLanguage()
	return Me.faction == "A" and L.LANGUAGE_1 or L.LANGUAGE_7
end

-------------------------------------------------------------------------------
-- Chat filter for /say and /yell public text.
function Me.ChatFilter_Say( _, _, msg, sender, language, ... )
	if msg:match( "^<.*>$" ) then
		-- This is an emote, so we cancel this, and in our other handler we
		--  will simulate an emote message.
		return true
	end
	
	-- If we're active, strip the language tag for Orcish/Common. Basically
	--  it has no use. Horde speak Orcish, Alliance speak Common.
	if Me.active and language == HordeLanguage() then
		language = GetDefaultLanguage()
		return false, msg, sender, language, ...
	end
end

-------------------------------------------------------------------------------
-- Some modules need to cache some references locally after we start up.
function Me.CacheRefs()
	Me.TRP.CacheRefs()
end

-------------------------------------------------------------------------------
-- Called after all of the initialization events.
--
function Me:OnEnable()
	if not Me.CheckFiles() then
		Me.Print( L.UPDATE_ERROR )
		return
	end
	
	Me.CacheRefs()
	
	Me.CreateDB()
	
	-- Me.db.char.debug is a persistent value to enable debug mode after
	--  /reloads.
	if Me.db.char.debug then
		Me.Debug()
	end
	
	-- Fetch and cache our identity.
	do
		local my_name, my_realm = UnitFullName( "player" )
		Me.realm      = my_realm
		Me.faction    = UnitFactionGroup( "player" ):sub(1,1)
		Me.fullname   = my_name .. "-" .. my_realm
	end
	
	---------------------------------------------------------------------------
	-- Hook events and messages.
	Me.EventRouting()
	
	---------------------------------------------------------------------------
	-- These are for stripping language tags when we're active.
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_SAY", Me.ChatFilter_Say )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_YELL", Me.ChatFilter_Say )
	
	-- For Bnet whispers, we catch when we have a Cross RP tag applied, and 
	--  then block the chat, re-submitting them as a normal character whisper.
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_BN_WHISPER",
	                                              Me.ChatFilter_BNetWhisper )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_BN_WHISPER_INFORM",
	                                              Me.ChatFilter_BNetWhisper )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_SYSTEM",
	                                               Me.Comm.SystemChatFilter )
												  
	-- We depend on Gopher for some core
	--  functionality. The CHAT_NEW hook isn't too important; it's just so we
	--  can block the user from posting in a relay channel. The QUEUE hook 
	--  is mainly for catching our custom types, and then re-routing them. 
	--  We're doing it this way so we can still use Gopher's cutter, 
	--                       and we send one relay packet per split message.
	-- The POST queue is to catch outgoing public chat and then inserting
	--  translation messages that are relayed. Gopher's API has been
	--  designed to accommodate this specifically, in regard to sending these
	--                                                 messages in tandem.
	Gopher.Listen( "CHAT_NEW",       Me.GopherChatNew       )
	Gopher.Listen( "CHAT_QUEUE",     Me.GopherChatQueue     )
	Gopher.Listen( "SEND_DEATH", function()
		-- Reset this flag if chat fails for whatever reason.
	end)
	
	-- Hook the unit popup frame to add the whisper button back when
	--  right-clicking on a Horde target. Again, we just call it horde, 
	--                          when it just means the opposing faction.
	Me.SetupHordeWhisperButton()
	
	-- Initialize our DataBroker source and such.
	Me.SetupMinimapButton()
	
	-- Call this after everything to apply our saved options from the database.
	Me.ApplyOptions()
	
	Me.startup_time = GetTime()
	
	local ht_cached = Me.db.char.horde_touched
	if ht_cached then
		Me.horde_touched = 
		               math.min( GetTime(), GetTime() - ( time() - ht_cached ))
	end
	
	-- Start our update loop. (This starts a repeating timer.)
	Me.UpdateActive()
	
	-- And the rest...
	Me.ButcherElephant()
	Me.ShowMOTD()
	Me.Proto.Init()
	Me.RPChat.Init()
	Me.Map_Init()
	Me.MSP.Init()
	Me.TRP.Init()
	
	Me.FixupTRPChatNames()
end

-------------------------------------------------------------------------------
-- Sets up event and message routing. Simple functions can be placed in here
--  to couple functions to events.
function Me.EventRouting()
	local Events = {
		CHAT_MSG_SAY = Me.OnChatMsg;
		
		CHAT_MSG_BN_WHISPER        = Me.OnChatMsgBnWhisper;
		CHAT_MSG_BN_WHISPER_INFORM = Me.OnChatMsgBnWhisper;
		
		CHAT_MSG_ADDON    = Me.Comm.OnChatMsgAddon;
		BN_CHAT_MSG_ADDON = Me.Comm.OnBnChatMsgAddon;
		
		UPDATE_MOUSEOVER_UNIT = function( ... )
			Me.OnMouseoverUnit()
			Me.Proto.OnMouseoverUnit()
			Me.TRP.OnMouseoverUnit()
		end;
		
		PLAYER_TARGET_CHANGED = function( ... )
			Me.OnTargetChanged()
			Me.Proto.OnTargetUnit()
			Me.TRP.OnTargetChanged()
		end;
		
		BN_FRIEND_INFO_CHANGED = Me.Proto.OnBnFriendInfoChanged;
		
		PLAYER_LOGOUT = function()
			local time = time()
			-- GetTime() is session based, so we convert horde_touched into a
			--  time() based value, and restore it on reload.
			Me.db.char.horde_touched = time - (GetTime() - Me.horde_touched)
			Me.db.char.logout_time = time
			Me.Proto.Shutdown()
		end;
		
		GROUP_LEFT   = Me.RPChat.OnGroupLeave;
		GROUP_JOINED = Me.RPChat.OnGroupJoin;
		
		CHAT_MSG_SYSTEM = function( ... )
			Me.Rolls.OnChatMsgSystem( ... )
			Me.Proto.OnChatMsgSystem( ... )
		end;
	}
	
	local Messages = {
		CROSSRP_PROTO_START = function()
			-- RPChat might set secure mode, so we do its post-init right here.
			Me.RPChat.OnProtoStart()
		end;
		
		CROSSRP_PROTO_START3 = function()
			Me.RPChat.OnProtoStart3()
		end;
	}
	
	for event, destination in pairs( Events ) do
		Me:RegisterEvent( event, destination )
	end
	
	for message, destination in pairs( Messages ) do
		Me:RegisterMessage( message, destination )
	end
	
	Me.EventRouting = nil
end

-------------------------------------------------------------------------------
-- Returns the duration remaining for the Elixir of Tongues buff on the unit
--  specified, or `nil` if they're not using it (or if the unit is invalid).
function Me.UnitHasElixir( unit )
	local ELIXIR_OF_TONGUES = 2336
	local buff_expiry
	for i = 1, 40 do
		local name, _,_,_,_, expiration, _,_,_, spell = UnitBuff( unit, i )
		if spell == ELIXIR_OF_TONGUES then
			buff_expiry   = expiration
			return buff_expiry - GetTime()
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- Touch test for horde using the elixir. Pass in the unit for them, and if
--  they have it active, we'll reset our touched time. If we have an elixir on
--  as well, then we'll switch to "active" state on the next update pass.
function Me.TouchTest( unit )
	if not UnitIsPlayer( unit ) then return end
	local time = GetTime()
	local fullname = Me.GetFullName( unit )
	local faction = UnitFactionGroup( unit ):sub(1,1)
	local relation = UnitRealmRelationship( unit )
	
	-- Record their data.
	Me.touched_users[fullname] = faction .. ":" .. relation .. ":" .. time
	if Me.UnitHasElixir( unit ) then
		if UnitIsEnemy( "player", unit ) then
			Me.horde_touched = time
		end
	end
end

-------------------------------------------------------------------------------
-- Returns true if the horde touch time is recent (15 minutes).
function Me.TouchingHorde()
	return GetTime() - Me.horde_touched < 15*60
end

-------------------------------------------------------------------------------
-- Handler for when the player mouses over a unit.
function Me.OnMouseoverUnit()
	Me.TouchTest( "mouseover" )
end

-------------------------------------------------------------------------------
-- Handler for when the player changes their target.
function Me.OnTargetChanged()
	Me.TouchTest( "target" )
end

-------------------------------------------------------------------------------
-- Routine function to update our active state.
function Me.UpdateActive()
	
	local ELIXIR_EXPIRED_GRACE_PERIOD = 5*60
	local buff_time = Me.UnitHasElixir( "player" )
	
	if buff_time then
		Me.elixir_active = true
		Me.elixir_time   = buff_time
	else
		Me.elixir_active = false
	end
	
	Me.TouchTest( "target" )
	
	if not Me.active then
		-- Switch to "active" if we have the Elixir of Tongues buff and have
		--  seen any horde nearby with it.
		if buff_time and Me.TouchingHorde() then
			Me.SetActive( true )
		end
	else
		-- Disable it if we haven't seen any horde in a while.
		if not Me.TouchingHorde() then
			Me.SetActive( false )
		else
			if not buff_time then
				-- Also disable it after a bit of a grace period after the
				--  elixir expires.
				if not Me.grace_period_time then
					Me.grace_period_time = GetTime()
				else
					local expires =
					         Me.grace_period_time + ELIXIR_EXPIRED_GRACE_PERIOD
					if GetTime() > expires then
						Me.SetActive( false )
					end
				end
			end
		end
	end
	
	if Me.active and buff_time then
		if buff_time < 180 then
			if not Me.elixir_notice_given then
				Me.elixir_notice_given = true
				Me.ElixirNotice.Show()
			end
		elseif buff_time > 50*60 then
			Me.elixir_notice_given = false
		end
	end
	
	-- This is a switch to enable/disable /e translations (conversions to
	--  /say). It's coupled with the minimap menu option.
	Me.emote_rerouting = Me.active and buff_time
	
	Me.UpdateIndicators()
	Me.Timer_Start( "update_active", "push", 1.0, Me.UpdateActive )
end

-------------------------------------------------------------------------------
-- "Active" is set when Cross RP detects that we're doing cross-faction RP,
--  which is when we have the elixir on and are nearby horde with it on too.
function Me.SetActive( active )
	if not active then
		Me.grace_period_time = nil
	end
	
	Me.active = active
	Me.UpdateIndicators()
end

-------------------------------------------------------------------------------
-- Returns the fullname for the unit specified. That is "Name-Realm". Also
--  returns realm by itself.
function Me.GetFullName( unit )
	if not UnitIsPlayer( unit ) then return end
	local name, realm = UnitName( unit )
	if not realm or realm == "" then
		if UnitRealmRelationship( unit ) == LE_REALM_RELATION_SAME then
			-- On our realm, so use our realm name.
			return name .. "-" .. Me.realm, Me.realm
		end
		
		-- Otherwise look up their realm from their GUID.
		local guid = UnitGUID( "player" )
		local found, _,_,_,_,_, realm = GetPlayerInfoByGUID( guid )
		if not found then return end
		if not realm or realm == "" then realm = Me.realm end
		realm = realm:gsub( "[ -]", "" )
		return name .. "-" .. realm, realm
	end
	return name .. "-" .. realm, realm
end

-------------------------------------------------------------------------------
local BUTTON_ICONS = {
	ON   = "Interface\\Icons\\INV_Jewelcrafting_ArgusGemCut_Green_MiscIcons";
	IDLE = "Interface\\Icons\\INV_Jewelcrafting_ArgusGemCut_Blue_MiscIcons";
	HALF = "Interface\\Icons\\INV_Jewelcrafting_ArgusGemCut_Yellow_MiscIcons";
	OFF  = "Interface\\Icons\\INV_Jewelcrafting_ArgusGemCut_Red_MiscIcons";
}

-------------------------------------------------------------------------------
-- Called when we connect, disconnect, enable/disable the relay, or anything
--  else which otherwise needs to update our connection indicators and 
--                                               front-end stuff.
function Me.UpdateIndicators()
	
	-- While these sorts of functions aren't SUPER efficient, i.e. re-setting
	--  everything for when only a single element is potentially changed, it's
	--  a nice pattern to have for less performance intensive parts of things.
	-- Just keeps things simple.
	if Me.active then
		if not Me.active_expiring then
			Me.ldb.icon = BUTTON_ICONS.ON
			Me.ldb.text = ""
			Me.ldb.label = "|cFF22CC22" .. L.CROSS_RP
		else
			-- Yellow for expiring-soon.
			Me.ldb.icon = BUTTON_ICONS.HALF
			Me.ldb.text = ""
			Me.ldb.label = "|cFFCCCC11" .. L.CROSS_RP
		end
	else
		Me.ldb.icon = BUTTON_ICONS.OFF
		Me.ldb.text = ""
		Me.ldb.label = L.CROSS_RP
	end
end

-------------------------------------------------------------------------------
-- Handler for when we receive a CHAT_MSG_SAY/EMOTE/YELL event, a public chat
--  event.
function Me.OnChatMsg( event, text, sender, language, 
                                                _,_,_,_,_,_,_, lineID, guid )

	-- We don't pass around GUIDs, we simply record them in a global table like
	--  this as we see them, and then reference them if we can. If we don't
	--  have a GUID for someone, it's not a huge deal. The Blizzard chat frames
	--  don't crash if you don't give them a GUID with a message.
	if guid then
		Me.player_guids[sender] = guid
	end
	
	if event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" then
		local emote = text:match( "^<(.*)>$" )
		if emote then
			local name_cutoff = emote:find( " " )
			if name_cutoff then
				emote = emote:sub( name_cutoff + 2 )
			end
			Me.Bubbles_Capture( sender, text, "EMOTE" )
			Me.SimulateChatMessage( "EMOTE", emote, sender, nil, lineID, guid )
		else
			Me.Bubbles_Capture( sender, text, "RESTORE" )
		end
	elseif event == "CHAT_MSG_YELL" then
		Me.Bubbles_Capture( sender, text, "RESTORE" )
	end
	
	-- They don't need the elixir on. If we're near enough to hear a hordie talk,
	--  then reset the timer.
	if language == HordeLanguage() then
		Me.horde_touched = GetTime()
	end
end

-------------------------------------------------------------------------------
-- Prints a chat message to the chat boxes, as well as forwards it to addons
--  like Listener and WIM (via LibChatHandler).
--    event_type  SAY, EMOTE... Can also be our custom types "RP", "RP2" etc.
--    msg       Message text.
--    username  Sender's fullname.
--    language  Language being spoken. Leave nil to use default language.
--    lineid    Message line ID. Leave nil to generate one.
--    guid      Sender's GUID. Leave nil to try to pull it from our data.
--
function Me.SimulateChatMessage( event_type, msg, username, 
                                                      language, lineid, guid )
	if username == Me.fullname then
		guid = UnitGUID( "player" )
	else
		guid = guid or Me.player_guids[username]
	end
	
	language = langauge or (GetDefaultLanguage())
	
	-- Other addons can intercept this message.
	Me:SendMessage( "CROSSRP_CHAT", event_type, msg, username, guid, lineid )
	
	if not lineid then
		-- Not actually sure if this is safe, using negative line IDs. It's
		--  something that we do for TRP compatibility. Other way we can fix
		--  this is if we patch TRP to process their chat messages differently.
		-- MIGHT WANT TO LOOK AT THAT BEFORE THE 8.0 PATCH, SO EVERYONE
		--  WILL HAVE IT.
		lineid = Me.fake_lineid
		Me.fake_lineid = Me.fake_lineid - 1
	end
	
	local event_check = event_type
	
	-- Catch if we're simulating one of our super special RP types.
	-- For the normal ones we use the chatbox filter RAID, and
	--                                for /rpw, RAID_WARNING.
	local rptype = event_type:match( "^RP([1-9W])" )
	
	local rpchat_windows = Me.db.char.rpchat_windows
	
	-- We have a bunch of block_xyz_support variables. These are for future
	--  proofing, when some other addon wants to handle our message that we
	--  trigger, and then block how it normally happens. Or for whatever reason
	--  someone might want to block our interaction with something. These are 
	--                            placed where we interact with other addons.
	if not Me.block_chatframe_support then
		-- We save this hook until we're about to abuse the chatboxes. That
		--  way, if the person isn't actively using Cross RP (which is most
		--  of the time), link construction isn't going to be touched.
		Me.HookPlayerLinks()
		
		for i = 1, NUM_CHAT_WINDOWS do
			local frame = _G["ChatFrame" .. i]
			local show = false
			if rptype then
				-- Check if RP chat is enabled for this window.
				if rpchat_windows[i] and rpchat_windows[i]:find( rptype ) then
					show = true
				end
			else
				show = frame:IsEventRegistered( "CHAT_MSG_" .. event_check )
			end
			
			if show then
				ChatFrame_MessageEventHandler( frame, 
				       "CHAT_MSG_" .. event_type, msg, username, language, "", 
					                    "", "", 0, 0, "", 0, lineid, guid, 0 )
			end
		end
	end
	
	-- Listener support. Listener handles the RP messages just fine, even if
	--  an older version is being used. (I think...)
	if ListenerAddon and not Me.block_listener_support then
		ListenerAddon:OnChatMsg( "CHAT_MSG_" .. event_type, msg, username, 
		                 language, "", "", "", 0, 0, "", 0, lineid, guid, 0 )
	end
	
	-- Only pass valid to here. (Or maybe not?)
	if (not is_rp_type) and not Me.block_libchathandler_support then 
		if LibChatHander_EventHandler then
			local lib = LibStub:GetLibrary("LibChatHandler-1.0")
			if lib.GetDelegatedEventsTable()["CHAT_MSG_" .. event_type] then
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
	
	-- Elephant support. (elephant.lua)
	Me.ElephantLog( event_type, msg, username, language, lineid, guid )
end

-------------------------------------------------------------------------------
-- Simple helper function to parse the location arguments from a normal chat
--  command. All strings: arg1 is the continent ID, arg2/arg3 are the packed 
--  coordinates.
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
-- Checks if a username belongs to a player that you can addon-whisper to.
--  `party_is_local` will make xrealm players return true if they're in your
--  party. Returns `nil` when we don't have enough information on the player
--                                      to properly determine the result.
local LE_REALM_RELATION_COALESCED_STR = tostring(LE_REALM_RELATION_COALESCED)
function Me.IsLocal( username, party_is_local )
	
	if Me.GetBnetInfo( username ) then return true end -- Bnet friend.
	
	local user = Me.touched_users[username]
	if not user then return end
	
	-- touched user format: F:R:TIME
	
	if user:sub(1,1) ~= Me.faction then
		--
		return false
	end
	
	local relation = user:sub(3,3)
	if relation == LE_REALM_RELATION_COALESCED_STR then
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
	-- In the pattern there's a no-break space, to differentiate it from
	--              someone pasting whispers from their normal chat log.
	local sender, text = text:match( "^%[([^%-]+%-[^%]]+)%] (.+)" )
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
				
				-- 7/24/18 On second thought, we should just not show this, as
				--  there can be some "messing around" that friends can do. In
				--  other words, only allow whispers coming from verified
				--  sources; that is, when the battle.net friend is online and
				--                                sending from their character.
				return
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
	-- Warning: pattern has a no-break space.
	local sender, text = text:match( "^%[([^%-]+%-[^%]]+)%] (.+)" )
	if sender then
		if event == "CHAT_MSG_BN_WHISPER_INFORM" 
		                            and not Me.bnet_whisper_names[bnet_id] then
			-- We didn't send this or we lost track, so just make it show up
			--  normally...
			-- The former case might show up when we're running two WoW
			--  accounts on the same Bnet account; both will probably receive
			--  the whisper inform.
			
			-- 7/24/18 Just don't show it. We have a special pattern now.
			--return
		end
		
		return true
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
	-- As far as I know, faction isn't localized from the Bnet info.
	if account_id and faction ~= UnitFactionGroup("player") then
		-- This is a cross-faction whisper.
		-- TODO: Not sure how this behaves when the target is playing on two
		--  WOW accounts.
		-- TODO: This probably needs a SUPPRESS.
		-- Warning: formatted message has a no-break space.
		BNSendWhisper( account_id, "[" .. Me.fullname .. "] " .. msg )
		--                                                 ^
		-- Note that the formatted message has a no-break space.
		
		-- Save their name so we know what the INFORM message
		--  is for.
		Me.bnet_whisper_names[account_id] = target
		return false
	end
end

-------------------------------------------------------------------------------
-- Triggers when the user wants to send a new chat message, and Gopher passes
--  us the entire chatbox text.
function Me.GopherChatNew( event, msg, type, arg3, target )

	-- If Cross RP is active, then we reroute EMOTE to a say message with the
	--  text wrapped in emote marks.
	if Me.emote_rerouting and Me.translate_emotes_option 
	                                           and type:upper() == "EMOTE" then
		Gopher.SetPadding( "<", ">" )
		local _, name = LibRPNames.Get( Me.fullname, UnitGUID("player") )
		-- no break space
		msg = name .. " " .. msg
		return msg, "SAY", arg3, target
	end
	
	
	local rptype = type:match( "^(RP[1-9W])" )
	
	-- Basically we want to intercept when the user is trying to send our
	--  [invalid] chat types RPW, RP1, RP2, etc... and then we catch them
	--               in here to reroute them to our own system as packets.
	if rptype then
		Me.RPChat.OnGopherNew( rptype, msg )
		return false -- Block the original message.
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
			local server  = UIDROPDOWNMENU_INIT_MENU.server or GetNormalizedRealmName()
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
-- This allows us to insert invalid line IDs into the chatbox. Basically this
--  needs to be called before doing so to avoid errors when interacting with
--  invalid line IDs (when right-clicking player names).
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
-- Are those some long ass function names or what? This reroutes a few of our
--  fake events to valid events so they work right with TRP's chat hooks.
--
function Me.FixupTRPChatNames()
	if not TRP3_API then return end
	
	Me:RawHook( TRP3_API.utils, "customGetColoredNameWithCustomFallbackFunction",
		function( fallback, event, ...)
			if event:match( "CHAT_MSG_RP[1-9]" ) then
				event = "CHAT_MSG_RAID"
			elseif event == "CHAT_MSG_RPW" then
				-- TRP doesn't hook RAID_WARNING yet.
				event = "CHAT_MSG_RAID" 
			end
			return Me.hooks[TRP3_API.utils].customGetColoredNameWithCustomFallbackFunction( fallback, event, ... )
		end)
end

-------------------------------------------------------------------------------
-- Sometimes players may update and then /reload, but that may break if we add
--  files to the distribution. This checks something defined in each file to
--                                        make sure that we have everything.
function Me.CheckFiles()
	-- We really only need to check the few newest files. Everything else
	--  should be loaded.
	local loaded = Me.Proto -- proto.lua (1.6.0)
	return loaded
end

-------------------------------------------------------------------------------
-- Debug Functions
-------------------------------------------------------------------------------
-- Log a debug message to chat. Only works when DEBUG_MODE is on. Trailing
--  arguments are formatting parameters. The text will not go through the 
--  format function if no additional arguments are given.
--
function Me.DebugLog( text, ... )
	if not Me.DEBUG_MODE then return end
	
	local delta = (GetTime() - (Me.last_debug_log or 0)) * 1000
	Me.last_debug_log = GetTime()
	if delta > 0 then
		delta = string.format( " +%dms", delta )
	else
		delta = ""
	end
	
	if select( "#", ... ) > 0 then
		text = text:format(...)
	end
	print( "|cFF0099FF[CRP" .. delta .. "]|r", text )
end

-------------------------------------------------------------------------------
-- Alternate version that doesn't use string format, but rather just passes
--                                                   all arguments to `print`.
function Me.DebugLog2( ... )
	if not Me.DEBUG_MODE then return end
	
	local delta = (GetTime() - (Me.last_debug_log or 0)) * 1000
	Me.last_debug_log = GetTime()
	if delta > 0 then
		delta = string.format( " +%dms", delta )
	else
		delta = ""
	end
	
	print( "|cFF0099FF[CRP" .. delta .. "]|r", ... )
end

-------------------------------------------------------------------------------
-- Enable Debug Mode, which displays diagnostic information and logging for 
--  various things. `CrossRP.Debug(false)` or /reload to turn off.
--
function Me.Debug( on )
	if on == nil then on = true end
	Me.DEBUG_MODE = on
end

function Me.Test()
	--Proto.BnetPacketHandlers.HO( "HO", "1", 1443 )
	--Proto.Send( "Catnia1H", "to catnia." )
	--Proto.Send( "1H", "to all( baon)." )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky. Bacon ipsum dolor amet buffalo picanha biltong tail leberkas spare ribs kevin hamburger boudin pork capicola ball tip landjaeger pancetta. Shank buffalo pig leberkas burgdoggen, chuck salami jowl shankle biltong capicola jerky." )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Shankle pig pork loin, ham salami landjaeger sirloin rump turducken. Beef ribs pork belly ground round, filet mignon pork kielbasa boudin corned beef picanha kevin. Tail ribeye swine venison. Short ribs leberkas flank, jerky ribeye drumstick cow sirloin sausage.Shankle pig pork loin, ham salami landjaeger sirloin rump turducken. Beef ribs pork belly ground round, filet mignon pork kielbasa boudin corned beef picanha kevin. Tail ribeye swine venison. Short ribs leberkas flank, jerky ribeye drumstick cow sirloin sausage." )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Jerky tail cow jowl burgdoggen, short loin kevin sirloin porchetta. Meatloaf strip steak salami cupim leberkas, andouille hamburger landjaeger tongue swine beef filet mignon meatball. Chuck pork belly tenderloin strip steak sausage flank, pork turducken jowl tri-tip. Jerky tail cow jowl burgdoggen, short loin kevin sirloin porchetta. Meatloaf strip steak salami cupim leberkas, andouille hamburger landjaeger tongue swine beef filet mignon meatball. Chuck pork belly tenderloin strip steak sausage flank, pork turducken jowl tri-tip. " )
	--Me.Comm.SendAddonPacket( "Tammya-MoonGuard", nil, true, "Pork loin chicken cow sirloin, ham pancetta andouille. Fatback biltong jerky ground round turducken. Pancetta jowl capicola picanha spare ribs shankle bresaola.Pork loin chicken cow sirloin, ham pancetta andouille. Fatback biltong jerky ground round turducken. Pancetta jowl capicola picanha spare ribs shankle bresaola." )
	--Me.Proto.SetSecure( "henlo" )
	
	--Me.horde_touched = GetTime()
	--Me.RPChat.Start('hi')
	
	local s256 = Me.Sha256
	local start = debugprofilestop()
	for i = 1, 10000 do
		s256( "henlo" )
	end
	local stop = debugprofilestop()
	print( ":", stop-start )
	
	print( s256( "henlo" ))
	
	-- 10000 iterations: 4300 seconds (0.43 milliseconds)
	
	--Me.RPChat.QueueMessage( "Poopie-MoonGuard", "RP1", "Bacon ipsum dolor amet drumstick pancetta shankle cupim picanha fatback, filet mignon t-bone hamburger ball tip. Beef ribs cow capicola swine ground round porchetta. Ground round alcatra tail turkey tenderloin jowl leberkas short ribs spare ribs pork chop landjaeger short loin. Ribeye tail corned beef kielbasa, leberkas andouille pig boudin. Leberkas kielbasa jerky prosciutto. Ball tip chicken jerky brisket turducken buffalo picanha, tenderloin boudin swine beef biltong. Turkey salami pork swine shoulder sausage kevin alcatra ham jerky ribeye bacon jowl turducken.", 3 )
	--Me.RPChat.QueueMessage( "Poopie-MoonGuard", "RP1", "Hello", 2 )
	--Me.RPChat.QueueMessage( "Poopie-MoonGuard", "RP1", "Hi", 1 )
	
	
	
	--Proto.Send( "all", "hitest", true )
	
	--C_ChatInfo.RegisterAddonMessagePrefix( "+TEN" )
	---C_ChatInfo.SendAddonMessage( "asdf", "hi", "CHANNEL", GetChannelName( "crossrp" ))
	--C_ChatInfo.SendAddonMessage( "asdf", "hi", "WHISPER", "Tammya-MoonGuard" )
end

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