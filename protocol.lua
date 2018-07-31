-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- This is the lowest level in our protocol, for handling sending and receiving
--  basic data packets to and from the relay channel.
-------------------------------------------------------------------------------
local _, Me = ...
local Gopher = LibGopher
local LibRealmInfo  = LibStub("LibRealmInfo")
-------------------------------------------------------------------------------
-- You can see this number when you receive messages, it's packed next to the
--  faction tag. If the number read is higher than this, then the message is
--  rejected as not-understood. We don't have the most forward compatible code,
local PROTOCOL_VERSION = 2  -- but we'll try to avoid changing this.
-------------------------------------------------------------------------------
-- This is our handler list for when we see a message from the relay channel
--  (a 'packet').
-- ProcessPacket[COMMAND] = function( user, command, msg, args )
Me.ProcessPacket = Me.ProcessPacket or {}
-------------------------------------------------------------------------------
-- TRANSFER_DELAY is how much time we wait before queueing normal packets. We
--  do this to minimize how many actual messages we're sending, trying to
--  group as many of them into a single message as possible. If you call
--  SendPacket a bunch of times with small data (sent together within this
--  window), they'll all be compacted into a single message and sent at once 
--                    with the same user header. It's just a good thing to do.
local TRANSFER_DELAY      = 0.25
-------------------------------------------------------------------------------
-- The SOFT and HARD limits are how much data we can actually send. The HARD
--  limit is the maximum size of a message that we'll send. Internally, the 
--  hard limit is about 4000 bytes, but if you send a text message that big,
--  the client chokes on it if it sees it anywhere, so we cut this down to a
--  more manageable size. This can change if we stop using VISIBLE TEXT to
--  transfer data in the future. The soft limit is how much data we want to at
--                                 least fit in a message before sending it.
-- We can push over the soft limit if a packet happens to do so, but we don't
--  push over the hard limit. Once we go over the soft limit, the message is
--  sent.
local TRANSFER_SOFT_LIMIT = 2000
local TRANSFER_HARD_LIMIT = 3000
-------------------------------------------------------------------------------
-- We have two queue priorities. A simple system, but it's important for when
--  the user is busy transferring their obnoxiously big profile. During the
--  profile transfer, we don't want them to not be able to send any chat text.
--  We keep large data transfers like that in the lower priority, which in turn
--  enters Gopher at a lower priority, and then chat and other smaller messages
--  get the higher priority, and basically skip the line and make anything 
--  lower wait.
-- [1] = high prio, [2] = low prio
Me.packets    = {{},{}}
-------------------------------------------------------------------------------
-- After we send a message, we can shorten further messages by cutting out our
--                        user name. If anyone sends HENLO then we reset this.
Me.protocol_user_short = nil
Me.protocol_sender_cache = {}
-------------------------------------------------------------------------------
-- These servers get a special single digit realm identifier because they're
--  very popular. This may change if we decide to support non RP servers
--                                     (these IDs are overwriting PvE servers).
Me.PRIMO_RP_SERVERS = {
	[1] = 1365; -- Moon Guard US
	[2] = 536;  -- Argent Dawn EU
	[3] = 1369; -- Wyrmrest Accord US
}
-------------------------------------------------------------------------------
-- Kills any data remaining. This is so that when we disconnect and reconnect,
--            any data in the queue is NOT going to be sent to the new server.
function Me.KillProtocol()
	Me.packets = {{},{}}
	Me.Timer_Cancel( "protocol_send" )
end

-------------------------------------------------------------------------------
-- Packets are composed of these pieces: COMMAND, ARGS, and DATA.
-- At the bare minimum, if there's no data or args, then the packet can simply
--  be the COMMAND by itself, and when paired with the username in the actual
--  outputted message, it looks like this:
--
--         hh2A Tammya-MoonGuard HENLO
--
-- This is a complete packet, and more packets can follow after if there is
--  a separator.
--
--         hh2A Tammya-MoonGuard HENLO;Packet2;Packet3
--
-- That's not quite a semicolon there either. The "message" is the complete
--  message received from someone, and the "header" is the hash, protocol
--  version, faction tag, and username. Packets are commands that follow.
--
--          Message
--         vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
--         hh2A Tammya-MoonGuard RP Testing!  
--         ^^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^^
--              Header            Packet
--
-- Simple arguments can be fed to a command by the colon separator.
--
--         hh2A Tammya-MoonGuard COMMAND:arg1:arg2:arg3
--         hh2A Tammya-MoonGuard COMMAND:arg1:arg2:arg3 <data...>
-- 
-- Second is the full size packet. Extra arguments cannot contain spaces
--  or the colon character.
-- All of the packet strings must be plain, UTF-8 compliant text, or the
--                                              server may reject them.
-- In 1.1.1 the username may be replaced with "*", meaning that you should
--  use the last username seen. If you don't have that, then you just ignore
--  the message until they tell you who they are. The HENLO command causes
--                      people to send their names again on the next message.
-- In 1.1.1 the `hh` field is a base64 hash purely for making it difficult
--  for a human to input data directly into the chat window without actually
--                                                         calling our code.
local function QueuePacket( command, data, priority, ... )
	local slug = ""
	if select( "#", ... ) > 0 then
		slug = ":" .. table.concat( { ... }, ":" )
	end
	local packet = command .. slug
	if data then
		-- "Full" packet.
		packet = packet .. " " .. data
	end
	
	-- U+037E -> ;
	packet = packet:gsub( ";", ";" )
	table.insert( Me.packets[priority], packet )
end

-------------------------------------------------------------------------------
-- We wrap our internal queueing magic in some easy to use interfaces.
-- SendPacket adds to the queue, but waits a little bit to allow more data
--  to be added into our next message before it's sent.
function Me.SendPacket( command, data, ... )
	QueuePacket( command, data, 1, ... )
	Me.Timer_Start( "protocol_send", "ignore", TRANSFER_DELAY, Me.DoSend )
end

-------------------------------------------------------------------------------
-- Larger data should use the low priority buffer, so it doesn't choke out
--  player chat. Player chat should always try to be as fast as possible for
--                                              a nice, seamless experience.
function Me.SendPacketLowPrio( command, data, ... )
	QueuePacket( command, data, 2, ... )
	Me.Timer_Start( "protocol_send", "ignore", TRANSFER_DELAY, Me.DoSend )
end

-------------------------------------------------------------------------------
-- Sometimes you don't want your message to wait for the send timer. When
--  you're sending relay-chat messages, Cross RP uses this, to flush the 
--                                       send queue instantly right after.
function Me.SendPacketInstant( command, data, ... )
	QueuePacket( command, data, 1, ... )
	Me.Timer_Cancel( "protocol_send" )
	Me.DoSend( true )
end

local function BattleTagXs( battle_tag )
	return battle_tag:match( "[^#]+" ):gsub(".", "x")
end

local function MyBattleTagXs()
	return BattleTagXs( select(2,BNGetInfo()) )
end

local function KStringXs( bnetid, kstring )
	local _,_, battle_tag = BNGetFriendInfoByID( bnetid )
	if battle_tag then
		-- Prefer this over using the Kstring, because we don't know if the
		--  Kstring is a battle tag length or a Real ID length.
		return BattleTagXs( battle_tag )
	end
	kstring = kstring:match( "|k([0]+)" )
	return kstring:gsub( ".", 'x' )
end

-------------------------------------------------------------------------------
-- Our special hash function. Uses a wacky base64.
--
local HASH_DIGITS 
           = "YLZeJA2Nw1UxFfDmMbKScuRipCaH8nsG7X34rdV590Q6ovhjPtWyTEgIBzlkOq@$"

local function MessageHash( text )
	local cs = 0
	for i = 1, #text do
		-- Similar to simple Pearson hashing, but with the added bit rotation.
		-- cs = (cs ROL 1) XOR byte
		cs = (cs * 2 + bit.rshift( cs, 11 )) % 2^12
		cs = bit.bxor( cs, text:byte(i) )
	end
	
	local digit1 = cs % 64
	local digit2 = bit.rshift(cs, 6) % 64
	
	return HASH_DIGITS:sub( 1+digit1,1+digit1 )
	         .. HASH_DIGITS:sub( 1+digit2, 1+digit2 )
end

Me.MessageHash = MessageHash

-------------------------------------------------------------------------------
-- Our flushing function. Flush it down those pipes.
--
function Me.DoSend( nowait )

	-- Hopefully this is a nice place for this.
	if not BNFeaturesEnabledAndConnected() then
		Me.Disconnect()
	end
	
	-- If we aren't connected, or aren't supposed to be sending data, just
	--                   kill the queue and escape. This can happen mid-send.
	if (not Me.connected) then -- or (not Me.relay_on) then
		-- No longer doing a relay_on check. Be -extra- prudent to not send
		--  unnecessary data while the relay is off.
		Me.packets = {{},{}}
		return
	end
	
	-- Special optimization for TRP vernums.
	Me.TRP_TryMixVernum()
	
	if #Me.packets[1] == 0 and #Me.packets[2] == 0 then
		-- Both queues are empty.
		return
	end
	
	-- Sometimes I wish languages had a special type of loop, where
	--  it doesn't repeat automatically, and you have to call `continue`
	--  or something to trigger the next iteration. This is a little
	--  ugly.
	while #Me.packets[1] > 0 or #Me.packets[2] > 0 do
		
		-- Build a nice packet to send off
		local data = Me.user_prefix .. " "
		if Me.protocol_user_short then
			-- This will need some more thought.
			--data = Me.user_prefix_short
		end
		Me.protocol_user_short = true
		local first_packet = true
		
		local priority = 10 -- This is the Gopher priority we'll
		                    --  use if we don't have any high priority
		                    --  packets left.
		while #Me.packets[1] > 0 or #Me.packets[2] > 0 do
			-- we try to empty priority 1 first
			local index = 1
			local p = Me.packets[index][1]
			if p then
				-- We flag this message as high priority since it contains a 
				--  message from the first queue.
				-- If it only contains messages from the second queue then 
				--  it'll be the priority set outside.
				priority = 1
			else
				-- If it's empty, then pull from queue 2.
				-- Note that a low priority message might get sent with high
				--  priority traffic if it gets grouped with it.
				index = 2
				p = Me.packets[index][1]
			end
			
			-- See the notes above on the HARD and SOFT limits. Basically our
			--  ideal packet is larger than SOFT and must be smaller than HARD.
			if #data + #p + 2 < TRANSFER_HARD_LIMIT then
				-- That's not a semicolon. It's U+037E - Greek Question Mark.
				-- That character should be converted to a semicolon anywhere
				--  else.
				if not first_packet then
					data = data .. ";"
				end
				first_packet = false
				data = data .. p
				table.remove( Me.packets[index], 1 )
			end
			if #data >= TRANSFER_SOFT_LIMIT then
				break
			end
		end
		
		-- Messages are prefixed with a message hash to prevent humans from
		--  entering data into the relay. Unfortunately we can't use a direct
		--  BattleTag in the hash, because BattleTags aren't available from
		--          other players in the community unless they're BNet friends.
		data = MessageHash( MyBattleTagXs() .. data ) .. data
		
		-- This suppresses Gopher's initial chat filters and cutting
		--  function. We don't want our packets to be mangled. We want them
		--  whole.
		Gopher.Suppress()
		-- We want to cleanly insert everything into Gopher's queue.
		-- Setting this flag causes its system to not start its send queue
		--  when this next packet is sent, and we have to manually start it
		--  below.
		Gopher.PauseQueue()
		Gopher.SetTrafficPriority( priority )
		-- All of these Gopher settings are reset after a chat call, like this.
		-- You don't need to worry about resetting.
		C_Club.SendMessage( Me.club, Me.stream, data )
		
		if not nowait then
			-- If nowait isn't set, then we only run this loop once.
			-- That means that we will wait a little bit to try and
			--  get more messages to smash together.
			break
		end
	end
	
	-- See PauseQueue above.
	Gopher.StartQueue()
	
	-- If we have more packets to send, we use our very-nifty timer API.
	if #Me.packets[1] > 0 or #Me.packets[2] then
		Me.Timer_Start( "protocol_send", "ignore", TRANSFER_DELAY, Me.DoSend )
	end
end

-------------------------------------------------------------------------------
-- Returns true if a user is on the Ignore list.
--
function Me.IsIgnored( user )
	local name = user.name:lower()
	for i = 1, GetNumIgnores() do
		if GetIgnoreName(i):lower() == name then 
			return true
		end
	end
end

-------------------------------------------------------------------------------
-- CHAT_MSG_COMMUNITIES_CHANNEL is how our protocol receives its data.
function Me.OnChatMsgCommunitiesChannel( event,
	          text, sender, language_name, channel, _, _, _, _, 
	          channel_basename, _, _, _, bn_sender_id, is_mobile, is_subtitle )
	
	-- If not connected, ignore all incoming traffic.
	--if not Me.connected then return end

	-- Not sure how these quite work, but we probably don't want them.
	if is_mobile or is_subtitle then return end
	
	-- `basename` is usually "", but if for some reason that we're subscribed
	--  to the relay channel, basename will be set to the raw channel name
	--  without the channel number prefix.
	if channel_basename ~= "" then channel = channel_basename end
	local club, stream = channel:match( ":(%d+):(%d+)$" )
	club   = tonumber(club)
	stream = tonumber(stream)
	if not Me.connected or Me.club ~= club or Me.stream ~= stream then
		-- Goodbye autoconnect.
		return
	end
	Me.AddTraffic( #text + #sender )
	-- The header for the messages is composed as follows:
	--  HHPF <user> ....
	--  HH: Message hash.
	--  P:  Protocol version.
	--  F:  Faction code.
	local msghash, version, faction, rest
	    = text:match( "^([0-9A-Za-z@$][0-9A-Za-z@$])([0-9]+)(.) (.+)" )
	if not msghash 
	         or msghash ~= MessageHash( KStringXs( bn_sender_id, sender )
 	                                                      .. text:sub(3) ) then
		Me.DebugLog( "Bad hash on message from %s.", sender )
		-- Invalid message.
		return
	end
	if not msghash then return end -- couldn't parse.
	
	version = tonumber( version )
	if version < PROTOCOL_VERSION then
		-- This user is out of date. We may still accept their message if we
		--  are compatible with some parts.
		return
	end
	if version > PROTOCOL_VERSION then
		-- This user is using a newer version.
		return
	end
	
	local player, realm_id
	
	-- This stuff isn't really used, but it seems like a good idea for the 
	--  future. Only problem with it is when someone is using multiple
	--  accounts under the same Bnet ID.
	if faction == "C" then
		player = Me.protocol_sender_cache[bn_sender_id]
		-- Unknown user.
		if not player then return end
		player, faction = player[1], player[2]
	else
		player, rest = rest:match( "^([^0-9]+[0-9]+) (.+)" )
		if not player then
			Me.DebugLog( "Received invalid message from %s.", sender )
			return
		end
		if not Me.protocol_sender_cache[bn_sender_id] then
			Me.protocol_sender_cache[bn_sender_id] = {}
		end
		Me.protocol_sender_cache[bn_sender_id][1] = player
		Me.protocol_sender_cache[bn_sender_id][2] = faction
	end
	
	player, realm_id = player:match( "^([^0-9]+)([0-9]+)" )
	if not player then
		Me.DebugLog( "Received invalid message from %s.", sender )
		return
	end
	
	-- Fix up player name in case capitalization is incorrect.
	player = player:lower()
	player = player:gsub( "^[%z\1-\127\194-\244][\128-\191]*", string.upper )
	
	-- Some RP servers are treated specially with a single digit ID to save
	--  on sweet byte bandwidth. These are the massively populated ones.
	realm_id = tonumber( realm_id )
	if Me.PRIMO_RP_SERVERS[realm_id] then
		realm_id = Me.PRIMO_RP_SERVERS[realm_id]
	end
	
	local _, _, _, realm_type = 
						LibRealmInfo:GetRealmInfoByGUID(UnitGUID("player"))
	
	local _, _, realm, realm_type = LibRealmInfo:GetRealmInfoByID( realm_id )
	if not realm_type:lower():find("rp") then
		Me.DebugLog( "%s sent a message from a non-RP server.", sender )
		return
	end
	
	-- Pack all of our user info neatly together; we share this with our packet
	--  handlers and such.
	local user = {
		-- True if this message is mirrored from the player.
		--self    = BNIsSelf( bn_sender_id );
		
		-- "A" or "H" (or something else). This is parsed directly from the
		--  message.
		faction = faction;
		
		-- True if the sender's faction doesn't match your own.
		horde   = faction ~= Me.faction;
		
		-- True if from another realm (adjusted below for connected realms).
		xrealm  = realm ~= Me.realm;
		
		-- User's full name.
		name     = player .. "-" .. realm;
		realm_id = realm_id;
		
		-- User's Bnet account ID.
		bnet    = bn_sender_id;
		
		-- What club they're communicating through.
		club    = club;
		stream  = stream;
		
		-- True if we're connected to the same relay with Cross RP.
		connected = Me.connected and Me.club == club and Me.stream == stream;
		
		-- The time this user was last seen.
		time    = GetTime();
	}
	
	user.self = user.name:lower() == Me.fullname:lower()
	
	if Me.IsIgnored( user ) then
		-- This player is being ignored and we should completely discard any
		--  data from them.
		return
	end
	
	-- Flag this user as having Cross RP
	Me.crossrp_users[user.name] = user
	
	if user.xrealm then
		-- They might not actually be cross-realm. GetAutoCompleteRealms()
		--  returns a list of realms that the user's realm is connected to.
		for _, v in pairs( GetAutoCompleteRealms() ) do
			if v == user.realm then
				-- Connected realm.
				user.xrealm = nil
				break
			end
		end
	end
	
	if user.connected then -- (This may get confusing for off-server abuse.)
		-- Here are some checks to prevent abuse. The community needs to be
		--  moderated to remove people that try to spoof messages.
		if not BNIsSelf(bn_sender_id) and user.self then 
			-- Someone else is posting under our name. This is clear malicious
			--  intent.
			print( "|cffff0000" .. L( "POLICE_POSTING_YOUR_NAME", sender ))
			return
		end
		
		-- We only allow listening to names from one bnet account ID.
		if not Me.name_locks[user.name] then
			Me.name_locks[user.name] = bn_sender_id
		elseif Me.name_locks[user.name] ~= bn_sender_id then
			-- If we see two people trying to use a name, then we print a
			--  warning.
			-- We aren't quite sure who is the real owner, and the mods need to
			--  deal with that. Hopefully, we captured the right person so they
			--  can keep posting.
			print( "|cffff0000" .. L( "POLICE_POSTING_LOCKED_NAME", sender ))
			return
		end
				
		-- Registering traffic is also only for connected users.
		--Me.AddTraffic( #text + #sender )
	end
	
	-- We're going to parse the actual messages now and then run the packet
	--  handler functions.
	while #rest > 0 do
		-- See the packet layout in the top of this file.
		--  Basically it looks like this or this or this.
		--  "HELLO"
		--  "HELLO DATA"
		--  "HELLO:META:STUFF DATA"
		-- Lots of scary, delicate code in this section.
		local packet_length = rest:find( ";" )
		local packet
		if packet_length then
			-- Parse out a single packet and then cut it from the rest.
			packet = rest:sub( 1, packet_length - 1 )
			-- 2 is the length of our separator.
			rest = rest:sub( packet_length + 2 )
		else
			-- This is the last packet or the only packet in the message.
			packet = rest
			rest   = ""
		end
		
		local header = packet:match( "^%S+" ) -- Cut out first word. The header
		if not header then return end       -- is all one word. Throw away the
		                                    -- packet if the header doesn't
											-- exist.
		-- If the header is the whole message, then it's the command.
		local command = header
		
		-- Try to parse out different parts of the header. Each one is 
		--  separated by a colon.
		local parts = {}
		for v in command:gmatch( "[^:]+" ) do
			table.insert( parts, v )
		end
		
		command = parts[1]
		
		-- Any additional packet data or "payload" follows after the header.
		-- There's a single space between them. This is optional, and data
		--  will just equal to "" if there isn't the space or text.
		-- +1 is right after the header, +2 is after the space too.
		local data = packet:sub( #header + 2 )
		
		-- Pass to the packet handler.
		if Me.ProcessPacket[command] then
			Me.ProcessPacket[command]( user, command, data, parts )
		end
	end
end
