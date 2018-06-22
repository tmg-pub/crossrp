
local AddonName, Me = ...

RPLink = Me

LibStub("AceAddon-3.0"):NewAddon( Me, AddonName, "AceEvent-3.0" )

Me.connected = false
Me.club      = nil
Me.stream    = nil

Me.name_locks = {}

Me.chat_pending = {}

local function MyName()
	local name, realm = UnitFullName( "player" )
	name = name .. "-" .. realm
	return name
end

local function FactionTag()
	local faction = UnitFactionGroup( "player" )
	return faction == "Alliance" and "A" or "H"
end

local function OppositeLanguage()
	return UnitFactionGroup( "player" ) == "Alliance" and "Orcish" or "Common"
end

function Me.Connect( club_id )
	Me.connected = false
	Me.name_locks = {}
	print("connecting")
	local club_info = C_Club.GetClubInfo( club_id )
	if not club_info then return end
	if club_info.clubType ~= Enum.ClubType.BattleNet then return end
	
	for _, stream in pairs( C_Club.GetStreams( club_id )) do
		if stream.name == "#RELAY#" then
			print("connected")
			Me.connected = true
			Me.club   = club_id
			Me.stream = stream.streamId
			
			EmoteSplitter.Suppress()
			C_Club.SendMessage( Me.club, Me.stream, string.format( "HI:%s:%s:", FactionTag(), MyName() ))
		end
	end
end

function Me:OnEnable()
	Me:RegisterEvent( "CHAT_MSG_COMMUNITIES_CHANNEL", Me.OnChatMsgCommunitiesChannel )
	
	Me:RegisterEvent( "CHAT_MSG_SAY",   Me.OnChatMsg )
	Me:RegisterEvent( "CHAT_MSG_EMOTE", Me.OnChatMsg )
	Me:RegisterEvent( "CHAT_MSG_YELL",  Me.OnChatMsg )
	
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_SAY",
		function( _, _, msg, sender, language )
			if language == OppositeLanguage() then
				return true
			end
		end)
	
	hooksecurefunc( EmoteSplitter, "QueueChat", Me.OnQueueChat )
end

Me.ProcessMessage = {}

function Me.ProcessMessage.R( faction, player, msg )
	local type, target, msg = msg:match( "([^:]+):([^:]+):(.+)" )
	-- apply message
	local pending = Me.chat_pending[player]
	if pending then
		if pending.waiting[type] > 0 then
			pending.waiting[type] = pending.waiting[type] - 1
			-- print.
			
			for i = 1, NUM_CHAT_WINDOWS do
				local frame = _G["ChatFrame" .. i]
				if frame:IsShown() then
					ChatFrame_MessageEventHandler( frame, "CHAT_MSG_" .. type, msg, player, (GetDefaultLanguage()), "", "", "", 0, 0, "", 0, nil, pending.guid, 0 )
				end
			end
		end
	end
end

function Me.ProcessMessage.BIN( msg )
end

function Me.ProcessMessage.TXT( msg )
end

function Me.ProcessMessage.HI( faction, player, msg )
	if Me.chat_pending[player] then
		Me.chat_pending[player].waiting = 0
	end
end

function Me.OnChatMsg( event, text, sender, language, _,_,_,_,_,_,_,_,guid )
	event = event:sub( 10 )
	if (event == "SAY" or event == "YELL") and language ~= OppositeLanguage() then return end
	if event == "EMOTE" and text ~= CHAT_EMOTE_UNKNOWN then return end
	
	if not Me.chat_pending[sender] then
		Me.chat_pending[sender] = {
			guid = guid;
			waiting = 0
		}
	end
	
	local data = Me.chat_pending[sender]
	data.waiting[event] = data.waiting[event] + 1
end

function Me.OnChatMsgCommunitiesChannel( event,
	          text, sender, language_name, channel, _, _, _, _, 
	          channel_basename, _, _, _, bn_sender_id, is_mobile, is_subtitle )
	if not Me.connected then return end
	if is_mobile or is_subtitle then return end
	if channel_basename ~= "" then channel = channel_basename end
	local club, stream = channel:match( ":(%d+):(%d+)" )
	if club ~= Me.club or stream ~= Me.stream then return end
	
	if BNIsSelf( bn_sender_id ) then return end
	
	local event, faction, player, rest = text:match( "([^:]+):([^:]):([^:]+):(.+)" )
	if not Me.name_locks[player] then
		Me.name_locks[player] = bn_sender_id
	elseif Me.name_locks[player] ~= bn_sender_id then
		-- two bnet ids using this player name is something wrong.
		return
	end
	
	local method = Me.ProcessMessage[event]
	if method then method( faction, player, rest ) end
end

function Me.RelayChat( msg, type, arg3, target )
	arg3 = tonumber(arg3)
	if arg3 ~= 1 and arg3 ~= 7 then return end -- not Orcish/Common
	
	EmoteSplitter.Suppress()
	C_Club.SendMessage( Me.club, Me.stream, string.format( "R:%s:%s:%s:%s:%s", FactionTag(), MyName(), type, target or "", msg ))
end

function Me.OnQueueChat( msg, type, arg3, target )
	if Me.in_relay then return end
	if not Me.connected then return end
	
	if type == "SAY" or type == "EMOTE" or type == "YELL" then
		print('doing relay')
		C_Timer.After( 0.01, function()	Me.RelayChat( msg, type, arg3, target ) end )
	end
end

function Me.SendData( tag, msg )
	EmoteSplitter.Suppress()
	msg = Me.ToBase64( msg )
	C_Club.SendMessage( Me.club, Me.stream, string.format( "BIN:%s:%s:%s:%s:%s:%s", FactionTag(), MyName(), tag, msg ))
end

function Me.SendTextData( tag, msg )
	EmoteSplitter.Suppress()
	C_Club.SendMessage( Me.club, Me.stream, string.format( "TXT:%s:%s:%s:%s:%s:%s", FactionTag(), MyName(), tag, msg ))
end

function Me.ReceiveData( prefix, msg, type, target )
	
end

function Me.ReceiveTextData( prefix, msg, type, target )
	
end

C_Timer.After(1, function()
	Me.Connect( 32381 )
end)