
local AddonName, Me = ...

RPLink = Me

LibStub("AceAddon-3.0"):NewAddon( Me, AddonName, "AceEvent-3.0" )

Me.connected = false
Me.club      = nil
Me.stream    = nil

Me.name_locks = {}

Me.chat_pending = {}

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
	Me.StartSend()
end

-------------------------------------------------------------------------------
function Me.SendPacketInstant( ... )
	local data = table.concat( {...}, ":" )
	table.insert( Me.packets, #data .. ":" .. data )
	Me.send_now = true
	Me.StartSend()
end

-------------------------------------------------------------------------------
function Me.StartSend( instant )
	if Me.send_now then
		Me.StopSendTimer()
		Me.DoSend()
		return
	end
	if Me.sending then return end
	Me.sending = true
	Me.StartSendTimer()
end

-------------------------------------------------------------------------------
function Me.StartSendTimer()
	Me.StopSendTimer()
	local timer = {
		cancel = false
	}
	Me.send_timer = timer
	C_Timer.After( TRANSFER_DELAY, function()
		if timer.cancel then return end
		Me.DoSend()
	end)
end

-------------------------------------------------------------------------------
function Me.StopSendTimer()
	if Me.send_timer then
		Me.send_timer.cancel = true
	end
end

-------------------------------------------------------------------------------
function Me.DoSend()
	Me.sending = false
	if #Me.packets == 0 then 
		Me.send_now = false
		return
	end
	
	if not Me.connected then 
		Me.send_now = false
		Me.packets = {}
		return end
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
	
	if #Me.packets > 0 then
		-- More to send
		if Me.send_now then
			Me.DoSend()
		else
			Me.StartSendTimer()
		end
	else
		Me.send_now = false
	end
end

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
			
			Me.SendPacket( "HENLO" )
		end
	end
end

-------------------------------------------------------------------------------
function Me:OnEnable()
	Me.user_prefix = string.format( "##%s:%s:%s//", FactionTag(), MyName(), 
	                                             UnitGUID("player"):sub(8) )
	Me.fullname = MyName()
	
	Me:RegisterEvent( "CHAT_MSG_COMMUNITIES_CHANNEL", Me.OnChatMsgCommunitiesChannel )
	
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
			if Me.connected and msg == CHAT_EMOTE_UNKNOWN then
				return true
			end
		end)
	
	
	EmoteSplitter.AddChatHook( "QUEUE", Me.EmoteSplitterQueue )
	EmoteSplitter.AddChatHook( "POSTQUEUE", Me.EmoteSplitterPostQueue )
	EmoteSplitter.SetChunkSizeOverride( "RP", 400 )
	EmoteSplitter.SetChunkSizeOverride( "RPW", 400 )
end

-------------------------------------------------------------------------------
function Me.OnChatMsg( event, text, sender, language, _,_,_,_,_,_,_,_,guid )
	event = event:sub( 10 )
	
	if event == "SAY" or event == "EMOTE" or event == "YELL" then
		if (event == "SAY" or event == "YELL") and language ~= OppositeLanguage() then return end
		if event == "EMOTE" and text ~= CHAT_EMOTE_UNKNOWN then return end
		
		if not Me.chat_pending[sender] then
			Me.chat_pending[sender] = {
				guid = guid;
				waiting = {
					SAY   = 0;
					EMOTE = 0;
					YELL  = 0;
				}
			}
		end
		
		local data = Me.chat_pending[sender]
		data.waiting[event] = data.waiting[event] + 1
	end
end

-------------------------------------------------------------------------------
Me.ProcessPacket = {}
-------------------------------------------------------------------------------
function Me.ProcessPacket.R( user, msg )
	if user.self then return end
	
	local type, msg = msg:match( "([^:]+):(.+)" )
	
	if not msg then return end
	
	-- apply message
	local pending = Me.chat_pending[user.name]
	if pending then
		if pending.waiting[type] > 0 then
			pending.waiting[type] = pending.waiting[type] - 1
			-- print.
			
			for i = 1, NUM_CHAT_WINDOWS do
				local frame = _G["ChatFrame" .. i]
				if frame:IsShown() then
					ChatFrame_MessageEventHandler( frame, "CHAT_MSG_" .. type, msg, user.name, (GetDefaultLanguage()), "", "", "", 0, 0, "", 0, nil, user.guid, 0 )
				end
			end
			
			if ListenerAddon then
				ListenerAddon:OnChatMsg( "CHAT_MSG_" .. type, msg, user.name, (GetDefaultLanguage()), "", "", "", 0, 0, "", 0, nil, user.guid, 0 )
			end
		end
	end
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.RP( user, msg )
	if not msg then return end
	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G["ChatFrame" .. i]
		if frame:IsShown() then
			ChatFrame_MessageEventHandler( frame, "CHAT_MSG_RP", msg, user.name, (GetDefaultLanguage()), "", "", "", 0, 0, "", 0, nil, user.guid, 0 )
		end
	end
	if ListenerAddon then
		ListenerAddon:OnChatMsg( "CHAT_MSG_RP", msg, user.name, (GetDefaultLanguage()), "", "", "", 0, 0, "", 0, nil, user.guid, 0 )
	end
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.RPW( user, msg )
	if not msg then return end
	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G["ChatFrame" .. i]
		if frame:IsShown() then
			ChatFrame_MessageEventHandler( frame, "CHAT_MSG_RPW", msg, user.name, (GetDefaultLanguage()), "", "", "", 0, 0, "", 0, nil, user.guid, 0 )
		end
	end
	if ListenerAddon then
		ListenerAddon:OnChatMsg( "CHAT_MSG_RPW", msg, user.name, (GetDefaultLanguage()), "", "", "", 0, 0, "", 0, nil, user.guid, 0 )
	end
	msg = ChatFrame_ReplaceIconAndGroupExpressions(msg);
	RaidNotice_AddMessage( RaidWarningFrame, msg, ChatTypeInfo["RPW"] );
	PlaySound(SOUNDKIT.RAID_WARNING);
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.BIN( user, msg )
	local tag, msg = msg:match( "^([^:]+):(.+)" )
	if not msg then return end
	Me.ReceiveData( tag, Me.FromBase64(msg) )
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.BIN( user, msg )
	local tag, msg = msg:match( "^([^:]+):(.+)" )
	if not msg then return end
	Me.ReceiveData( tag, Me.FromBase64(msg) )
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.TXT( user, msg )
	local tag, msg = msg:match( "^([^:]+):(.+)" )
	if not msg then return end
	Me.ReceiveData( tag, msg )
end

-------------------------------------------------------------------------------
function Me.ProcessPacket.HENLO( user, msg )
	if Me.chat_pending[user.name] then
		Me.chat_pending[user.name].waiting = 0
	end
end

-------------------------------------------------------------------------------
function Me.PacketHandler( user, packet )
	local type, rest = packet:match( "^([^:]+):(.*)" )
	print( type, rest )
	if not type then return end
	if not Me.ProcessPacket[type] then return end
	Me.ProcessPacket[type]( user, rest )
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
	}
	
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
function Me.EmoteSplitterQueue( msg, type, arg3, target )
	if Me.in_relay then return end
	if not Me.connected then return end
	if type == "RP" then
		Me.SendPacket( "RP", msg )
		return false
	elseif type == "RPW" then
		Me.SendPacket( "RPW", msg )
		return false
	end
end

-------------------------------------------------------------------------------
function Me.EmoteSplitterPostQueue( msg, type, arg3, target )
	if Me.in_relay then return end
	if not Me.connected then return end
	-- 1,7 = orcish,common
	if type == "SAY" or type == "EMOTE" or type == "YELL" and (arg3 == 1 or arg3 == 7) then
		print('doing relay')
		Me.SendPacketInstant( "R", type, msg )
	end
end


C_Timer.After(1, function()
	Me.Connect( 32381 )
end)

-------------------------------------------------------------------------------
local function Hexc( hex )
	return {
		r = tonumber( "0x"..hex:sub(1,2) )/255;
		g = tonumber( "0x"..hex:sub(3,4) )/255;
		b = tonumber( "0x"..hex:sub(5,6) )/255;
	}
end

-------------------------------------------------------------------------------
local my_chat_types = {
	{
		type    = "RP";
		command = "/RP";
		color   = Hexc "BAE4E5";
		header  = "RP: ";
		get     = "[RP] %s: ";
	};
	{
		type    = "RPW";
		command = "/RPW";
		color   = Hexc "EA3556";
		header  = "RP Warning: ";
		get     = "[RP Warning] %s: ";
	};
}

for k,v in pairs( my_chat_types ) do
	ChatTypeInfo[v.type] = {
		r = v.color.r;
		g = v.color.g;
		b = v.color.b;
	}
	hash_ChatTypeInfoList[v.command] = v.type
	_G["CHAT_"..v.type.."_SEND"] = v.header
	_G["CHAT_"..v.type.."_GET"] = v.get
end

--hash_ChatTypeInfoList["/RP"] = "RP"
--hash_ChatTypeInfoList["/RPW"] = "RP"
--[[
ChatFrame1EditBox:HookScript( "OnTextChanged", function( editBox, userInput )
	if not userInput then return end
	
	for _,chat_type in pairs( my_chat_types ) do
		if editBox:GetText():sub( 1, #chat_type.command + 1 ):upper() == (chat_type.command .. " ") then
			-- snip off command
			editBox:SetText( editBox:GetText():sub( #chat_type.command + 2 ))
			
			local header = _G[editBox:GetName().."Header"];
			local headerSuffix = _G[editBox:GetName().."HeaderSuffix"];
			header:SetWidth(0);
			header:SetText( chat_type.header )
			editBox:SetAttribute( "chatType", chat_type.type );
			local headerWidth = (header:GetRight() or 0) - (header:GetLeft() or 0);
			local editBoxWidth = (editBox:GetRight() or 0) - (editBox:GetLeft() or 0);
			if ( headerWidth > editBoxWidth / 2 ) then
				header:SetWidth(editBoxWidth / 2);
				headerSuffix:Show();
			else
				headerSuffix:Hide();
			end
			local color = chat_type.color
			header:SetTextColor( color.r, color.g, color.b );
			headerSuffix:SetTextColor( color.r, color.g, color.b );
			editBox:SetTextInsets( 15 + header:GetWidth() + (headerSuffix:IsShown() and headerSuffix:GetWidth() or 0), 13, 0, 0 );
			editBox:SetTextColor( color.r, color.g, color.b );
			editBox.focusLeft:SetVertexColor( color.r, color.g, color.b );
			editBox.focusRight:SetVertexColor( color.r, color.g, color.b );
			editBox.focusMid:SetVertexColor( color.r, color.g, color.b );
			
		end
	end
end)
]]









