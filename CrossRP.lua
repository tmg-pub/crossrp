-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
-------------------------------------------------------------------------------

local AddonName, Me = ...
local L = Me.Locale

CrossRP = Me

-- Embed AceAddon.
LibStub("AceAddon-3.0"):NewAddon( Me, AddonName, "AceEvent-3.0", "AceHook-3.0" )

Me.connected = false
Me.club      = nil
Me.stream    = nil

Me.name_locks = {}

Me.chat_pending = {}

Me.ProcessPacket = {}
Me.DataHandlers = {}

Me.player_guids = {}
Me.bnet_whisper_names = {} -- [bnetAccountId] = ingame name

-- seconds before we reset the buffer waiting for translations
local CHAT_TRANSLATION_TIMEOUT = 5
local CHAT_HEAR_RANGE = 25.0
local PROTOCOL_VERSION = 1

-------------------------------------------------------------------------------
local function MyName()
	local name, realm = UnitFullName( "player" )
	name = name .. "-" .. realm
	return name
end

-------------------------------------------------------------------------------
local function FactionTag()
	local faction = UnitFactionGroup( "player" )
	return faction == "Alliance" and "A" or "H"
end

-------------------------------------------------------------------------------
local function OppositeLanguage()
	return UnitFactionGroup( "player" ) == "Alliance" and "Orcish" or "Common"
end

-------------------------------------------------------------------------------
-- Returns true if in the open world.
--
local GARRISON_MAPS = {
	[1152] = true;
	[1330] = true;
	[1153] = true;
	[1154] = true;
	[1158] = true;
	[1331] = true;
	[1159] = true;
	[1160] = true;
}
function Me.InWorld()
	if IsInInstance() then return false end
	local mapID = select( 8, GetInstanceInfo() )
	if GARRISON_MAPS[mapID] then return false end
	return true
end

-------------------------------------------------------------------------------
local function Hexc( hex )
	return 
		tonumber( "0x"..hex:sub(1,2) )/255,
		tonumber( "0x"..hex:sub(3,4) )/255,
		tonumber( "0x"..hex:sub(5,6) )/255
end

-------------------------------------------------------------------------------
function Me:OnEnable()
	Me.CreateDB()
	Me.user_prefix = string.format( "1%s %s", FactionTag(), MyName() )
	local my_name, my_realm = UnitFullName( "player" )
	Me.realm = my_realm
	Me.fullname = my_name .. "-" .. my_realm
	
	Me:RegisterEvent( "CHAT_MSG_COMMUNITIES_CHANNEL", Me.OnChatMsgCommunitiesChannel )
	Me:RegisterEvent( "BN_CHAT_MSG_ADDON", Me.OnBnChatMsgAddon )
	Me:RegisterEvent( "CHAT_MSG_BN_WHISPER", Me.OnChatMsgBnWhisper )
	Me:RegisterEvent( "CHAT_MSG_BN_WHISPER_INFORM", Me.OnChatMsgBnWhisper )
	
	Me:RegisterEvent( "CHAT_MSG_SAY",   Me.OnChatMsg )
	Me:RegisterEvent( "CHAT_MSG_EMOTE", Me.OnChatMsg )
	Me:RegisterEvent( "CHAT_MSG_YELL",  Me.OnChatMsg )
	
	Me:RegisterEvent( "ADDON_LOADED",  Me.OnAddonLoaded )
	
	Me:RegisterEvent( "CLUB_STREAM_REMOVED", function()
		Me.VerifyConnection()
	end)
	Me:RegisterEvent( "CLUB_REMOVED", function()
		Me.VerifyConnection()
	end)
	
	Me:RegisterEvent( "STREAM_VIEW_MARKER_UPDATED", Me.OnStreamViewMarkerUpdated )
	
	local function say_filter( _, _, msg, sender, language )
		if Me.connected and language == OppositeLanguage() then
			return true
		end
	end
	
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_SAY", say_filter )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_YELL", say_filter )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_EMOTE", 
		function( _, _, msg, sender, language )
			if Me.connected and msg == CHAT_EMOTE_UNKNOWN or msg == CHAT_SAY_UNKNOWN then
				return true
			end
		end)
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_BN_WHISPER", Me.ChatFilter_BNetWhisper )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_BN_WHISPER_INFORM", Me.ChatFilter_BNetWhisper )
	
	EmoteSplitter.AddChatHook( "START", Me.EmoteSplitterStart )
	EmoteSplitter.AddChatHook( "QUEUE", Me.EmoteSplitterQueue )
	EmoteSplitter.AddChatHook( "POSTQUEUE", Me.EmoteSplitterPostQueue )
	for i = 1,9 do
		EmoteSplitter.SetChunkSizeOverride( "RP" .. i, 400 )
	end
	EmoteSplitter.SetChunkSizeOverride( "RPW", 400 )
	
	C_ChatInfo.RegisterAddonMessagePrefix( "RPL" )
	Me:RegisterEvent( "CHAT_MSG_ADDON", Me.OnChatMsgAddon )
	
	Me.indicator = CreateFrame("Frame",nil,UIParent)
	Me.indicator:SetFrameStrata("DIALOG")
	Me.indicator:SetSize( 16,16 )
	Me.indicator:SetPoint( "TOP" )
	Me.indicator:Hide()
	Me.indicator:SetScale(1)
	Me.indicator.text = Me.indicator:CreateFontString(nil,"OVERLAY")
	Me.indicator.text:SetFont( "Fonts\\FRIZQT__.ttf", 12 )--, "OUTLINE" ) 
	Me.indicator.text:SetPoint( "TOP", 0, -4 )
	Me.indicator.text:SetText( "Connected to TEST." )
	Me.indicator.text:SetShadowOffset( 1,-1)
	Me.indicator.text:SetShadowColor(0.0,0.0,0.0,0.3 )
	Me.indicator.bg = Me.indicator:CreateTexture(nil,"ARTWORK")
	Me.indicator.bg:SetPoint( "TOPLEFT", Me.indicator.text, "TOPLEFT", -12, 4 )
	Me.indicator.bg:SetPoint( "BOTTOMRIGHT", Me.indicator.text, "BOTTOMRIGHT", 12, -4 )
	local r,g,b = Hexc "22CC22"
	Me.indicator.bg:SetColorTexture( r,g,b )
	Me.indicator.bg2 = Me.indicator:CreateTexture( nil,"BACKGROUND")
	Me.indicator.bg2:SetPoint( "TOPLEFT", Me.indicator.bg, "BOTTOMLEFT", 0, 3 )
	Me.indicator.bg2:SetPoint( "BOTTOMRIGHT", Me.indicator.bg, "BOTTOMRIGHT", 0, -3 )
	Me.indicator.bg2:SetColorTexture( r * 0.7, g * 0.7, b * 0.7 )
	Me.indicator.text:SetShadowColor(r * 0.7, g * 0.7, b * 0.7,1 )
	Me.indicator.thumb = CreateFrame( "Button", "CrossRPIndicatorThumb", Me.indicator )
	Me.indicator.thumb:SetPoint( "TOPLEFT", Me.indicator.bg, "TOPLEFT" )
	Me.indicator.thumb:SetPoint( "BOTTOMRIGHT", Me.indicator.bg, "BOTTOMRIGHT", 0, -3 )
	Me.indicator.thumb:EnableMouse(true)
	Me.indicator.thumb:RegisterForClicks( "LeftButtonUp", "RightButtonUp" )
	Me.indicator.thumb:SetScript( "OnClick", Me.OnMinimapButtonClick )
	Me.indicator.thumb:SetScript( "OnEnter", Me.OnMinimapButtonEnter )
	Me.indicator.thumb:SetScript( "OnLeave", Me.OnMinimapButtonLeave )
	
	hooksecurefunc( "UnitPopup_ShowMenu", Me.OnUnitPopup_ShowMenu )
	Me.FuckUpCommunitiesFrame()
	
	Me.TRP_Init()
	Me.SetupMinimapButton()
	Me.ApplyOptions()
	
	C_Timer.After( 3, function()
		-- Clean up shit.
		
		local servers = Me.GetServerList()
		for k,v in pairs( servers ) do
			C_Club.AdvanceStreamViewMarker( v.club, v.stream )
		end
	end)
end

-- Does what it says on the tin.
function Me.FuckUpCommunitiesFrame()
	if not CommunitiesFrame then return end

	local function LockRelay()
		if Me.CanEditMute() then return end
		
		for i = 1,99 do
			local button = _G["DropDownList1Button"..i]
			if button and button:IsShown() then
				if button:GetText():match( "^#RELAY#" ) then
					button:SetEnabled(false)
					break
				end
			else
				break
			end
		end
	end
	
	hooksecurefunc( CommunitiesFrame.StreamDropDownMenu, "initialize", LockRelay )
end

-------------------------------------------------------------------------------
function Me.OnAddonLoaded( event, name )
	if name == "Blizzard_Communities" then
		Me.FuckUpCommunitiesFrame()
	end
end

-------------------------------------------------------------------------------
function Me.GetServerList()
	local servers = {}
	for _,club in pairs( C_Club.GetSubscribedClubs() ) do
		if club.clubType == Enum.ClubType.BattleNet then
			for _, stream in pairs( C_Club.GetStreams( club.clubId )) do
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
	table.sort( servers, function(a,b) return a.name < b.name end )
	return servers
	
end

-------------------------------------------------------------------------------
function Me.GetFullName( unit )
	if not UnitIsVisible( unit ) then return end
	local name, realm = UnitName( unit )
	realm = realm or Me.realm
	realm = realm:gsub(" ", "")
	return name .. "-" .. realm, realm
end

-------------------------------------------------------------------------------
-- Protocol
-------------------------------------------------------------------------------
local TRANSFER_DELAY      = 0.5
local TRANSFER_SOFT_LIMIT = 1500
local TRANSFER_HARD_LIMIT = 2500
Me.packets    = {}
Me.sending    = false
Me.send_timer = nil

local function QueuePacket( command, data, ... )
	local slug = ""
	if select("#",...) > 0 then
		slug = ":" .. table.concat( { ... }, ":" )
	end
	if data then
		table.insert( Me.packets, string.format( "%X", #data ) .. ":" .. command .. slug .. " " .. data )
	else
		table.insert( Me.packets, command )
	end
end

-------------------------------------------------------------------------------
function Me.SendPacket( command, data, ... )
	QueuePacket( command, data, ... )
	Me.Timer_Start( "send", "ignore", TRANSFER_DELAY, Me.DoSend )
end

-------------------------------------------------------------------------------
function Me.SendPacketInstant( command, data, ... )
	QueuePacket( command, data, ... )
	Me.Timer_Cancel( "send" )
	Me.DoSend( true )
end

-------------------------------------------------------------------------------
function Me.DoSend( nowait )
	
	if #Me.packets == 0 then
		return
	end
	
	if not Me.connected then
		Me.packets = {}
		return
	end
	
	local data = Me.user_prefix
	while #Me.packets > 0 do
		local p = Me.packets[1]
		if #data + #p + 1 < TRANSFER_HARD_LIMIT then
			data = data .. " " .. p
			table.remove( Me.packets, 1 )
		end
		if #data > TRANSFER_SOFT_LIMIT then
			break
		end
	end
	
	EmoteSplitter.Suppress()
	C_Club.SendMessage( Me.club, Me.stream, data )
	
	if nowait then
		Me.DoSend()
		return
	end
	
	if #Me.packets > 0 then
		-- More to send
		Me.Timer_Start( "send", "ignore", TRANSFER_DELAY, Me.DoSend )
	end
end

-------------------------------------------------------------------------------
function Me.Connect( club_id )
	Me.connected = false
	Me.name_locks = {}
	
	local club_info = C_Club.GetClubInfo( club_id )
	if not club_info then return end
	if club_info.clubType ~= Enum.ClubType.BattleNet then return end
	
	for _, stream in pairs( C_Club.GetStreams( club_id )) do
		if stream.name == "#RELAY#" and not stream.leadersAndModeratorsOnly then
			Me.connected = true
			Me.club   = club_id
			Me.stream = stream.streamId
			Me.club_name = club_info.name
			C_Club.FocusStream( Me.club, Me.stream )
			
			Me.SendPacket( "HENLO" )
			Me.TRP_OnConnected()
			
			Me.PrintL( "CONNECTED_MESSAGE", club_info.name )
			
			Me.UpdateChatTypeHashes()
			Me.ldb.iconR = 1;
			Me.ldb.iconG = 1;
			Me.ldb.iconB = 1;
			Me.indicator.text:SetText( L( "INDICATOR_CONNECTED", Me.club_name ))
			if Me.db.global.indicator then
				Me.indicator:Show()
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.Disconnect()
	if Me.connected then
		Me.connected = false
		Me.indicator:Hide()
		Me.PrintL( "DISCONNECTED_FROM_SERVER", Me.club_name )
		Me.UpdateChatTypeHashes()
		Me.ldb.iconR = 0.5;
		Me.ldb.iconG = 0.5;
		Me.ldb.iconB = 0.5;
	end
end

-------------------------------------------------------------------------------
function Me.VerifyConnection()
	if not Me.connected then return end
	local club_info = C_Club.GetClubInfo( Me.club )
	if not club_info or club_info.clubType ~= Enum.ClubType.BattleNet then
		Me.Disconnect()
		return
	end
	
	local stream = C_Club.GetStreamInfo( Me.club, Me.stream )
	if not stream then
		Me.Disconnect()
		return
	end
	
	if stream.leadersAndModeratorsOnly then
		Me.Disconnect()
		return
	end
	
end

-------------------------------------------------------------------------------
function Me.OnChatMsgAddon( prefix, msg, dist, sender )
	if prefix == "RPL" then
	
		-- TODO this needs more work.
		-- the sender should be checked if they're in the same community
		-- we don't want to verify battle tag for people outside
		-- its a privacy issue
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
function Me.OnChatMsg( event, text, sender, language, _,_,_,_,_,_,_,lineID,guid )
	if not Me.connected then return end
	
	if not sender:find( "-" ) then
		sender = sender .. "-" .. GetNormalizedRealmName()
	end
	
	if guid then
		Me.player_guids[sender] = guid
	end
	
	event = event:sub( 10 )
	if event == "SAY" or event == "EMOTE" or event == "YELL" then
		if (event == "SAY" or event == "YELL") and language ~= OppositeLanguage() then return end
		if event == "EMOTE" and text ~= CHAT_EMOTE_UNKNOWN and text ~= CHAT_SAY_UNKNOWN then return end
		
		if event == "SAY" and text ~= "" then
			Me.Bubbles_Add( sender, text )
		end
		
		local orcish
		if event == "SAY" and text ~= "" then orcish = text end
		
		-- CHAT_SAY_UNKNOWN is an EMOTE that spawns from /say when you type in something like "reeeeeeeeeeeeeee"
		if event == "EMOTE" and text == CHAT_SAY_UNKNOWN then
			event = "SAY"
			text = ""
		end
		
		if not Me.chat_pending[sender] then
			Me.chat_pending[sender] = {
				guid = guid;
				waiting = {
					SAY   = {};
					EMOTE = {};
					YELL  = {};
				}
			}
		end
		
		local data = Me.chat_pending[sender]
		table.insert( data.waiting[event], { lineid = lineID, time = GetTime(), orcish = orcish } )
	end
end

-------------------------------------------------------------------------------
Me.bubbles = {}

function Me.Bubbles_Add( user, text )
	if not Me.db.global.bubbles then return end
	Me.bubbles[user] = {
		time    = GetTime();
		orcish  = text;
		frame   = nil;
		expires = 2.0 + (#text / 255) * 11.0
	}
	
	C_Timer.After( 0.01, function()
		local frame, fontstr = Me.Bubbles_FindFromText( text )
		fontstr:SetTextColor(1,1,1,0.3)
		if frame then
			C_Timer.After( 0.1, function() frame:Hide() end )
			frame:Hide()
		end
	end)
end

-------------------------------------------------------------------------------
function Me.Bubbles_FindFromText( text, post )
	for _, v in pairs( C_ChatBubbles.GetAllChatBubbles() ) do
		if not v:IsForbidden() then
			for i = 1, v:GetNumRegions() do
				local frame = v
				local v = select( i, v:GetRegions() )
				if v:GetObjectType() == "FontString" then
					local fontstring = v
					if fontstring:GetText() == text then
						return frame, fontstring
					end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.Bubbles_Translate( orcish, common )
	if not Me.db.global.bubbles then return end
	local bubble, fontstring = Me.Bubbles_FindFromText( orcish, true )
	if not bubble then return end
	bubble:Show()
	fontstring:SetText( common )
	fontstring:SetTextColor( 1,1,1,1 )
	fontstring:SetWidth( math.min( (fontstring:GetStringWidth()), 300 ))
end

-------------------------------------------------------------------------------
function Me.SimulateChatMessage( event_type, msg, username, language, lineid, guid )
	if username == Me.fullname then
		guid = UnitGUID( "player" )
	else
		guid = guid or Me.player_guids[username]
	end
	lineid = lineid or 0
	
	language = langauge or (GetDefaultLanguage())
	local event_check = event_type
	local is_rp_type = event_type:match( "^RP[1-9]" )
	if is_rp_type then
		event_check = "RAID" 
	elseif event_type == "RPW" then 
		event_check = "RAID_WARNING"
	end
	local show_in_chatboxes = true
	if is_rp_type and not Me.db.global["show_"..event_type:lower()] then
		show_in_chatboxes = false
	end
	
	if show_in_chatboxes then
		for i = 1, NUM_CHAT_WINDOWS do
			local frame = _G["ChatFrame" .. i]
			-- TODO, check if theres anything that we should do to NOT add messages to this frame
			if frame:IsEventRegistered( "CHAT_MSG_" .. event_check ) then
				ChatFrame_MessageEventHandler( frame, "CHAT_MSG_" .. event_type, msg, username, language, "", "", "", 0, 0, "", 0, lineid, guid, 0 )
			end
		end
	end
	
	if ListenerAddon then
		ListenerAddon:OnChatMsg( "CHAT_MSG_" .. event_type, msg, username, language, "", "", "", 0, 0, "", 0, lineid, guid, 0 )
	end
	
	if (not is_rp_type) and event_type ~= "RPW" then -- only pass valid to here
		if LibChatHander_EventHandler then
			local lib = LibStub:GetLibrary("LibChatHandler-1.0")
			if lib.GetDelegatedEventsTable()[event_type] then
				-- teehee
				local event_script = LibChatHander_EventHandler:GetScript( "OnEvent" )
				if event_script then
					event_script( LibChatHander_EventHandler, "CHAT_MSG_" .. event_type, msg, username, language, "", "", "", 0, 0, "", 0, lineid, guid, 0 )
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.ProcessPacketPublicChat( user, command, msg )
	if user.self then return end
	if not user.horde then return end
	if not msg then return end
	local type = command -- special handling here if needed
	-- apply message
	local pending = Me.chat_pending[user.name]
	if pending then
		while pending.waiting[type] and #pending.waiting[type] > 0 
		      and pending.waiting[type][1].time < GetTime() - CHAT_TRANSLATION_TIMEOUT do
			-- discard OLD entries, something went wrong.
			table.remove( pending.waiting[type], 1 )
		end
		if #pending.waiting[type] > 0 then
			local entry = pending.waiting[type][1]
			table.remove( pending.waiting[type], 1 )
			
			if type == "SAY" and entry.orcish then
				Me.Bubbles_Translate( entry.orcish, msg )
			end
			
			Me.SimulateChatMessage( type, msg, user.name, nil, entry.lineid )
		end
	end
end

Me.ProcessPacket.SAY   = Me.ProcessPacketPublicChat
Me.ProcessPacket.EMOTE = Me.ProcessPacketPublicChat
Me.ProcessPacket.YELL  = Me.ProcessPacketPublicChat

-------------------------------------------------------------------------------
function Me.GetRole( user )
	local members = C_Club.GetClubMembers( Me.club )
	local role = 4
	for k,index in pairs(members) do
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

local function ProcessRPXPacket( user, command, msg )
	if not msg then return end
	Me.SimulateChatMessage( command, msg, user.name )
end

for i = 2,9 do
	Me.ProcessPacket["RP"..i] = ProcessRPXPacket
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.RP1( user, command, msg )
	if not msg then return end
	
	local role = Me.GetRole( user )
	if role == 4 and C_Club.GetStreamInfo( Me.club, Me.stream ).subject:lower():find( "#mute" ) then
		-- RP channel is muted
		return
	end
	
	Me.SimulateChatMessage( "RP1", msg, user.name )
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.RPW( user, command, msg )
	if not msg then return end
	
	local role = Me.GetRole( user )
	if role > 2 then return end -- Only leaders can RPW.
	
	Me.SimulateChatMessage( "RPW", msg, user.name )
	msg = ChatFrame_ReplaceIconAndGroupExpressions(msg);
	RaidNotice_AddMessage( RaidWarningFrame, msg, ChatTypeInfo["RPW"] );
	PlaySound( SOUNDKIT.RAID_WARNING );
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.HENLO( user, command, msg )
	if user.self then return end
	
	if user.horde then
		if Me.chat_pending[user.name] then
			Me.chat_pending[user.name].waiting = {
				SAY   = {};
				EMOTE = {};
				YELL  = {};
			}
		end
	end
	
	if user.xrealm or user.horde then
		Me.TRP_SendVernumDelayed()
	end
end

-------------------------------------------------------------------------------
function Me.PacketHandler( user, command, data )
	if not Me.ProcessPacket[command] then return end
	Me.ProcessPacket[command]( user, command, data )
end

-------------------------------------------------------------------------------
function BNetFriendOwnsName( bnet_id, name )
	-- do we really need to iterate over everything?
	for friend = 1, BNGetNumFriends() do
		local accountID, _, _, _, _, _, _, is_online = BNGetFriendInfo( friend )
		if is_online and accountID == bnet_id then
			local num_accounts = BNGetNumFriendGameAccounts( friend )
			for account_index = 1, num_accounts do
				local _, char_name, client, realm,_, faction, _,_,_,_,_,_,_,_,_, game_account_id = BNGetFriendGameAccountInfo( friend, account_index )
				if client == BNET_CLIENT_WOW then
					char_name = char_name .. "-" .. realm:gsub(" ","")
					if char_name == name then return true end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.OnBnChatMsgAddon( event, prefix, text, channel, bnetIDGameAccount )

end

function Me.OnChatMsgBnWhisper( event, text, _,_,_,_,_,_,_,_,_,_,_, bnet_id )
	local sender, text = text:match( "^%[W:([^%-]+%-[^%]]+)%] (.+)" )
	if sender then
		if event == "CHAT_MSG_BN_WHISPER" then
			local prefix = BNetFriendOwnsName( bnet_id, sender ) and "" or (L.WHISPER_UNVERIFIED .. " ")
			Me.SimulateChatMessage( "WHISPER", prefix .. text, sender )
		elseif event == "CHAT_MSG_BN_WHISPER_INFORM" then
			if Me.bnet_whisper_names[bnet_id] then
				Me.SimulateChatMessage( "WHISPER_INFORM", text, Me.bnet_whisper_names[bnet_id] )
			end
		end
	end
end

function Me.ChatFilter_BNetWhisper( self, event, text, _,_,_,_,_,_,_,_,_,_,_, bnet_id )
	local sender, text = text:match( "^%[W:([^%-]+%-[^%]]+)%] (.+)" )
	
	if sender then
		if event == "CHAT_MSG_BN_WHISPER_INFORM" and not Me.bnet_whisper_names[bnet_id] then
			-- we didn't send this or we lost track, so just make it show up normally???
			return
		end
		
		return true
	end
end

function Me.OnStreamViewMarkerUpdated( event, club, stream, last_read_time )
	if last_read_time then
		local stream_info = C_Club.GetStreamInfo( club, stream )
		if stream_info.name == "#RELAY#" then
			C_Club.AdvanceStreamViewMarker( club, stream )
		end
	end
end

-------------------------------------------------------------------------------
function Me.OnChatMsgCommunitiesChannel( event,
	          text, sender, language_name, channel, _, _, _, _, 
	          channel_basename, _, _, _, bn_sender_id, is_mobile, is_subtitle )
	
	if not Me.connected then return end
	if is_mobile or is_subtitle then return end
	if channel_basename ~= "" then channel = channel_basename end
	local club, stream = channel:match( ":(%d+):(%d+)$" )
	if tonumber(club) ~= Me.club or tonumber(stream) ~= Me.stream then return end
	
	
	local version, faction, player, realm, rest = text:match( "^([0-9]+)(.)%S* ([^%-]+)%-([%S]+) (.+)" )

	if not player then
		-- didn't match
		return
	end
	
	if (tonumber(version) or 0) < PROTOCOL_VERSION then
		-- needs update
		return
	end
	
	local user = {
		self    = BNIsSelf( bn_sender_id );
		faction = faction;
		horde   = faction ~= FactionTag();
		xrealm  = realm ~= Me.realm;
		name    = player .. "-" .. realm;
		bnet    = bn_sender_id;
	}
	
	if user.xrealm then
		for _, v in pairs( GetAutoCompleteRealms() ) do
			if v == user.realm then
				-- this is a connected realm.
				user.xrealm = nil
			end
		end
	end
	
	if not user.self and user.name:lower() == Me.fullname:lower() then 
		-- someone else using our name?
		print( "|cffff0000" .. L( "POLICE_POSTING_YOUR_NAME", sender ))
		return
	end
	
	if not Me.name_locks[user.name] then
		Me.name_locks[user.name] = bn_sender_id
	elseif Me.name_locks[user.name] ~= bn_sender_id then
		-- multiple bnet ids using this player - this is something malicious
		-- hopefully we already captured the right person
		print( "|cffff0000" .. L( "POLICE_POSTING_LOCKED_NAME", sender ))
		return
	end
	
	-- message loop
	while #rest > 0 do
		local header = rest:match( "^%S+" )
		if not header then return end
		local command = header
		
		local length
		local parts = {}
		for v in command:gmatch( "[^:]+" ) do
			table.insert( parts, v )
		end
		
		if #parts >= 2 then
			length, command = parts[1], parts[2]
			length = tonumber( length, 16 )
			if not length then return end
		end
		
		local data
		if length and length > 0 then
			data = rest:sub( #header + 2, #header+2 + length-1 )
			if #data < length then
				return
			end
		end
		
		Me.PacketHandler( user, command, data, parts )
		
		-- cut away this message
		rest = rest:sub( #header + 2 + (length or -1) + 1 )
	end
end

-------------------------------------------------------------------------------
-- Clean a name so that it starts with a capital letter.
--
function Me.FixupName( name )

	if name:find( "-" ) then
		name = name:gsub( "^.+%-", string.lower )
	else
		name = name:lower()
	end
	
	-- (utf8 friendly) capitalize first character
	name = name:gsub("^[%z\1-\127\194-\244][\128-\191]*", string.upper)
	return name
end

-------------------------------------------------------------------------------
function Me.HandleOutgoingWhisper( msg, type, arg3, target )
	if msg == "" then return end
	
	if not target:find('-') then
		target = target .. "-" .. Me.realm
	end
	target = target:lower()
	
	for friend = 1, BNGetNumFriends() do
		local accountID, _, _, _, _, _, _, is_online = BNGetFriendInfo( friend )
		if is_online then
			local num_accounts = BNGetNumFriendGameAccounts( friend )
			for account_index = 1, num_accounts do
				
				local _, char_name, client, realm,_, faction, _,_,_,_,_,_,_,_,_, game_account_id = BNGetFriendGameAccountInfo( friend, account_index )
				if client == BNET_CLIENT_WOW then
					char_name = char_name .. "-" .. realm:gsub(" ","")
					
					-- TODO, faction is maybe localized.
					if char_name:lower() == target and UnitFactionGroup("player") ~= faction then
						-- this is a cross-faction whisper!
						
						-- TODO, if the recipient is on 2 wow accounts, both will see this message
						-- and not know who it is to!
						BNSendWhisper( accountID, "[W:" .. Me.fullname .. "] " .. msg )
						Me.bnet_whisper_names[accountID] = char_name
						return false
					end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.EmoteSplitterStart( msg, type, arg3, target )
	if type == "CLUB" and not Me.sending_to_relay then
		local stream_info = C_Club.GetStreamInfo( arg3, target )
		if not stream_info then return end
		local name = stream_info.name
		if not name then return end
		if name == "#RELAY#" then
			-- this is a relay channel
			Me.Print( L.CANNOT_SEND_TO_CHANNEL )
			return false
		end
	end
end

-------------------------------------------------------------------------------
function Me.EmoteSplitterQueue( msg, type, arg3, target )

	if type == "WHISPER" then
		return Me.HandleOutgoingWhisper( msg, type, arg3, target )
	end
	
	if Me.in_relay then return end
	if not Me.connected then return end
	
	local rptype,rpindex = type:match( "^(RP)(.)" )
	
	if rptype then
		if rpindex == "1" then -- "RP"
			if Me.GetRole() == 4 and Me.IsMuted() then
				Me.Print( L.RP_CHANNEL_IS_MUTED )
				return false
			end
			Me.SendPacketInstant( "RP1", msg )
		elseif rpindex:match "[2-9]" then
			Me.SendPacketInstant( "RP" .. rpindex, msg )
			
		elseif rpindex == "W" then
			if Me.GetRole() > 2 then
				Me.Print( L.CANT_POST_RPW )
				return false
			end
			Me.SendPacketInstant( "RPW", msg )
		end
		return false
	end
end

-------------------------------------------------------------------------------
function Me.EmoteSplitterPostQueue( msg, type, arg3, target )
	if Me.in_relay then return end
	if not Me.connected then return end
	-- 1,7 = orcish,common
	if type == "SAY" or type == "EMOTE" or type == "YELL" and (arg3 == 1 or arg3 == 7) then
		if Me.InWorld() then -- ONLY translate these if in the world
			local y,x = UnitPosition( "player" )
			if not y then return end
			x = string.format( "%.1f", x )
			y = string.format( "%.1f", y )
			local mapid = select( 8, GetInstanceInfo() )
			Me.SendPacketInstant( type, msg, mapid, x, y )
		end
	end
end

-------------------------------------------------------------------------------
function Me.CanEditMute()
	if not Me.connected then return end
	local privs = C_Club.GetClubPrivileges( Me.club )
	return privs.canSetStreamSubject
end

-------------------------------------------------------------------------------
function Me.IsMuted()
	return C_Club.GetStreamInfo( Me.club, Me.stream ).subject:lower():find( "#mute" )
end

-------------------------------------------------------------------------------
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
function Me.Print( text, ... )
	if select( "#", ... ) > 0 then
		text = string.format( text, ... )
	end
	text = "|cFF22CC22<"..L.CROSS_RP..">|r |cFFc3f2c3" .. text
	print( text )
end

-------------------------------------------------------------------------------
function Me.PrintL( key, ... )
	local text
	if select( "#", ... ) > 0 then
		text = L( key, ... )
	else
		text = L[key]
	end
	print( "|cFF22CC22<"..L.CROSS_RP..">|r |cFFc3f2c3" .. text )
end

-------------------------------------------------------------------------------
function Me.OnUnitPopup_ShowMenu( menu, which, unit, name, userData )
	if not Me.db.global.whisper_horde then return end
	
	if UIDROPDOWNMENU_MENU_LEVEL == 1 and unit == "target" and unit then
		local is_player = UnitIsPlayer( unit )
		local is_online = UnitIsConnected( unit )
		local add_whisper_button = is_player and (UnitFactionGroup( "player" ) ~= UnitFactionGroup("target")) and is_online
		
		local info
		
		if add_whisper_button then
			UIDropDownMenu_AddSeparator(UIDROPDOWNMENU_MENU_LEVEL);
			info = UIDropDownMenu_CreateInfo();
			info.text = L.CROSS_RP;
			info.isTitle = true;
			info.notCheckable = true;
			UIDropDownMenu_AddButton(info);
		end
		
		if add_whisper_button then
			info = UIDropDownMenu_CreateInfo();
			info.text = L.WHISPER;
			info.notCheckable = true;
			info.func = function()
				local name = UIDROPDOWNMENU_INIT_MENU.name
				local server = UIDROPDOWNMENU_INIT_MENU.server
				if not server then server = GetNormalizedRealmName() end
				ChatFrame_SendTell( name .. "-" .. server, UIDROPDOWNMENU_INIT_MENU.chatFrame )
			end
			info.tooltipTitle     = info.text
			info.tooltipText      = L.WHISPER_TIP;
			info.tooltipOnButton  = true
			UIDropDownMenu_AddButton(info);
		end
	end
end

-------------------------------------------------------------------------------
function Me.ListenToChannel( index, enable )
	local key = "RP" .. index
	Me.db.global["show_" .. key:lower()] = enable
	Me.UpdateChatTypeHashes()
end

-------------------------------------------------------------------------------
function Me.UpdateChatTypeHashes()
	if Me.db.global.show_rpw and Me.connected then
		hash_ChatTypeInfoList["/RPW"] = "RPW"
	else
		hash_ChatTypeInfoList["/RPW"] = nil
	end
	for i = 1, 9 do
		if Me.db.global["show_rp"..i] and Me.connected then
			hash_ChatTypeInfoList["/RP"..i] = "RP"..i
			if i == 1 then
				hash_ChatTypeInfoList["/RP"] = "RP1"
			end
		else
			hash_ChatTypeInfoList["/RP"..i] = nil
			if i == 1 then
				hash_ChatTypeInfoList["/RP"] = nil
			end
		end
	end
	
	-- reset chat boxes that are stickied to channels that are no longer valid
	for i = 1,NUM_CHAT_WINDOWS do
		local editbox = _G["ChatFrame"..i.."EditBox"]
		local chat_type = editbox:GetAttribute( "chatType" )
		if chat_type:match( "^RP." ) and not (Me.db.global["show_"..chat_type:lower()] and Me.connected) then
			editbox:SetAttribute( "chatType", "SAY" )
			if editbox:IsShown() then
				ChatEdit_UpdateHeader(editbox)
			end
		end
	end
end

-------------------------------------------------------------------------------
for i = 1, 9 do
	local key = "RP" .. i
	ChatTypeInfo[key]               = { r = 1, g = 1, b = 1, sticky = 1 }
	hash_ChatTypeInfoList["/"..key] = key
	_G["CHAT_"..key.."_SEND"]       = key..": "
	_G["CHAT_"..key.."_GET"]        = "["..key.."] %s: "
end

ChatTypeInfo["RPW"]           = { r = 1, g = 1, b = 1, sticky = 1 }
hash_ChatTypeInfoList["/RP"]  = "RP1"
hash_ChatTypeInfoList["/RPW"] = "RPW"
CHAT_RP1_SEND                 = "RP: "
CHAT_RP1_GET                  = "[RP] %s: "
CHAT_RPW_SEND                 = L.RP_WARNING .. ": "
CHAT_RPW_GET                  = "["..L.RP_WARNING.."] %s: "

--@debug@
C_Timer.After( 1, function()

	Me.Connect( 32381 )
end)
--@end-debug@