
local AddonName, Me = ...

RPLink = Me

LibStub("AceAddon-3.0"):NewAddon( Me, AddonName, "AceEvent-3.0" )

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
function Me:OnEnable()
	Me.CreateDB()
	Me.user_prefix = string.format( "##%s:%s:%s//", FactionTag(), MyName(), 
	                                             UnitGUID("player"):sub(8) )
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
	
	EmoteSplitter.AddChatHook( "QUEUE", Me.EmoteSplitterQueue )
	EmoteSplitter.AddChatHook( "POSTQUEUE", Me.EmoteSplitterPostQueue )
	EmoteSplitter.SetChunkSizeOverride( "RP", 400 )
	EmoteSplitter.SetChunkSizeOverride( "RPW", 400 )
	
	Me.TRP_Init()
	Me.SetupMinimapButton()
	Me.ApplyOptions()
end

-------------------------------------------------------------------------------
function Me.GetFullName( unit )
	local name, realm = UnitName( unit )
	realm = realm or Me.realm
	return name .. "-" .. realm
end

-------------------------------------------------------------------------------
-- Protocol
-------------------------------------------------------------------------------
local TRANSFER_DELAY = 0.5
local TRANSFER_SOFT_LIMIT = 1500
local TRANSFER_HARD_LIMIT = 2500
Me.packets = {}
Me.sending = false
Me.send_timer = nil

-------------------------------------------------------------------------------
function Me.SendPacket( ... )
	local data = table.concat( {...}, ":" )
	table.insert( Me.packets, #data .. ":" .. data )
	Me.Timer_Start( "send", "ignore", TRANSFER_DELAY, Me.DoSend )
end

-------------------------------------------------------------------------------
function Me.SendPacketInstant( ... )
	local data = table.concat( {...}, ":" )
	table.insert( Me.packets, #data .. ":" .. data )
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
		if #data + #p < TRANSFER_HARD_LIMIT then
			data = data .. p
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
		if stream.name == "#RELAY#" then
			Me.connected = true
			Me.club   = club_id
			Me.stream = stream.streamId
			C_Club.FocusStream( Me.club, Me.stream )
			
			Me.SendPacket( "HENLO" )
			Me.TRP_OnConnected()
		end
	end
end

-------------------------------------------------------------------------------
function Me.OnChatMsg( event, text, sender, language, _,_,_,_,_,_,_,lineID,guid )
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
		
		if event == "SAY" and text ~= "" then
			Me.Bubbles_Add( sender, text )
		end
		
		local orcish
		if event == "SAY" and text ~= "" then orcish = text end
		
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
	guid   = guid or Me.player_guids[username]
	lineid = lineid or 0
	
	language = langauge or (GetDefaultLanguage())
	local event_check = event_type
	if event_type == "RP" then event_check = "RAID" end
	if event_type == "RPW" then event_check = "RAID_WARNING" end
	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G["ChatFrame" .. i]
		-- TODO, check if theres anything that we should do to NOT add messages to this frame
		if frame:IsEventRegistered( "CHAT_MSG_" .. event_check ) then
			ChatFrame_MessageEventHandler( frame, "CHAT_MSG_" .. event_type, msg, username, language, "", "", "", 0, 0, "", 0, lineid, guid, 0 )
		end
	end
	
	if ListenerAddon then
		ListenerAddon:OnChatMsg( "CHAT_MSG_" .. event_type, msg, username, language, "", "", "", 0, 0, "", 0, lineid, guid, 0 )
	end
	
	if event_type ~= "RP" and event_type ~= "RPW" then -- only pass valid to here
		if LibChatHander_EventHandler then
			local event_script = LibChatHander_EventHandler:GetScript( "OnEvent" )
			if event_script then
				event_script( LibChatHander_EventHandler, "CHAT_MSG_" .. event_type, msg, username, language, "", "", "", 0, 0, "", 0, lineid, guid, 0 )
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.R( user, msg )
	if user.self then return end
	
	local type, msg = msg:match( "([^:]+):(.+)" )
	
	if not msg then return end
	
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

-------------------------------------------------------------------------------
function Me.ProcessPacket.RP( user, msg )
	if not msg then return end
	
	local role = Me.GetRole( user )
	if role == 4 and C_Club.GetStreamInfo( Me.club, Me.stream ).subject:lower():find( "#mute" ) then
		-- RP channel is muted
		return
	end
	
	Me.SimulateChatMessage( "RP", msg, user.name )
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.RPW( user, msg )
	if not msg then return end
	
	local role = Me.GetRole( user )
	if role > 2 then return end -- Only leaders can RPW.
	
	Me.SimulateChatMessage( "RPW", msg, user.name )
	msg = ChatFrame_ReplaceIconAndGroupExpressions(msg);
	RaidNotice_AddMessage( RaidWarningFrame, msg, ChatTypeInfo["RPW"] );
	PlaySound( SOUNDKIT.RAID_WARNING );
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.HENLO( user, msg )
	if user.self then return end
	
	if Me.chat_pending[user.name] then
		Me.chat_pending[user.name].waiting = {
			SAY   = {};
			EMOTE = {};
			YELL  = {};
		}
	end
	Me.TRP_SendVernum()
end

-------------------------------------------------------------------------------
function Me.PacketHandler( user, packet )
	local type, rest = packet:match( "^([^:]+)(.*)" )
	if not type then return end
	if not Me.ProcessPacket[type] then return end
	Me.ProcessPacket[type]( user, rest:sub(2) )
end

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
	print( event, sender, text )
	if sender then
		if event == "CHAT_MSG_BN_WHISPER" then
			local prefix = BNetFriendOwnsName( bnet_id, sender ) and "" or "(Unverified!) "
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

-------------------------------------------------------------------------------
function Me.OnChatMsgCommunitiesChannel( event,
	          text, sender, language_name, channel, _, _, _, _, 
	          channel_basename, _, _, _, bn_sender_id, is_mobile, is_subtitle )
	if not Me.connected then return end
	if is_mobile or is_subtitle then return end
	if channel_basename ~= "" then channel = channel_basename end
	local club, stream = channel:match( ":(%d+):(%d+)$" )
	if tonumber(club) ~= Me.club or tonumber(stream) ~= Me.stream then return end
	C_Club.AdvanceStreamViewMarker( Me.club, Me.stream )
	
	local faction, player, guid, payload = text:match( "^##(.):([^:]+):([^:]+)//(.+)" )
	if not player then
		-- didn't match
		return
	end
	guid = "Player-" .. guid
	
	local user = {
		self    = BNIsSelf( bn_sender_id );
		faction = faction;
		name    = player;
		guid    = guid;
		bnet    = bn_sender_id;
	}
	
	if not user.self and player == Me.fullname then return end -- someone else using our name?
	
	if not Me.name_locks[player] then
		Me.name_locks[player] = bn_sender_id
	elseif Me.name_locks[player] ~= bn_sender_id then
		-- multiple bnet ids using this player - this is something malicious
		-- hopefully we already captured the right person
		return
	end
	
	-- message loop
	while #payload > 0 do
		local length = payload:match( "^(%d+):" )
		if not length then return end -- malformed
		
		-- extract packet
		-- example:
		-- |11:R:SAY:hello<next packet>
		-- |   ^         ^
		-- |   4         14
		-- |length     = 11
		-- |#length    = 2
		-- |#length+2  = 4
		-- |length+#length+1 = 14
		local packet = payload:sub( #length + 2, #length + length + 1 )
		if packet then
			Me.PacketHandler( user, packet )
		end
		payload = payload:sub( #length + 2 + length )
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

function Me.HandleOutgoingWhisper( msg, type, arg3, target )
	if not target:find('-') then
		target = target .. "-" .. Me.realm
	end
	target = target:lower()
	
	for friend = 1, BNGetNumFriends() do
		local accountID, _, _, _, _, _, _, is_online = BNGetFriendInfo( friend )
		print( "scan1", friend, accountID, is_online )
		if is_online then
			local num_accounts = BNGetNumFriendGameAccounts( friend )
			for account_index = 1, num_accounts do
				
				local _, char_name, client, realm,_, faction, _,_,_,_,_,_,_,_,_, game_account_id = BNGetFriendGameAccountInfo( friend, account_index )
				print( "scan2", account_index, char_name, client, realm ,faction, game_account_id )
				
				if client == BNET_CLIENT_WOW then
					char_name = char_name .. "-" .. realm:gsub(" ","")
					
					print( "scan3", char_name, target, UnitFactionGroup("player"), faction )
						-- TODO, faction is probably localized.
					if char_name:lower() == target and UnitFactionGroup("player") ~= faction then
						-- this is a cross-faction whisper!
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
function Me.EmoteSplitterQueue( msg, type, arg3, target )

	if type == "WHISPER" then
		return Me.HandleOutgoingWhisper( msg, type, arg3, target )
	end
	
	if Me.in_relay then return end
	if not Me.connected then return end
	
	if type == "RP" then
		if Me.GetRole() == 4 and Me.IsMuted() then
			print( "<RPLink> RP Channel is muted." )
			return false
		end
		Me.SendPacketInstant( "RP", msg )
		return false
	elseif type == "RPW" then
		if Me.GetRole() > 2 then
			print( "<RPLink> Only leaders can post in RP Warning." )
			return false
		end
		Me.SendPacketInstant( "RPW", msg )
		return false
	end
end

-------------------------------------------------------------------------------
function Me.EmoteSplitterPostQueue( msg, type, arg3, target )
	if Me.in_relay then return end
	if not Me.connected then return end
	-- 1,7 = orcish,common
	if type == "SAY" or type == "EMOTE" or type == "YELL" and (arg3 == 1 or arg3 == 7) then
		Me.SendPacketInstant( "R", type, msg )
	end
end

function Me.IsMuted()
	return C_Club.GetStreamInfo( Me.club, Me.stream ).subject:lower():find( "#mute" )
end

function Me.ToggleMute()
	if not Me.connected then return end
	local stream_info = C_Club.GetStreamInfo( Me.club, Me.stream )
	local desc = stream_info.subject
	if desc:find( "#mute" ) then
		desc = desc:gsub( "%s?#mute", "" )
	else
		desc = desc .. " #mute"
	end
	C_Club.EditStream( Me.club, Me.stream, nil, desc )
end

--DEBUG
C_Timer.After(1, function()
	Me.Connect( 32381 )
end)

-------------------------------------------------------------------------------
ChatTypeInfo["RP"]            = { r = 1, g = 1, b = 1, sticky = 1 }
ChatTypeInfo["RPW"]           = { r = 1, g = 1, b = 1, sticky = 1 }
hash_ChatTypeInfoList["/RP"]  = "RP"
hash_ChatTypeInfoList["/RPW"] = "RPW"
CHAT_RP_SEND                  = "RP: "
CHAT_RPW_SEND                 = "RP Warning: "
CHAT_RP_GET                   = "[RP] %s: "
CHAT_RPW_GET                  = "[RP Warning] %s: "
