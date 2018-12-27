-------------------------------------------------------------------------------
-- Cross RP
-- by Tammya-MoonGuard (2018)
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

local AddonName, Me = ...
local L             = Me.Locale
local Gopher        = LibGopher
local LibRealmInfo  = LibStub("LibRealmInfo")
Me.Private = Me.Private or {}
local Private = Me.Private

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
Me.version = "1.6.0-dev"

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

Me.horde_touched = 0
Me.translate_emotes_option = true

function Me.NameHash( name )
--[[	local sha = Me.Sha256Words( name )
	local hash = hash .. 
	for i = 1, 5
		local digit = sha % 63
		sha = math.floor(sha / 63)
		
	local digit1 = 
	return Me.Sha256Hex( name ):sub(1,6)]]
end

-------------------------------------------------------------------------------
-- A simple helper function to return the name of the language the opposing
--                                                  faction uses by default.
local function HordeLanguage()
	return UnitFactionGroup( "player" ) == "Alliance" 
	                                           and L.LANGUAGE_1 or L.LANGUAGE_7
end

-------------------------------------------------------------------------------
-- When we hear orcish, we outright block it if our connection is active.
--  In a future version we might have some time-outs where we allow the orcish
--                     to go through, but currently it's just plain discarded.
function Me.ChatFilter_Say( _, _, msg, sender, language, ... )
	if msg:match( "^<.*>$" ) then
		-- This is an emote, and another chat message will be simulated.
		return true
	end
	
	-- strip language tag
	if Me.active and language == HordeLanguage() then
		language = GetDefaultLanguage()
		return false, msg, sender, language, ...
	end
end

-------------------------------------------------------------------------------
-- This is for 'makes some strange gestures'. We want to block that too.
--  Localized strings are CHAT_EMOTE_UNKNOWN and CHAT_SAY_UNKNOWN.
--  CHAT_SAY_UNKNOWN is actually from /say. If you say something like
--  REEEEEEEEEEEEEEEEEE then it gets converted to an emote of you "saying
--                                            something unintelligible".
-- 1.4.1 includes CHAT_YELL_UNKNOWN and CHAT_YELL_UNKNOWN_FEMALE - these are 
--  triggered with the same case above with /say, but when using /yell.
function Me.ChatFilter_Emote( _, _, msg, sender, language )
	if Me.connected and (msg == CHAT_EMOTE_UNKNOWN or msg == CHAT_SAY_UNKNOWN 
	       or msg == CHAT_YELL_UNKNOWN or msg == CHAT_YELL_UNKNOWN_FEMALE) then
		return true
	end
end

-------------------------------------------------------------------------------
-- Called after all of the initialization events.
--
function Me:OnEnable()
	if not Me.CheckFiles() then
		Me.Print( L.UPDATE_ERROR )
		return
	end
	
	Me.CreateDB()
	if Me.db.char.debug then
		Me.Debug()
	end
	
	do
		local my_name, my_realm = UnitFullName( "player" )
		Me.realm      = my_realm
		Me.faction    = UnitFactionGroup( "player" ):sub(1,1)
		Me.fullname   = my_name .. "-" .. my_realm
	end
	
	---------------------------------------------------------------------------
	-- Event Routing
	---------------------------------------------------------------------------
	Me.EventRouting()
	
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
	
	-- Hook the unit popup frame to add the whisper button back when
	--  right-clicking on a Horde target. Again, we just call it horde, 
	--                          when it just means the opposing faction.
	Me.SetupHordeWhisperButton()
	
	-- Initialize our DataBroker source and such.
	Me.SetupMinimapButton()
	
	Me.UpdateActive()
	
	-- Call this after everything to apply our saved options from the database.
	Me.ApplyOptions()
	
	Me.startup_time = GetTime()
	
	Me.ButcherElephant()
	
	Me.ShowMOTD()
	
	Me.Proto.Init()
	Me.RPChat.Init()
	Me.Map_Init()
end

-------------------------------------------------------------------------------
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
		end;
		
		PLAYER_TARGET_CHANGED = function( ... )
			Me.OnTargetChanged()
			Me.Proto.OnTargetUnit()
		end;
		
		BN_FRIEND_INFO_CHANGED = Me.Proto.OnBnFriendInfoChanged;
		
		PLAYER_LOGOUT = function()
			Me.db.char.logout_time = time()
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
function Me.HordeTouchTest( unit )
	if UnitIsEnemy( "player", unit ) and Me.UnitHasElixir( unit ) then
		Me.horde_touched = GetTime()
	end
end

-------------------------------------------------------------------------------
function Me.TouchingHorde()
	return GetTime() - Me.horde_touched < 15*60
end

-------------------------------------------------------------------------------
function Me.OnMouseoverUnit()
	Me.HordeTouchTest( "mouseover" )
end

-------------------------------------------------------------------------------
function Me.OnTargetChanged()
	Me.HordeTouchTest( "target" )
end

-------------------------------------------------------------------------------
function Me.UpdateActive()
	
	local ELIXIR_EXPIRED_GRACE_PERIOD = 5*60
	local buff_time = Me.UnitHasElixir( "player" )
	
	if buff_time then
		Me.elixir_active = true
		Me.elixir_time   = buff_time
	else
		Me.elixir_active = false
	end
	
	Me.HordeTouchTest( "target" )
	
	if not Me.active then
		if buff_time and Me.TouchingHorde() then
			Me.SetActive( true )
		end
	else
		if not Me.TouchingHorde() then
			Me.SetActive( false )
		else
			if not buff_time then
				if not Me.grace_period_time then
					Me.grace_period_time = GetTime()
				else
					if GetTime() > Me.grace_period_time + ELIXIR_EXPIRED_GRACE_PERIOD then
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
	
	Me.emote_rerouting = Me.active and buff_time
	
	Me.UpdateIndicators()
	Me.Timer_Start( "update_active", "push", 1.0, Me.UpdateActive )
end

-------------------------------------------------------------------------------
function Me.SetActive( active )
	if not active then
		Me.grace_period_time = nil
	end
	
	Me.active = active
	Me.UpdateIndicators()
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

function Me.GetFullName( unit )
	if not UnitIsPlayer( unit ) then return end
	local name, realm = UnitName( unit )
	if not realm or realm == "" then
		if UnitRealmRelationship( unit ) == LE_REALM_RELATION_SAME then
			return name .. "-" .. Me.realm, Me.realm
		end
		local guid = UnitGUID("player")
		local found, _, _, _, _, _, realm = GetPlayerInfoByGUID(guid)
		if not found then return end
		if not realm or realm == "" then realm = Me.realm end
		realm = realm:gsub("%s*%-*", "")
		return name .. "-" .. realm, realm
	end
	return name .. "-" .. realm, realm
end

-------------------------------------------------------------------------------
-- Helper function to get our current server's name.
-- If `short` is set, it tries to get the club's short name, and falls back to
--  the long name. If it can't figure out what name it is, then it returns
--  (Unknown).
function Me.GetServerName( short )
	if not Me.connected then return "(" .. L.NOT_CONNECTED .. ")" end
	
	local info = Me.GetRelayInfo( Me.club, Me.stream )
	if not info then return L.UNKNOWN_SERVER end
	
	return info.fullname_short
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
	
	-- We also disable using /rp, etc. in chat if they don't have the relay on.
	-- (TODO)
	--Me.UpdateChatTypeHashes()
end

-------------------------------------------------------------------------------
-- Enable or disable the chat relay. This is meant to be used by the user 
--                      through the UI, with message printing and everything.
function Me.EnableRelay( enabled )
	if not enabled then
		Me.EnableRelayDelayed( false )
		Me.Timer_Cancel( "enable_relay_delay" )
	else
		Me.Timer_Start( "enable_relay_delay", "push", 0.3,
	                                           Me.EnableRelayDelayed, enabled )
	end
end

-------------------------------------------------------------------------------
function Me.EnableRelayDelayed( enabled )
	-- Good APIs should always have little checks like this so you don't have
	--                                        to do it in the outside code.
	if not Me.connected then return end
	if enabled then
		Me.relay_active_time = GetTime()
		Me.relay_idle = false
	end
	if (not Me.relay_on) == (not enabled) then return end
	
	Me.relay_on = enabled
	Me.ResetRelayIdle()
	-- We also save this to the database, so we can automatically enable the 
	--  relay so long as our other constraints for this are met (like how we
	--          only do that if they've logged for less than three minutes).
	Me.db.char.relay_on = enabled
	Me.ConnectionChanged()
	
	if Me.relay_on then
		Me.Print( L.RELAY_NOTICE )
		Me.protocol_user_short = nil
		
		-- 7/24/18 We only want to send HENLO once per connection. The HENLO
		--  is for getting the states of everyone, and so long as the user 
		--  stays connected, they will be up to date with everyone's states.
		-- HENLO causes everyone to send a message, so it needs to be sparse.
		if not Me.henlo_sent then
			Me.henlo_sent = true
			Me.SendHenlo()
		end
		
		-- Vernum we can send every time the relay turns on.
		Me.TRP_OnRelayOn()
	else
		-- Nice and verbose.
		Me.Print( L.RELAY_DISABLED )
		Me.showed_relay_off_warning = nil
	end
end

-------------------------------------------------------------------------------
-- Henlo is the greeting message when a player connects to a relay. It's only
--  sent when the relay is activated, and otherwise the player can listen
--  silently and their presence will only be known if they activate the relay
--  or use /rp chat.
function Me.SendHenlo()
	Me.DebugLog( "Sending HENLO." )
	
	local crossrp_version = GetAddOnMetadata( "CrossRP", "Version" )
	local profile_addon = "NONE"
	
	if TRP3_API then
		profile_addon = "TotalRP3/" .. GetAddOnMetadata( "totalRP3", "Version" )
	else
		if Me.msp_addon then
			-- For some dumb reason we use ; instead of / in the msp_addon
			--  string.
			profile_addon = Me.msp_addon:gsub( ";", "/" )
		end
	end
	
	Me.SendPacket( "HENLO", nil, crossrp_version, profile_addon )
end

-------------------------------------------------------------------------------
-- This is set when the player doesn't receive a translated message for a
--  while, meaning that no Horde are nearby (or they're just being quiet). As
--  soon as a translated message is received, the idle state is cancelled. It's
--  to cut down on server load when the relay isn't actually being used. We
--  might also turn off the relay completely if it stays like that for a
--                                                     prolonged period.
function Me.SetRelayIdle()
	if not Me.relay_idle then
		Me.relay_idle = true
		Me.ConnectionChanged()
	end
end

-------------------------------------------------------------------------------
-- Called when we receive a message that should reset the relay idle state.
--  Right now that is any translated messages with a range parameter within
--  30 yards.
function Me.ResetRelayIdle( manual_click )
	Me.relay_active_time = GetTime()
	if Me.relay_idle then		
		if manual_click then
			Me.DebugLog( "Manual relay reset!" )
			-- If they click it manually, then upgrade the idle time to
			--  +5 minutes!
			Me.extra_relay_idle_time = Me.extra_relay_idle_time + 60*5
		end
		Me.relay_idle = false
		Me.ConnectionChanged()
		Me.TRP_SendVernumIfNeeded()
	end
end

-------------------------------------------------------------------------------
-- Establish server connection.
-- club_id: ID of club.
-- stream_id: ID of stream to connect to.
-- enable_relay: Enable relay as well as connect.
function Me.Connect( club_id, stream_id, enable_relay )

	-- Reset everything.
	Me.Disconnect()
	Me.Timer_Cancel( "auto_connect" )
	Me.name_locks  = {}
	Me.autoconnect_finished = true
	Me.connect_time = GetTime()
	Me.henlo_sent = false
	Me.extra_relay_idle_time = 0
	
	for k,v in pairs( Me.crossrp_users ) do
		v.connected = nil
	end

	-- The club must be a valid Battle.net community.
	local club_info = C_Club.GetClubInfo( club_id )
	if not club_info then return end
	if club_info.clubType ~= Enum.ClubType.BattleNet then return end
	
	local relay = Me.GetRelayInfo( club_id, stream_id )
	if not relay then return end
	
	-- A funny thing to note is that unlike traditional applications
	--  which connect to servers, this is instant. There's no initial
	--  handshake or anything. Once you flip the switch on, you're
	--  then processing incoming data.
	Me.connected  = true
	Me.club       = relay.club
	Me.stream     = relay.stream
	
	-- Relays have a flag for war mode, and if it's not present, then the
	--  relay should not be allowed to transfer/receive translations when
	--  the player has war mode on.
	do
		local si = C_Club.GetStreamInfo( club_id, stream_id )
		if si.subject:lower():find( "[warmode]" ) then
			Private.warmode_relay = true
		end
	end
	
	-- We need to save the club name for the disconnect message.
	--  Otherwise, we won't know what it is if we get kicked from the
	--  server.
	Me.club_name  = relay.fullname
	-- This is for auto-connecting on the next login or reload.
	Me.db.char.connected_club   = relay.club
	Me.db.char.connected_stream = relay.stream
	
	Me.showed_relay_off_warning = nil
	
	-- This is a bit of an iffy part. Focusing a stream is for when
	--  the communities panel navigates to one of the streams, and
	--  the API documentation states that you can only have one
	--  focused at a time. But, as far as I know, this is the only
	--                                  way to subscribe to a stream.
	C_Club.FocusStream( Me.club, Me.stream )
	C_Club.UnfocusStream( Me.club, Me.stream )
	-- 1.4.2: Calling Unfocus right after now to try and avoid stalling the
	--  communities panel. Before, sometimes you couldn't subscribe to any
	--  new channels, and I'm assuming this was the reason.
	
	Me.PrintL( "CONNECTED_MESSAGE", Me.club_name )
	
	Me.ConnectionChanged()
	Me.StartConnectionUpdates()
	
	Me.TRP_OnConnected()
	
	-- `enable_relay` is set either when the user presses a connect
	--  button manually, or when they log in within the grace
	--  period. Otherwise, we don't want to do this automatically to
	--                              protect privacy and server load.
	Me.EnableRelay( enable_relay )
	
	Me.Map_ResetPlayers()
end

-------------------------------------------------------------------------------
-- Disconnect from the current server. `silent` will suppress the chat message
--                                  for system things.
function Me.Disconnect( silent )
	if Me.connected then
		-- We don't want to prompt people to rejoin a club they just left.
		Me.club_connect_prompted[Me.club .. "-" .. Me.stream] = true
		
		-- We do, however, want to show them alternatives again...
		Me.club_connect_prompt_shown      = false
		
		Me.connected                = false
		Me.relay_on                 = false
		Me.db.char.connected_club   = nil
		Me.db.char.connnectd_stream = nil
		Me.db.char.relay_on         = nil
		
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
function Me.OnClubStreamUnsubscribed( club, stream )
	if Me.connected and Me.club == club and Me.stream == stream then
		-- Something made us unsubscribed. Subscribe again!
		
		C_Club.FocusStream( club, stream )
		C_Club.UnfocusStream( club, stream )
	end
end

-------------------------------------------------------------------------------
function Me.OnClubsChanged()
	Me.VerifyConnection()
	
	-- Clean and mute relay servers.
	Me.CleanRelayMarkers()
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
	
	local relay = Me.GetRelayInfo( Me.club, Me.stream )
	if not relay then
		-- Either our relay channel was deleted, or we otherwise can't access
		--  it.
		Me.Disconnect()
		return
	end
	
	Me.club_name = relay.fullname
	Me.ConnectionChanged()
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
	
	if language == HordeLanguage() then
		Me.horde_touched = GetTime()
	end
end

-------------------------------------------------------------------------------
-- Prints a chat message to the chat boxes, as well as forwards it to addons
--  like Listener and WIM (via LibChatHandler).
-- event_type: SAY, EMOTE... Can also be our custom types "RP", "RP2" etc.
-- msg:       Message text.
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
	
	-- Check our filters too (set in the minimap menu). If any of them are
	--  unset, then we skip passing it to the chatbox, but we can still pass
	--                       it to Listener, which has its own chat filters.
	--local show_in_chatboxes = true
	--if is_rp_type and not Me.db.global["show_"..event_type:lower()] then
	--	show_in_chatboxes = false
	--end
	
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
			-- I feel like we /might/ be missing another check here. TODO
			--  do some more investigating on how the chat boxes filter
			--  events.
			local show = false
			if rptype then
				if rpchat_windows[i] and rpchat_windows[i]:find( rptype ) then
					show = true
				end
				--[[for k, v in pairs( frame.channelList ) do
					if v:lower() == "crossrp" then
						show = true
						break
					end
				end]]
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
-- Returns true if the relay that we're connected to allows war mode.
--
function Private.WarModeRelayAllowed()
	-- This limitation is bypassed for now, as it's not really an issue yet.
	-- If/when it does become an issue, we already have the implementation
	--  ready to block players from abusing it.
	if true then return true end
	
	if C_PvP.IsWarModeActive() then
		if C_PvP.CanToggleWarMode() then
			return true
		end
		
		if not Private.warmode_relay then
			return false
		end
	end
	
	return true
end

-------------------------------------------------------------------------------
-- Called when we receive a public chat packet, a "translation". We're going 
--  to receive these from both factions, from whoever is connected to the 
--                    relay. We're only interested in the ones from Horde.
function Me.ProcessPacketPublicChat( user, command, msg, args )
	
	if user.horde and not Private.WarModeRelayAllowed() then
		-- War mode is enabled and horde communication is disabled.
		return
	end
	if user.self then
		-- Not sure if this is actually a good idea. While it might make a 
		--  cleaner relay stream, this is basically sending another message
		--  to the server, doubling up the required messages to say something
		--  in the relay.
--		local info, club, stream = C_Club.GetInfoFromLastCommunityChatLine()
--		if info.author.isSelf then
--			-- This should always pass, but maybe not?
--			C_Club.DestroyMessage( club, stream, info.messageId )
--		end
	end
	if user.self or not msg then return end
	-- Args for this packet are: COMMAND, CONTINENT, X, Y
	-- X, Y are packed using our special function.
	local continent, chat_x, chat_y = 
	                          Me.ParseLocationArgs( args[2], args[3], args[4] )
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
	
	if user.horde and PointWithinRange( continent, chat_x, 
	                                   chat_y, RELAY_IDLE_RESET_RANGE ) then
		Me.ResetRelayIdle()
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

--Me.ProcessPacket.SAY   = Me.ProcessPacketPublicChat
--Me.ProcessPacket.EMOTE = Me.ProcessPacketPublicChat
--Me.ProcessPacket.YELL  = Me.ProcessPacketPublicChat

-------------------------------------------------------------------------------
-- Returns the current "role" for someone in the connected club. Defaults
--  to 4/"Member". If user isn't specified then it returns the player's role.
function Me.GetRole( user )
	local role = Enum.ClubRoleIdentifier.Member
	if not Me.connected then return role end
	
	if not user then
		-- Polling the player has a special shortcut. We should have a shortcut
		--  for below later once we actually have a member ID in user tables.
		local member_info = C_Club.GetMemberInfoForSelf( Me.club )
		if member_info then
			return member_info.role or role
		end
		-- Not sure if the above is guaranteed.
		return role
	end
	
	local members = C_Club.GetClubMembers( Me.club )
	if not members then return role end
	
	-- `members` is a list of member IDs
	for k, index in pairs( members ) do
		local info = C_Club.GetMemberInfo( Me.club, index )
		
		if info.bnetAccountId == user.bnet then
			role = info.role
			break
		end
	end
	return role
end

-------------------------------------------------------------------------------
-- Returns true if we're a moderator or higher for the club.
--
function Me.IsModForClub( club )
	local member_info = C_Club.GetMemberInfoForSelf( club )
	if member_info then
		return member_info.role <= Enum.ClubRoleIdentifier.Moderator
	end
	return false
end

-------------------------------------------------------------------------------
-- Trims whitespace from start and end of string.
--
local function TrimString( value )
	return value:match( "^%s*(.-)%s*$" )
end

-------------------------------------------------------------------------------
-- Returns true if the stream is a relay channel we can connect to.
-- 8/24/18 - we can connect to moderator only channels now.
--
function Me.IsRelayStream( club, stream )
	local si = C_Club.GetStreamInfo( club, stream )
	if not si then return end
	
	if si.leadersAndModeratorsOnly and not Me.IsModForClub( club ) then 
		return
	end
	
	local relay_name = si.name:match( Me.RELAY_NAME_PATTERN )
	if not relay_name then return end
	return relay_name, si
end

-------------------------------------------------------------------------------
-- Returns the number of relay channels in a club.
--
function Me.GetNumRelays( club )
	local count = 0
	for _, stream in pairs( C_Club.GetStreams( club )) do
		if Me.IsRelayStream( club, stream.streamId ) then
			count = count + 1
		end
	end
	return count
end

-------------------------------------------------------------------------------
-- Parses the stream description for any tags that are associated with a relay
--  stream.
function Me.GetRelayInfo( club, stream )
	local relay_name, si = Me.IsRelayStream( club, stream )
	if not relay_name then return end
	local ci = C_Club.GetClubInfo( club )
	local info = {
		club     = club;
		stream   = stream;
		clubinfo = ci;
		channel  = relay_name;
		name     = relay_name;
		fullname       = ci.name;
		fullname_short = ci.shortName;
	}
	
	if not ci.name then return end -- Something is wrong...
	if not ci.shortName or ci.shortName == "" then 
		info.fullname_short = ci.name
	end
	
	local num_relays = Me.GetNumRelays( club )
	if num_relays == 1 then
		-- If the community only has one relay stream, then the name defaults
		--  to the parent club name.
		info.name = nil
	end
	
	for line in si.subject:gmatch( "[^\n]+" ) do
		local tag, value = line:match( "%[([^%]]+)%]([^%[]*)" )
		if tag then
			tag = tag:lower()
			if tag == "mute" then
				-- The "mute" tag makes it so that normal members cannot type 
				--  in /rp, reserving it for moderators only.
				info.muted = true
			elseif tag == "name" then
				-- The "name" tag sets a name for a relay stream. By default
				--  it just is the name of the channel minus the prefix ##.
				-- If there's only one channel, the default name is nothing,
				--  and it just uses the club's name for everything.
				value = TrimString( value )
				if value ~= "" then
					info.name = value
				end
			elseif tag == "autosub" then
				-- "autosub" is a disabled feature, it was for automatically
				--  subscribing to the club channel, used only for early
				--  deployment. Not used anymore.
				info.autosub = true
			elseif tag == "warmode" then
				-- "warmode" is a tag that allows public translations in war
				--  mode; otherwise that's disabled.
				info.warmode = true
			end
		end
	end
	
	if num_relays > 1 then
		info.fullname = info.fullname .. ": " .. info.name
		info.fullname_short = info.fullname_short .. ": " .. info.name
	end

	return info
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
		Me.Connect( StaticPopupDialogs.CROSSRP_CONNECT.server, 
		                      StaticPopupDialogs.CROSSRP_CONNECT.stream, true )
	end;
}

-------------------------------------------------------------------------------
function Me.ShowConnectPromptIfNearby( user, map, x, y )
	-- 7/25/18 Removed this functionality. This is not compatible with our
	--  current principles of minimizing server load. It would be better if
	--  they could just connect without turning on the relay, but figuring out
	--  an intuitive way to present that is something for the future.
--[[
	if not map then return end
	if PointWithinRange( map, x, y, 500 ) then
		if Me.connected or user.connected then return end
		
		-- The user might want to do something about this already.
		if not Me.autoconnect_finished 
		                           and GetTime() - Me.startup_time < 10.0 then
			-- Give autoconnect some time to work. This will trigger often when
			--  /reloading in a crowded area and messages are queued up when
			--  the UI is loading.
			return 
		end
		
		local info = Me.GetRelayInfo( user.club, user.stream )
		if not info then return end
		
		local prompt_key = user.club .. "-" .. user.stream
		if not Me.club_connect_prompted[ prompt_key ] 
		                              and not Me.club_connect_prompt_shown then
			Me.club_connect_prompted[ prompt_key ] = true
			Me.club_connect_prompt_shown = true
			StaticPopupDialogs.CROSSRP_CONNECT.text 
			                              = L( "CONNECT_POPUP", info.fullname )
			StaticPopupDialogs.CROSSRP_CONNECT.server = user.club
			StaticPopupDialogs.CROSSRP_CONNECT.stream = user.stream
			StaticPopup_Show( "CROSSRP_CONNECT" )
		end
	end]]
end


--for i = 1,9 do
--	Me.ProcessPacket["RP"..i] = ProcessRPxPacket
--end
--Me.ProcessPacket["RPW"] = ProcessRPxPacket

-------------------------------------------------------------------------------
-- HENLO is the packet that people send as soon as they enable their relay.
--[[
function Me.ProcessPacket.HENLO( user, command, msg )
	Me.DebugLog( "Henlo from %s (%s)", user.name, user.faction )
	
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
	-- (This feature is currently not used)
	Me.protocol_user_short = nil
end]]

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
function Me.ChatFilter_CommunitiesChannel( self, event, text, sender,
              language_name, channel, _, _, _, _, 
	          channel_basename, _, _, _, bn_sender_id, is_mobile, is_subtitle )
	
	if channel_basename ~= "" then channel = channel_basename end
	local club, stream = channel:match( ":(%d+):(%d+)$" )
	club   = tonumber(club)
	stream = tonumber(stream)
	
	if Me.IsRelayStream( club, stream ) then return true end
end

-------------------------------------------------------------------------------
-- A simple event handler to mark any relay channel as read. i.e. hide the
--  "new messages" blip. Normal users can't even open the channel in the 
--  communities panel.
function Me.OnStreamViewMarkerUpdated( event, club, stream, last_read_time )
	if last_read_time then
		
		Me.DebugLog2( "Stream marker updated." )
		local stream_info = C_Club.GetStreamInfo( club, stream )
		if not stream_info then return end
		if stream_info.name == Me.RELAY_CHANNEL then
			-- We're not doing this anymore in favor of just muting the
			--  channels. Muting them doesn't require this interaction with the
			--  server every single time a message is received.
			
			--C_Club.AdvanceStreamViewMarker( club, stream )
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
-- Sort of a temporary workaround. Strip any special codes from a message so
--  that it transfers properly.
--
function Me.StripChatMessage( msg )
	msg = msg:gsub( "|c%x%x%x%x%x%x%x%x", "" )
	msg = msg:gsub( "|r", "" )
	msg = msg:gsub( "|H.-|h(.-)|h", "%1" )
	
	local target_name = UnitName( "target" ) or TARGET_TOKEN_NOT_FOUND
	local focus_name = UnitName( "focus" ) or FOCUS_TOKEN_NOT_FOUND
	msg = msg:gsub( "%%t", target_name )
	msg = msg:gsub( "%%f", focus_name )
	return msg
end

-------------------------------------------------------------------------------
-- Gopher Post Queue hook. This is after the message is put out on the
--  line, so we can't modify anyting.
function Me.GopherChatPostQueue( event, msg, type, arg3, target )
	if Me.in_relay then return end
	if not Me.connected or not Me.relay_on then return end
	
	local default_language = (arg3 == nil or arg3 == 1 or arg3 == 7)
	local is_translatable_type = 
	 ((type == "SAY" or type == "YELL") and default_language)
	 or type == "EMOTE"
	
	-- 1, 7 = Orcish, Common
	if (Me.InWorld() and not IsStealthed()) and is_translatable_type then
		
		if Me.relay_idle and (type == "SAY" or type == "EMOTE") then
			-- Don't send these two types when the relay is idle. They need to
			--  manually turn it back on or wait until they receive a horde
			--  message.
			return
		end
		
		-- Cut out links and stuff because those currently break.
		msg = Me.StripChatMessage( msg )
		
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
	local relay_info = Me.GetRelayInfo( Me.club, Me.stream )
	return relay_info.muted
end

function Me.StartConnectionUpdates()
	Me.Timer_Start( "connection_update", "ignore", 5.0, Me.OnConnectionUpdate )
end

-------------------------------------------------------------------------------
-- Test if a given unit is a Horde Cross RP user, and then reset the relay
--  idle time.
function Me.UnitRelayResetTest( unit )
	if not Me.connected  
	                 or not UnitExists( unit ) or not UnitIsPlayer( unit ) then
		return
	end
	local username = Me.GetFullName( unit )
	if not username then return end
	local user = Me.crossrp_users[username]
	if user and user.horde and IsItemInRange( 18904, unit ) then
		Me.DebugLog( "Resetting relay from touching Horde." )
		Me.ResetRelayIdle()
		return true
	end
end

-------------------------------------------------------------------------------
-- Function that's called periodically to update some connection info.
function Me.OnConnectionUpdate()
	if not Me.connected then return end
	Me.Timer_Start( "connection_update", "push", 5.0, Me.OnConnectionUpdate )
	
	if Me.relay_on then
		-- We have the idle timeout based on how much traffic the server is
		--  experiencing. The relay going idle can be annoying for some people,
		--  and it's not super necessary if the server isn't even generating
		--  a lot of traffic.
		local traffic = Me.GetTrafficSmooth()
		-- 50 BP/S  = 45 minutes timeout for idle mode
		-- 400 BP/S = 10 minutes timeout for idle mode
		local a = ((traffic - 50) / (400 - 50)) -- 50–400 bytes
		a = math.max( a, 0 )
		a = math.min( a, 1 )
		a = 1-a
		a = 10 + (45-10) * a -- 10–45 minutes
		local idle_timeout = (a * 60) + Me.extra_relay_idle_time
		Me.debug_idle_timeout = idle_timeout
		
		-- Mainly just the relay idle thing.
		if GetTime() > Me.relay_active_time + idle_timeout then
			Me.SetRelayIdle()
		end
		
		Me.UnitRelayResetTest( "mouseover" )
		Me.UnitRelayResetTest( "target" )
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
-- Enables or disables listening to an RP channel type. `index` may be 1-9 or
--                                         'W'. `enable` turns it on or off.
function Me.ListenToChannel( index, enable )
	local key = "RP" .. index
	Me.db.global["show_" .. key:lower()] = enable
	
	-- We also disable the chatbox from accessing it.
	Me.UpdateChatTypeHashes()
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
	local loaded = Me.ButcherElephant -- elephant.lua
	           and Me.ShowMOTD        -- motd.lua
			   and Me.ElixirNotice    -- elixirnotice.lua
			   and Me.RPChat          -- rpchat.lua
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
	
	if select( "#", ... ) > 0 then
		text = text:format(...)
	end
	print( "|cFF0099FF[CRP]|r", text )
end

-------------------------------------------------------------------------------
-- Alternate version that doesn't use string format, but rather just passes
--                                                   all arguments to `print`.
function Me.DebugLog2( ... )
	if not Me.DEBUG_MODE then return end
	
	print( "|cFF0099FF[CRP]|r", ... )
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
	Me.RPChat.Start('hi')
	
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