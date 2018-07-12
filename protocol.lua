-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- This is the lowest level in our protocol, for handling sending and receiving
--  basic data packets to and from the relay channel.
-------------------------------------------------------------------------------
local _, Me = ...
local Gopher = LibGopher
-------------------------------------------------------------------------------
-- You can see this number when you receive messages, it's packed next to the
--  faction tag. If the number read is higher than this, then the message is
--  rejected as not-understood. We don't have the most forward compatible code,
local PROTOCOL_VERSION = 1  -- but we'll try to avoid changing this.
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
local TRANSFER_DELAY      = 0.5
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
local TRANSFER_SOFT_LIMIT = 1500
local TRANSFER_HARD_LIMIT = 2500
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
-- Kills any data remaining. This is so that when we disconnect and reconnect,
--            any data in the queue is NOT going to be sent to the new server.
function Me.KillProtocol()
	Me.packets = {{},{}}
	Me.Timer_Cancel( "protocol_send" )
end

-------------------------------------------------------------------------------
-- We have a few types of packets that we can create. Packets are composed of
--  these pieces: COMMAND, LENGTH, SLUG, and DATA.
-- At the bare minimum, if there's no data or slug, then the packet can simply
--  be the COMMAND by itself, and when paired with the username in the actual
--  outputted message, it looks like this:
--
--         1A Tammya-MoonGuard HENLO                               (SHORT)
--
-- When you add data, the length part is added. Length isn't optional if
--  there's a slug, either. The length is the length of the data excluding
--  any spaces padding around it.
--
--          Message
--         vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
--         1A Tammya-MoonGuard 8:RP Testing!                        (FULL)
--                             ^^^^^^^^^^^^^
--                              Packet
-- Slug examples:
--
--         1A Tammya-MoonGuard 0:COMMANDNAME:arg1:arg2:arg3         (SLUG)
--         1A Tammya-MoonGuard 5:COMMANDNAME:arg1:arg2:arg3 Datas   (FULL)
-- 
-- First doesn't have any data, but still needs 0 length set for the parser.
-- Second is the full size packet. The slug is just extra arguments for the
--  command which cannot contain ":" or spaces.
-- All of the packet strings must be plain, UTF-8 compliant text, or the
--                                              server may reject them.
local function QueuePacket( command, data, priority, ... )
	local slug = ""
	if select("#",...) > 0 then
		slug = ":" .. table.concat( { ... }, ":" )
	end
	if data then
		-- "Full" packet.
		table.insert( Me.packets[priority], string.format( "%X", #data ) 
		                             .. ":" .. command .. slug .. " " .. data )
	elseif slug ~= "" then
		-- "Slug" packet.
		table.insert( Me.packets[priority], 
		                               "0:" .. command .. slug .. " " .. data )
	else
		-- "Short" packet.
		table.insert( Me.packets[priority], command )
	end
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

-------------------------------------------------------------------------------
-- Our flushing function. Flush it down those pipes.
--
function Me.DoSend( nowait )
	
	-- If we aren't connected, or aren't supposed to be sending data, just
	--                   kill the queue and escape. This can happen mid-send.
	if (not Me.connected) or (not Me.relay_on) then
		Me.packets = {{},{}}
		return
	end
	
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
		local data = Me.user_prefix
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
			if #data + #p + 1 < TRANSFER_HARD_LIMIT then
				data = data .. " " .. p
				table.remove( Me.packets[index], 1 )
			end
			if #data >= TRANSFER_SOFT_LIMIT then
				break
			end
		end
		
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
--	if club ~= Me.club or stream ~= Me.stream then 
--		-- Not our relay channel.
--		return
--	end
	
	-- Parse out the user header, it looks like this:
	--  1A Username-RealmName ...
	local version, faction, player, realm, rest 
	                   = text:match( "^([0-9]+)(.)%S* ([^%-]+)%-([%S]+) (.+)" )
	if not player then
		-- Invalid message.
		return
	end
	
	if (tonumber(version) or 0) < PROTOCOL_VERSION then
		-- That user needs to update.
		-- TODO: We can send them an update message here.
		return
	end
	
	-- Pack all of our user info neatly together; we share this with our packet
	--  handlers and such.
	local user = {
		-- True if this message is mirrored from the player.
		self    = BNIsSelf( bn_sender_id );
		
		-- "A" or "H" (or something else). This is parsed directly from the
		--  message.
		faction = faction;
		
		-- True if the sender's faction doesn't match your own.
		horde   = faction ~= Me.faction;
		
		-- True if from another realm (adjusted below for connected realms).
		xrealm  = realm ~= Me.realm;
		
		-- User's full name.
		name    = player .. "-" .. realm;
		
		-- User's Bnet account ID.
		bnet    = bn_sender_id;
		
		-- What club they're communicating through.
		club    = club;
		stream  = stream;
		
		-- True if we're connected to the same club with Cross RP.
		connected = Me.connected and Me.club == club;
		
		-- The time this user was last seen.
		time    = GetTime();
	}
	
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
		if not user.self and user.name:lower() == Me.fullname:lower() then 
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
		Me.AddTraffic( #text + #sender )
	end
	
	-- We're going to parse the actual messages now and then run the packet
	--  handler functions.
	while #rest > 0 do
		-- See the packet layout in the top of this file.
		--  Basically it looks like this or this or this.
		--  "HELLO"
		--  "4:HELLO DATA"
		--  "4:HELLO:META:STUFF DATA"
		-- Lots of scary, delicate code in this section.
		local header = rest:match( "^%S+" ) -- Cut out first word. The header
		if not header then return end       -- is all one word. Throw away the
		                                    -- packet if the header doesn't
											-- exist.
		-- If the header is the whole message, then it's the command.
		local command = header
		
		-- Try to parse out different parts of the header. Each one is 
		--  separated by a colon.
		local length
		local parts = {}
		for v in command:gmatch( "[^:]+" ) do
			table.insert( parts, v )
		end
		
		-- If there are at least two parts, then the first two are the data
		--  length and actual command.
		if #parts >= 2 then
			length, command = parts[1], parts[2]
			length = tonumber( length, 16 )
			if not length then return end
		end
		
		-- If `length` is > 0 then we cut that much data. Lots of off-by-one
		--  error potential about here. We add a space before the data, and
		--  then another space after the data if there's another packet
		--  afterwards.
		local data = nil
		if length and length > 0 then
			-- +1 is right after the header, +2 is after the space too.
			data = rest:sub( #header + 2, #header+2 + length-1 )
			if #data < length then
				-- Make sure that the packet was sound and has all of our
				--  needed data.
				return
			end
		end
		
		-- Pass to the packet handler.
		if Me.ProcessPacket[command] then
			Me.ProcessPacket[command]( user, command, data, parts )
		end
		
		-- Cut away this message.
		-- Length of header, plus space, plus one for the next word, and then
		-- if `length` is set, there's another space and 
		-- `length` bytes (`length`+1 or 0).
		rest = rest:sub( #header + 2 + (length or -1) + 1 )
	end
end
