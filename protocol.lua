-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- This is the lowest level in our protocol, for handling sending and receiving
--  basic data packets to and from the relay channel.
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
--  We keep large data transfers lik that in the lower priority, which in turn
--  enters Emote Splitter at a lower priority, and then chat and other
--  smaller messages get the higher priority, and basically skip the line and
--  make anything lower wait.
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
		table.insert( Me.packets[priority], "0:" .. command .. slug .. " " .. data )
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
		local priority = 10 -- This is the Emote Splitter priority we'll
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
		
		-- This suppresses Emote Splitter's initial chat filters and cutting
		--  function. We don't want our packets to be mangled. We want them
		--  whole.
		EmoteSplitter.Suppress()
		-- We want to cleanly insert everything into Emote Splitter's queue.
		-- Setting this flag causes its system to not start its send queue
		--  when this next packet is sent, and we have to manually start it
		--  below.
		EmoteSplitter.PauseQueue()
		EmoteSplitter.SetTrafficPriority( priority )
		C_Club.SendMessage( Me.club, Me.stream, data )
		EmoteSplitter.SetTrafficPriority( 1 )
		
		if not nowait then
			-- If nowait isn't set, then we only run this loop once.
			-- That means that we will wait a little bit to try and
			--  get more messages to smash together.
			break
		end
	end
	
	-- See PauseQueue above.
	EmoteSplitter.StartQueue()
	
	-- If we have more packets to send, we use our very-nifty timer API.
	if #Me.packets[1] > 0 or #Me.packets[2] then
		Me.Timer_Start( "protocol_send", "ignore", TRANSFER_DELAY, Me.DoSend )
	end
end
