-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2019)
--
-- The low-level communications layer.
-------------------------------------------------------------------------------
local _, Me = ...
local Comm  = {}
Me.Comm = Comm
-------------------------------------------------------------------------------
local pairs, ipairs, select, DebugLog,    DebugLog2,    tonumber, tostring = 
      pairs, ipairs, select, Me.DebugLog, Me.DebugLog2, tonumber, tostring
local strmatch,     strfind,     format,        floor,      strsub = 
      string.match, string.find, string.format, math.floor, string.sub
local strbyte,     strchar,     min,      random,      wipe, type =
      string.byte, string.char, math.min, math.random, wipe, type
-------------------------------------------------------------------------------
-- JOB PRIORITIES                                                   #priorities
-- "LOW"    This is meant for the bulk of traffic. LOW traffic is sent out of
--           order to share the bandwidth among multiple tasks, so if you have
--           a large transfer in progress in the LOW queue, and then queue
--           another small transfer in the LOW queue afterwards, the smaller
--           one will likely finish first (the load distribution is random;
--           each transfer frame sends a random piece from any LOW queue).
-- "NORMAL" Default. This is for our direct traffic, sent in-order and pauses
--           LOW queue until it's finished.
-- "FAST"   This bypasses our rate limiter (which is very low), passing data
--           directly to the global-level chat limiter (Chomp). So it's like
--           NORMAL, but very fast.
-- "URGENT" This bypasses everything and puts data out on the line instantly,
--           via a direct call to SendAddonMessage/BNSendGameData, meant for
--           things that require critical execution. Should only be used for
--           small objects, because otherwise there's a risk for disconnecting
--           the user.
-------------------------------------------------------------------------------
-- This is how many bytes per second we will throttle normal messages. This is
--  to make it so that we're a sort of background service. After our throttler
--                                   we still go through ChatThrottleLib/Chomp.
local RATE_LOW      = 200
-------------------------------------------------------------------------------
-- Not yet implemented. I figure that if a user is "actively" doing some
--  "cross rp", then they shoul use this larger value to be a stronger transfer
--  node. (Could also make it so that non-active users report a higher load.)
local RATE_FULL     = 1000
-------------------------------------------------------------------------------
-- How much data must be buffered before we send out a chunk.
--
local SEND_BUFFER   = 300
-------------------------------------------------------------------------------
-- How much data we can send in a single Bnet data chunk. The max for these
--  is around 4000, but that's a lot of data to process in a single instance.
local MAX_BNET_SIZE = 400

-------------------------------------------------------------------------------
-- Communication protocol version. This is present in all messages (the first
--  character), and we will refuse any messages where the protocol version
--  doesn't match ours.
local PROTO_VERSION = 1                      Comm.PROTO_VERSION = PROTO_VERSION
local PROTO_VERSION_STR = tostring( PROTO_VERSION )
-------------------------------------------------------------------------------
-- All jobs have a "slot" attached, which is a number visible on the receiving
--  end. Basically it lets someone know what message a chunk belongs to. For
--  LOW priority messages, things are sent out of order, and a slot number is
--  like a serial that controls where each chunk ends up. So for example if you
--  queue two messages, they can get slot 5 and 6, and then the transfer
--  service will send randomly bits from slot 5 and 6, so the receiver is
--  getting both at once, and using the slot number to sort the pieces out.
local m_next_slot = 0
-------------------------------------------------------------------------------
-- All of our jobs have a serial number attached. This is for sorting the
--  higher priority messages, which are sent in-order, so that a protocol can
--  depend easily on one message being received before another. For NORMAL
--  traffic, messages with lower serieals are sent before higher serials. For
--  FAST and URGENT traffic, the data goes directly to the global throttler or
--  bypasses entirely, and are naturally in-order. For LOW priority, this isn't
--  used and messages can arrive out of order.
local m_next_serial = 1
-------------------------------------------------------------------------------
-- This is our main list of jobs. `send` is outgoing. `recv` is incoming,
--  spawned in our data-received handlers.
local m_jobs = {
	send = {};
	recv = {};
}                                                            Comm.jobs = m_jobs
-------------------------------------------------------------------------------
-- The last time we processed our queue, used to determine how much bandwidth
--  we should add for the next process time.
local m_last_run = GetTime()
-------------------------------------------------------------------------------
-- How many bytes per second we will transfer. We can actually go a bit over
--  this in bursts, but the number will go negative and pause our transfers
--  until it recovers.
local m_bps = RATE_LOW
-------------------------------------------------------------------------------
-- The max value that `bandwidth` can be. Note that this is still quite small.
--  If we have any messages queued larger than it, we'll still send them anyway
--                once we're "at the max", and the bandwidth will dip negative.
local m_burst = RATE_LOW * 1.25
-------------------------------------------------------------------------------
-- How much bandwidth we have accumulated over time for transfers. Incremented
--  during each process by how much time has passed times `bps`.
local m_bandwidth = 0
-------------------------------------------------------------------------------
-- A constant added to the length of chunks sent. Overhead for sending data.
local m_send_overhead = 10
-------------------------------------------------------------------------------
-- Handlers for completed messages received. The first word in a message
--                                     determines which handler it's passed to.
local m_handlers = {     
	BROADCAST = {}; -- Messages received over CHANNEL distribution.
	BNET      = {}; -- Messages received over BNET whispers.
	WHISPER   = {}; -- Messages received over ADDON whispers.
	PARTY     = {}; -- Messages received over PARTY/RAID distribution.
}                                                    Comm.handlers = m_handlers
-------------------------------------------------------------------------------
-- Whenever we send a message to someone, we save their name in here, and then
--  in our CHAT_MSG_SYSTEM handler we check for the "that player is offline"
--  message, and suppress it.
local m_suppress_offline_message = {}           Comm.suppress_offline_message =
                                                     m_suppress_offline_message
-------------------------------------------------------------------------------
-- The Job class handles buffering data being sent or received.
local Job = {}                                                   Comm.Job = Job
-------------------------------------------------------------------------------
-- Create a new Job object.
-- `slot` is the transfer slot index (unique within the past 5 minutes or so).
-- `type` is what transfer medium, either "BNET" or "ADDON". 
-- `dest` is who the message is being sent to. For BNET, this is game ID. For
--  "ADDON", this can be a player fullname, or "*" for the broadcast channel,
--  or "P" for a raid/party broadcast. For jobs that are receiving data, this
--  is nil.
function Job.New( slot, type, dest )
	-- The Job object.
	local job = setmetatable( {
		-----------------------------------------------------------------------
		-- `slot` is a unique ID that is sent or received that manages what
		--  chunks go to which messages. It's not truly unique, as slot numbers
		--  are reused after a while.
		slot = slot;
		-----------------------------------------------------------------------
		-- The time this job was created. When we fetch a job in the queue, we
		--  check the time. If the time is too old, we treat the job as a 
		--  defunct entity, and clean it up, making a new job. This could
		--  happen if a job gets broken mid-transfer, and it just sits there
		--  until the slot is reused.
		time = GetTime();
		-----------------------------------------------------------------------
		-- Controls what API we're using for transferring receiving, as well as
		--  the underlying protocol. BNET or ADDON, we use a different transfer
		--  protocol.
		-----------------------------------------------------------------------
		type = type;
		-- For sending jobs, the destination of our message. Can be a game id,
		--  a fullname, "*" (broadcast), or "P" (party).
		dest = dest;
		-- Flag that a job has all of its data. A job can be started, data can
		--  be queued, but if this flag isn't set, then the job will expect
		--  more data to be queued before it triggers the final transfer or
		--  callback and ends the job. Once `complete` is set, it's an error to
		--                                              add more data to a job.
		complete = false;
		-----------------------------------------------------------------------
		-- The data buffer. Data received is concatenated to this. In a receive
		--  handler, you can reset this value to "", and when the next chunk of
		--     of data is received, it will be added again to the empty string.
		text = "";
		-----------------------------------------------------------------------
		-- What addon prefix to use when sending. This is suffixed by "+RP".
		--           This is used mainly for "secure" transfers and broadcasts.
		prefix = "";
		-----------------------------------------------------------------------
		-- Each job has an incrementing number attached. Used to keep "NORMAL"
		--                                     priority messages sent in-order.
		serial = m_next_serial;
		-----------------------------------------------------------------------
		-- See #priorities. What transfer priority this job uses. Not used for
		--  receiving jobs.
		priority = "NORMAL";
		-----------------------------------------------------------------------
		-- Something really stupid is that Bnet GameData can arrive out of
		--  order, so we have to take additional steps to make sure that we get
		--  things in the right order when receiving. We do this by having a
		--  "page number" attached to all Bnet messages, and then use that to
		--  sort things out in the end. Any pages we receive that are not the
		--  "next page" (tracked below) are just queued until we receive the
		--  right next page.
		pages_waiting = nil;
		-----------------------------------------------------------------------
		-- The next page we're expecting for a BNET transfer. If we receive a
		--       page that isn't the next, then it's queued until we get to it.
		next_page = 1;
		-----------------------------------------------------------------------
		-- The protocol has a marker for the last page in a BNET message, and
		--                        when next_page reaches last_page, we're done.
		last_page = nil;
	}, {
		-- Class metatable.
		__index = Comm.Job;
	})
	
	-- Each job has a unique serial.
	m_next_serial = m_next_serial + 1
	
	return job
end                                                      local JobNew = Job.New

-------------------------------------------------------------------------------
-- Primes an existing job to be ready for fresh data. This is used when we
--  run into a problem that is likely due to trying to apply new data over an
--  old job, so we reset and hope that things work out (they likely won't). In
--  the case of a failure, the job will usually just sit and then time out. Oh
--  well!
function Job:Reset()
	self.time      = GetTime()
	self.complete  = false
	self.text      = ""
	self.next_page = 1
	self.lage_page = nil
	if self.pages_waiting then
		wipe(self.pages_waiting)
	end
end                                                  local JobReset = Job.Reset

-------------------------------------------------------------------------------
-- After adding data to a job, this starts the dequeue process, or dispatches
--                                        directly for FAST and URGENT traffic.
function Job:TryDispatch()
	if self.cancel_send or not self.sender then return end
	local priority = self.priority
	
	-- It'd be kind of weird to call DispatchPacket for incomplete jobs, but
	--        FAST and URGENT are most likely `complete` as soon as they start.
	if priority == "FAST" then
		self.chomp_prio = "MEDIUM"
		Comm.DispatchPacket( self, true )
	elseif priority == "URGENT" then
		self.nothrottle = true
		Comm.DispatchPacket( self, true )
	else
		Comm.RunNextFrame()
	end
end                                      local JobTryDispatch = Job.TryDispatch

-------------------------------------------------------------------------------
-- A "page" is a chunk of a job with a unique ID. Jobs can be populated in two
--  ways, directly adding text, and adding pages. Pages are mainly for
--  receiving data that can be out of order, like BNET transfers. Each piece
--  has a page number attached, which basically tells where in the data it
--  belongs. So for example in contrast to directly adding data, we could add
--  page 1, 4, 5, 2, 3, and the system will sort them out, concatenating them
--  from lowest to highest.
-- `is_last` tells the job that the index given is the last page, so as soon as
--  all pages before that are received, the job is complete.
-- `text` is the contents of the page. Pages do not have any fixed size.
-- A message transferred could be received like this:
--  [PAGE 1, 252 BYTES], [PAGE 4 (LAST) 45 BYTES], [PAGE 2, 250 BYTES],
--   [PAGE 3, 251 BYTES].
-- When the last page 4 is received, 1,2,3 are expected, and the job waits for
--  those before treating the data as complete, ordering all the pages and
--  putting them together:
--  [PAGE 1 252 BYTES][PAGE 2 250 BYTES][PAGE 3 251 BYTES][PAGE 4 45 BYTES]
--  (TOTAL 798 byte string)
-- Returns true if job.text has new data added. False if the page is just
--                          queued, waiting for more pages before it to use it.
function Job:AddPage( index, is_last, text )
	-- `next_page` tracks the lowest page before there's a break in the page
	--  list. So if we have pages 1, 2 and 3, next page will be 4. If we have
	--  pages 1, 2, and 5, next page will be 3. This is a safety check - if we
	--  receive a page under that number, then the job is likely "new", and we
	--                     should reset it. An error might be more appropriate.
	local next_page = self.next_page
	if next_page > index then
		JobReset( self )
		next_page = self.next_page
	end
	
	if self.complete then
		-- Can't add data to `complete` jobs.
		error( "Job is already complete." )
	end
	
	local new_data = false
	
	if is_last then
		self.last_page = index
	end
	
	local pages_waiting = self.pages_waiting
	
	if next_page == index then
		-- This page is the next one we are expecting, so we can add it
		--  to our text string.
		local selftext = self.text
		selftext = selftext .. text
		next_page = next_page + 1
		-- And then any pages that are queued can also be added, until we find
		--  a gap in the pages again.
		while pages_waiting and pages_waiting[next_page] do
			selftext = selftext .. pages_waiting[next_page]
			pages_waiting[next_page] = nil
			next_page = next_page + 1
		end
		new_data = true
		
		-- Updated fields.
		self.next_page = next_page
		self.text      = selftext
	else
		-- This page is out of order, so we create the queue if it doesn't
		--  exist, and then save the page for later. It'll be picked up above
		--  when `next_page` finds it.
		pages_waiting = pages_waiting or {}
		pages_waiting[index] = text
		
		-- Updated fields.
		self.pages_waiting = pages_waiting
	end
	
	local last_page = self.last_page
	
	-- If we just wrote the `last_page`, then this job is complete, and no
	--                                       further data will be accepted.
	if last_page and next_page > last_page then
		self.complete = true
	end
	
	JobTryDispatch( self )
	
	return new_data
end                                              local JobAddPage = Job.AddPage

-------------------------------------------------------------------------------
-- Abruptly terminates a send job. This may leave the endpoint a bit confused
--  if we're mid-transfer, but it will just time out. This is mainly used for
--  small things, such as Proto's status broadcasts - if something changes,
--  then the previous messages are invalid, and they can be cancelled if
--                              they're still waiting in the send queue.
function Job:CancelSend()
	self.cancel_send = true
	Comm.RemoveJob( self )
end                                        local JobCancelSend = Job.CancelSend

-------------------------------------------------------------------------------
-- Append text to the job's buffer. Jobs are designed to allow progressive
--  transfers, so one could add a few chunks of text on one frame, and the job
--  stays open to more data until `complete` is set. A single job is a transfer
--  to a single destination. This progressive transferring is especially
--  important when it comes to forwarding routed data (see Proto.R1 for more
--  info). `complete` means this chunk of text being added is the last, and no
--                     more will be allowed, and the job will close soon after.
function Job:AddText( complete, text )
	if self.complete then
		error( "Job is already complete." )
	end
	self.time     = GetTime()
	self.text     = self.text .. text
	self.complete = complete
	
	JobTryDispatch( self )
end                                              local JobAddText = Job.AddText

-------------------------------------------------------------------------------
-- Public function to set the priority of the job. See #priorities. Normally
--  this can just be set when the job is created, but it can be changed through
--  here.
function Job:SetPriority( priority )
	self.priority = priority
	self.chomp_prio = priority == "LOW" and "LOW" or "MEDIUM"
end                                      local JobSetPriority = Job.SetPriority

-------------------------------------------------------------------------------
-- The job prefix is the addon message prefix used, basically meant for private
--  transfer channels (if you broadcast a message with a private prefix, only
--  clients that register that prefix will see it). `nil` to use the default
--  prefix.
function Job:SetPrefix( prefix )
	self.prefix = prefix or ""
end

-------------------------------------------------------------------------------
-- The sent callback is triggered when the last piece of data is sent by this
--  job. So for a job with 10 pages, only after the last page is sent will this
--  callback trigger. Function signature is just `( job )`, a reference to the
--  job object triggering it.
function Job:SetSentCallback( callback )
	self.onsent = callback
end

-------------------------------------------------------------------------------
-- Scans through our send table and cancels any jobs that have this "tag"
--  attached to them. Tags can be added by adding an entry to the `tags` table
--  in the job object. This table may be nil, and must be created if used.
--  e.g. job.tags = { mytag = true } - Comm.CancelSendByTag( "mytag" )
function Comm.CancelSendByTag( tag )
	for k, v in pairs( m_jobs.send ) do
		local tags = v.tags
		if tags and tags[tag] then
			-- Careful here because this modifies the list we're iterating
			--  over.
			JobCancelSend( v )
		end
	end
end

-------------------------------------------------------------------------------
-- Creates or returns an existing job for the list and slot specified.
-- `list` can be "send" or "recv", for send jobs and receive jobs.
-- `type` can be "BNET" or "ADDON". Type must match when getting the an
--  existing job again.
-- `dest` is set as the job destination when the job is created. Can be `nil`
--  for received jobs (the dest is ourself).
-- If a job exists in that slot already, it will be returned so long as it
--               isn't "timed out" - in this case a new job will overwrite it.
function Comm.GetJob( list, slot, type, dest )
	local joblist = m_jobs[list]
	local job = joblist[slot]
	if job then
		if GetTime() < job.time + 5*60 then
			if job.type ~= type or job.dest ~= dest then
				error( "Debug: Logic error." )
			end
			return job
		else
			-- this job timed out. make a new one
		end
	end
	
	local job = JobNew( slot, type, dest )
	job.list = list
	
	joblist[slot] = job
	return job
end                                                  local GetJob = Comm.GetJob

-------------------------------------------------------------------------------
-- Remove a job from our job lists. Done whenever a job is complete, needs no
--                                   further processing, and it can be deleted.
function Comm.RemoveJob( job )
	if job.list then
		m_jobs[job.list][job.slot] = nil
		-- This function can safely be called multiple times.
		job.list = nil
	end
end                                            local RemoveJob = Comm.RemoveJob

-------------------------------------------------------------------------------
-- Returns the next available transfer/receive slot, for starting new
--  transfers.
function Comm.GetNextSlot()
	local slot = m_next_slot
	-- In the protocol, the "slot" is stored as two binary bytes in the range
	--  of 1-127 (can't send NULL/zero bytes), so slot can be in the range of
	--  [0, 127*127-1].
	m_next_slot = (m_next_slot + 1) % (127*127)
	return slot
end                                        local GetNextSlot = Comm.GetNextSlot

-------------------------------------------------------------------------------
-- SENDING FUNCTIONS                                                   #sending
-- The following set of functions work as follows.
-- Each one starts a new "send" job to the destination specified, and that job
--  is returned.
-- If `complete` is false, then the job will stay "open" for more data, which
--  can be added with `job:AddText( complete, text )` or 
--  `job:AddPage( page, is_last, text )`. Once the `complete` flag is set, then
--  the job is finished up and closed, and no further data can be transferred
--  using it. If `complete` is true, then this is the only call required to
--  send the complete message. Normally, `complete` is usually true, but there
--  are cases where you might want to send data progressively, especially if
--  you do not have all of the data, such as when acting as a router for a long
--  message.
-- `prefix` is the addon prefix used, excluding the "+RP" bit. "1251" will show
--  up on addon channel "1251+RP". `nil` is the same as "".
-- `priority` is the transfer priority used. See #priorities.
-- Example:
--  (Start a new send job, but it's incomplete, so it will stay open.)
--    job = Comm.SendAddonPacket( "someone", false, "<message data>" )
--  (Later on, we can add the rest of the data.)
--    job:AddText( false, "Hello " )
--    job:AddText( true, "World." )
--  (Once `complete` is set, the job is closed.)
-------------------------------------------------------------------------------
-- Starts a new transfer to `game_account_id` over Bnet. Job type is "BNET".
-- Note that over BNET, messages are always received regardless of prefix used.
--  You don't need to register addon prefixes for Bnet channels.
function Comm.SendBnetPacket( game_account_id, complete, text, prefix,
                                                                     priority )
	local job = GetJob( "send", GetNextSlot(), "BNET", game_account_id )
	job.sender   = true
	if prefix then job.prefix = prefix end
	if priority then 
		JobSetPriority( job, priority )
	end
	
	if text then
		JobAddText( job, complete, text )
	end
	return job
end                                  local SendBnetPacket = Comm.SendBnetPacket

-------------------------------------------------------------------------------
-- Normally this isn't used. Just here for completion's sake. When starting a
--  sending process, you usually do it through the normal Packet function,
--  which sends data in a straight sequence rather than a random-paged
--  sequence.
function Comm.SendBnetPacketPaged( game_account_id, page, is_last, text,
                                                             prefix, priority )
	local job = GetJob( "send", GetNextSlot(), "BNET", game_account_id )
	job.sender  = true
	if prefix then job.prefix = prefix end
	if priority then 
		JobSetPriority( job, priority )
	end
	
	if text then
		JobAddPage( job, page, is_last, text )
	end
	return job
end                        local SendBnetPacketPaged = Comm.SendBnetPacketPaged

-------------------------------------------------------------------------------
-- Starts a new transfer to the target over an addon channel.
-- `target` may be:
--   "*" to broadcast to the Cross RP channel ("CHANNEL" distribution).
--   "P" to send the message to the raid/party ("RAID"/"PARTY" distribution).
--   <playername> to send directly to a player ("WHISPER" distribution).
function Comm.SendAddonPacket( target, complete, text, prefix, priority )
	local job = GetJob( "send", GetNextSlot(), "ADDON", target )
	job.sender   = true
	if prefix then job.prefix = prefix end
	if priority then
		JobSetPriority( job, priority )
	end
	
	if text then
		JobAddText( job, complete, text )
	end
	return job
end                                local SendAddonPacket = Comm.SendAddonPacket

-------------------------------------------------------------------------------
-- Shortcut function to send a Simple Message Fast. That is, a string of
--  formatted text with FAST priority. Used often with the RP chat system, as
--                                   chat is meant to be high priority traffic.
function Comm.SendSMF( target, text, ... )
	if select( "#", ... ) > 0 then
		text = format( text, ... )
	end
	SendAddonPacket( target, true, text, nil, "FAST" )
end

-------------------------------------------------------------------------------
-- And one to send a message with URGENT priority.
function Comm.SendSMU( target, text, ... )
	if select( "#", ... ) > 0 then
		text = format( text, ... )
	end
	SendAddonPacket( target, true, text, nil, "URGENT" )
end

-------------------------------------------------------------------------------
-- Callback for when we receive data from someone. This may trigger multiple
--  times for a single message for progress, and then once at the end for
--  completion.
function Comm.OnDataReceived( job, dist, sender )
	if job.proto_abort then return end
	DebugLog2( "DATA RECEIVED", job.prefix, job.type, 
	              job.complete and "COMPLETE" or "PROGRESS", sender, job.text )
	
	if job.firstpage then
		-- If this is the first page, we parse the command from the message for
		--  routing.
		local command = strmatch( job.text, "^(%S+)" )
		if not command then
			job.proto_abort = true
			return
		end
		job.command = command
	end
	
	local jobtype, jobcommand = job.type, job.command
	local handler_result
	
	-- Looks more scary than it is. Just basic splitting up the `dist` and then
	--  passing it to a handler part of that set.
	if jobtype == "BNET" then
		local handler = m_handlers.BNET[job.command]
		if handler then
			handler_result = handler( job, sender )
		else
			DebugLog( "[Comm] Couldn't find handler for '%s' (BNET).",
			                                                       jobcommand )
		end
	elseif jobtype == "ADDON" then
		if dist == "WHISPER" then
			local handler = m_handlers.WHISPER[jobcommand]
			if handler then
				handler_result = handler( job, sender )
			else
				DebugLog( "[Comm] Couldn't find handler for '%s' (WHISPER).",
				                                                   jobcommand )
			end
		elseif dist == "CHANNEL" then
			local handler = m_handlers.BROADCAST[jobcommand]
			if handler then
				handler_result = handler( job, sender )
			else
				DebugLog( "[Comm] Couldn't find handler for '%s' (BROADCAST).",
				                                                   jobcommand )
			end
		elseif dist == "RAID" or dist == "PARTY" then
			local handler = m_handlers.PARTY[jobcommand]
			if handler then
				handler_result = handler( job, sender )
			else
				DebugLog( "[Comm] Couldn't find handler for '%s' (PARTY).",
				                                                   jobcommand )
			end
		end
	end
	
	-- Message handlers can return `false` to abort the transfer (any further
	--  data for that job will be discarded, and no further callbacks will be
	--  issued).
	if handler_result == false then
		job.proto_abort = true
	end
end                                  local OnDataReceived = Comm.OnDataReceived

-------------------------------------------------------------------------------
-- Pack a number in a double-byte format suitable for addon transfers.
-- Range is [0, 127*127-1]. Returns a 2-byte string. Used characters in the
--  string are \1-\127 (Bnet whispers don't support \128-\255).
function Comm.PackNumber2( number )
	return strchar( 1 + floor( number / 127 ), 1 + (number % 127) )
end                                        local PackNumber2 = Comm.PackNumber2

-------------------------------------------------------------------------------
-- Unpack a number. Accepts a 2-byte string. Returns the decoded number.
-- `index` is the index in the string to look at.
function Comm.UnpackNumber2( text, index )
	index = index or 1
	local a, b = strbyte( text, index, index+1 )
	return (a - 1) * 127 + (b - 1)
end                                    local UnpackNumber2 = Comm.UnpackNumber2

-------------------------------------------------------------------------------
-- Main handler for Bnet whispers (BN_CHAT_MSG_ADDON).
function Comm.OnBnChatMsgAddon( event, prefix, message, _, sender )
	-- All Cross RP messages (what we're interested in) have the prefix ending
	--  with "+RP".
	local crp_prefix, valid = strmatch( prefix, "(.*)(%+RP)" )
	if not valid then return end
	
	-- Parsing out the first two parts of the protocol.
	-- First is a number, that's the protocol version.
	-- Second is a character that signals what position this page is in, the 
	--  "part".
	local proto, part, rest = strmatch( message, "([0-9]+)([<=>%-])(.*)" )
	if not proto then
		DebugLog( "Invalid BNET message from %s.", sender )
		return
	end
	if proto ~= PROTO_VERSION_STR then
		DebugLog( "Protocol version mismatch from %s.", sender )
	end
	
	Me.AddTraffic( #message )
	
	-- If the part character is "-", then the entire message has been received,
	--  (fits in one chunk).
	-- Otherwise, the part will be "<" for the first page of the message, "="
	--  for a page in the middle, and ">" to mark the last page.
	if part == "-" then
		-- Complete message in one chunk, so we have a bit of a shortcut here.
		local job = JobNew( "temp", "BNET" )
		JobAddText( job, true, rest )
		job.firstpage = true
		job.prefix = crp_prefix
		OnDataReceived( job, "WHISPER", sender )
		return
	end
	
	-- The first call to UnpackNumber2 uses the first 2 characters of rest
	--  only, so the strsub has been omitted.
	local slot, page = UnpackNumber2( rest, 1 ), 
	                   UnpackNumber2( rest, 3 )
					   
	-- Slots are unique by both the number and the sender, and we index our
	--  receive table like that.
	slot = sender .. "-" .. slot
	
	local job = GetJob( "recv", slot, "BNET" )
	job.prefix = crp_prefix
	local new_data = false
	if part == "<" then
		-- This is the first page. For BNET messages, we can receive ANY page
		--  first, and this can be filled in after we have already received
		--  other pages.
		-- TODO: We don't need a marker for the first page for BNET transfers.
		--  We have a page number, and page #1 should always be the first page.
		--  We only need a page marker for the last page.
		-- `rest:sub( 5 )` strips data header.
		new_data = JobAddPage( job, page, false, strsub( rest, 5 ) )
		job.firstpage = true
	elseif part == "=" then
		-- "=" - this is a page in the middle.
		new_data = JobAddPage( job, page, false, strsub( rest, 5 ) )
		job.firstpage = false
	elseif part == ">" then
		-- ">" - this is the last page.
		new_data = JobAddPage( job, page, true, strsub( rest, 5 ) )
		job.firstpage = false
	end
	
	-- `firstpage` is set in the job object after receiving the first page.
	-- Used for the message handler to determine what the message's command is.
	
	-- Delete completed jobs.
	if job.complete then
		RemoveJob( job )
	end
	
	if new_data then
		-- This is only called after more data is added to `job.text`. If pages
		--  are received out of order, this isn't triggered until we have the
		--  right pages to add more to `job.text`.
		OnDataReceived( job, "WHISPER", sender )
	end
end

-------------------------------------------------------------------------------
-- Main handler for addon messages (CHAT_MSG_ADDON).
function Comm.OnChatMsgAddon( event, prefix, message, dist, sender )
	-- CHAT_MSG_ADDON is a high traffic event, so we do this (redundant) check
	--  here which is a FAST way to check if the prefix is likely a Cross RP
	--  prefix.
	-- Checking for the + (ASCII 43) in +RP.
	if strbyte( prefix, -3 ) ~= 43 then return end
	
	-- And then we properly parse the prefix, which is in the format
	--  "<channel>+RP".
	local crp_prefix, valid = strmatch( prefix, "(.*)(%+RP)" )
	if not valid then return end
	
	local proto, part, rest = strmatch( message, "([0-9]+)([<=>%-])(.*)" )
	if not proto then
		-- Couldn't parse message.
		DebugLog( "Invalid ADDON message from %s.", sender )
		return
	end
	if proto ~= PROTO_VERSION_STR then
		DebugLog( "Protocol version mismatch from %s.", sender )
	end
	
	Me.AddTraffic( #message )
	
	-- "-" means the entire message fits in a single page.
	if part == "-" then
		local job = JobNew( "temp", "ADDON" )
		JobAddText( job, true, rest )
		job.firstpage = true
		job.prefix = crp_prefix
		OnDataReceived( job, dist, sender )
		return
	end
	
	-- Using the first two characters of `rest` here.
	-- For ADDON messages, we don't have a page number, because they are
	--  guaranteed to be sent and received in-order. The page number is just
	--  for ordering.
	local slot = sender .. "-" .. UnpackNumber2( rest )
	
	local job = GetJob( "recv", slot, "ADDON" )
	job.prefix = crp_prefix
	
	-- "<" is the first page. "=" are middle pages. ">" is the last page.
	if part == "<" then
		-- In some rare corner cases, this job might be an old defunct job.
		--  This shouldn't really happen, but in the case it does, we reset it
		--  if we're about to write the first page.
		JobReset( job )
		JobAddText( job, false, strsub( rest, 3 ))
		job.firstpage = true
	elseif part == "=" then
		-- middle page
		JobAddText( job, false, strsub( rest, 3 ))
		job.firstpage = false
	elseif part == ">" then
		-- last page
		JobAddText( job, true, strsub( rest, 3 ))
		job.firstpage = false
	end
	
	-- Delete completed jobs.
	if job.complete then
		RemoveJob( job )
	end
	
	-- Pass to handler routing.
	OnDataReceived( job, dist, sender )
end

-------------------------------------------------------------------------------
-- This little bit is a method to stop the "player not found" system message
--  when accidentally sending to someone who is offline. Hopefully this works
--  for all locales.
local SYSTEM_PLAYER_NOT_FOUND_PATTERN = 
                              ERR_CHAT_PLAYER_NOT_FOUND_S:gsub( "%%s", "(.+)" )

-------------------------------------------------------------------------------
-- Suppress the offline message for this username for a short period.
function Comm.SuppressOfflineNotice( username )
	-- The table contains suppression expiration times.
	m_suppress_offline_message[username] = GetTime() + 5
end                    local SuppressOfflineNotice = Comm.SuppressOfflineNotice
		
-------------------------------------------------------------------------------
-- ChatFrame message filter for CHAT_MSG_SYSTEM.
function Comm.SystemChatFilter( self, event, text )
	local name = strmatch( text, SYSTEM_PLAYER_NOT_FOUND_PATTERN )
	if GetTime() < (m_suppress_offline_message[name] or 0) then
		return true
	end
end

-------------------------------------------------------------------------------
-- Callback for global chat throttler.
function Comm.OnJobSendComplete( job, success )
	if job.onsent then
		job.onsent( job )
	end
end                            local OnJobSendComplete = Comm.OnJobSendComplete

-------------------------------------------------------------------------------
-- One megafunction for taking data from a job and then putting it out on the
--  line. This reads one chunk/page from a job and then passes it along to the
--  WoW API (or the global chat throttler) to be sent.
-- `all` means this will recurse for jobs with multiple chunks queued, and
--  send them all, used for FAST and URGENT jobs (though that's a bad idea for
--   URGENT jobs as they don't use a throttler at all).
function Comm.DispatchPacket( job, all )
	-- Locals for optimization.
	local jobtype,  jobtext,  jobdest,  addonprefix = 
	      job.type, job.text, job.dest, job.prefix .. "+RP"
	local sendpos = job.send_position or 1
	
	-- While these two types are highly similar, there are still some serious
	--  differences between the two, so may as well just have things a little
	--                                   WET for more flexibility with nuances.
	if jobtype == "BNET" then
		-- BNET has a page value, ADDON does not.
		local sendpage = job.send_page or 1
		--job.send_position = job.send_position or 1
		--job.send_page = job.send_page or 1
		-- A lot of scary stuff in here, so I'll comment each bit
		-- `datapart` is the mark in the message header that signals what page
		--  is being received ("entirety", "first", "middle", or "last")
		--  encoded into a single char ("-", "<", "=", ">")
		local datapart
		
		-- `sendpos` is where we are reading next from the message. We read up
		--  to `MAX_BNET_SIZE` chars from the message for each chunk.
		-- `text_to_send` is the portion of the message that we are sending in
		--  this next chunk.
		local text_to_send = strsub( jobtext, sendpos,
		                                          sendpos + MAX_BNET_SIZE - 1 )
		-- `callback` is a flag that we are sending the last chunk (or the
		--  entire message in a single chunk), and signals that we should
		--  execute the `onsent` callback for the job when we're done putting
		--  this data out on the line.
		local callback
		sendpos = sendpos + #text_to_send
		-- `slotpage` is the slot and page together, to be inserted into the
		--  message header. This isn't present for single-chunk messages (reset
		--  below).
		local slotpage = PackNumber2( job.slot ) .. PackNumber2( sendpage )
		
		-- If this is the first page...
		if sendpage == 1 then
			if sendpos > #jobtext and job.complete then
				-- If `job.complete` is set, then we have all of the data to
				--  send available to us. If we have read it all
				--  `(sendpos > #text)`, and we're on the first page, then
				--  this is a single-chunk message. `datapart` for this is "-",
				--  and the slot and page are omitted.
				datapart = "-"
				slotpage = ""
				RemoveJob( job )
				callback = true -- Last chunk, trigger callback.
			else
				datapart = "<"
			end
		else
			if sendpos > #jobtext and job.complete then
				-- This is the last chunk that we just read, so delete the job
				--  and trigger the callback after we send it.
				datapart = ">"
				RemoveJob( job )
				callback = true
			else
				-- Middle of message `datapart`.
				datapart = "="
			end
		end
		
		-- Increment sending page and save value.
		job.send_page = sendpage + 1
		
		DebugLog2( "COMMSENDBN:", job.prefix, jobdest, text_to_send )
		
		text_to_send = PROTO_VERSION_STR .. datapart .. slotpage .. text_to_send
		-- Using Chomp as our chat throttler, which is shipped with all popular
		--  RP profile addons. If for some reason it isn't installed, then we 
		--  should still be okay, as most of our traffic is using LOW/NORMAL
		--                        priority and passes through our rate limiter.
		if AddOn_Chomp and not job.nothrottle then
			AddOn_Chomp.BNSendGameData( jobdest, addonprefix, text_to_send,
			         job.chomp_prio or "LOW", nil,
			         callback and OnJobSendComplete, callback and job )
		else
			-- For when there's no rate limiter, or we're priority "URGENT".
			BNSendGameData( jobdest, addonprefix, text_to_send )
			if callback then
				OnJobSendComplete( job, true )
			end
		end
		Me.AddTraffic( #text_to_send )
		
		-- Add message overhead per chunk we send.
		m_bandwidth = m_bandwidth - #text_to_send - m_send_overhead
		
	elseif jobtype == "ADDON" then

		local firstpage = sendpos == 1
		local slot = ""
		local header
		local text_to_send
		local callback
		
		-- Max length for a single-chunk message is 
		--  (255 - proto version - datamark)
		if firstpage and job.complete 
		                           and #jobtext < (254-#PROTO_VERSION_STR) then
			-- Can fit in one packet.
			header = PROTO_VERSION_STR .. "-"
			text_to_send = jobtext
			sendpos = sendpos + #text_to_send
			RemoveJob( job )
			callback = true
		else
			-- Max length for a multi-chunk message is
			--  255 - #proto_version - 1 (datamark) - 2 (slot) and then
			--  another -1 for inclusive range in string.sub.
			text_to_send = strsub( jobtext, sendpos, sendpos + (251-#PROTO_VERSION_STR) )
			sendpos = sendpos + #text_to_send
			slot = PackNumber2( job.slot )
			if firstpage then
				header = PROTO_VERSION_STR .. "<" .. slot
			else
				if sendpos > #jobtext and job.complete then
					-- Mark this as the last page, and the job can be deleted.
					header = PROTO_VERSION_STR .. ">" .. slot
					RemoveJob( job )
					callback = true
				else
					header = PROTO_VERSION_STR .. "=" .. slot
				end
			end
		end
		
		-- ADDON messages can go to three distribution types. "*" sends it to
		--  the Cross RP data channel (local). "P" sends it to the raid or
		--  party. Otherwise it's treated as a fullname and whispers a player.
		local dist, target
		if jobdest == "*" then
			dist   = "CHANNEL"
			target = GetChannelName( Me.data_channel )
		elseif jobdest == "P" then
			dist   = "RAID"
			target = nil
		else
			dist   = "WHISPER"
			target = jobdest
			SuppressOfflineNotice( jobdest )
		end
		
		DebugLog2( "COMMSEND:", job.prefix, dist, target, text_to_send )
		text_to_send = header .. text_to_send
		if AddOn_Chomp and not job.nothrottle then
			-- We'll play nice. :)
			-- Once everything goes through our rate limiter, we pass it to the
			--  global-level rate limiter (Chomp). If Chomp isn't installed,
			--  then the user has a funky setup, but we should be fine anyway,
			--                           as FAST priority messages are minimal.
			AddOn_Chomp.SendAddonMessage( addonprefix, text_to_send,
			                 dist, target, job.chomp_prio or "LOW", nil,
			                 callback and OnJobSendComplete, callback and job )
		else
			-- This is mainly for URGENT priority, unless the user doesn't have
			--  Chomp.
			C_ChatInfo.SendAddonMessage( addonprefix, text_to_send,
			                                                     dist, target )
			if callback then
				OnJobSendComplete( job, true )
			end
		end
		Me.AddTraffic( #text_to_send )
		
		-- Add message overhead per chunk we send.
		m_bandwidth = m_bandwidth - #text_to_send - m_send_overhead
	else
		error( "Unknown job type." )
	end
	
	job.send_position = sendpos
	
	if all and job.complete then
		if (sendpos or 1) <= #jobtext then
			return Comm.DispatchPacket( job, all )
		end
	end
end                                  local DispatchPacket = Comm.DispatchPacket

-------------------------------------------------------------------------------
-- The main routine function to dequeue pages of messages and put them out on
--  the line.
local m_comm_run_work_table = {}
local RUN_DELAY_TIME = 0.25
function Comm.Run()
	local time = GetTime()
	
	-- Ignore multiple calls in the same frame, and delay them to 0.25 seconds
	--  later.
	if m_last_run == time then 
		Me.Timer_Start( "comm_run", "ignore", RUN_DELAY_TIME, Comm.Run )
		return
	end
	
	-- Add new bandwidth. Time * `bps`, capped to `burst`.
	local delta = time - m_last_run
	m_bandwidth = min( m_bandwidth + delta * m_bps, m_burst )
	
	if m_bandwidth < RATE_LOW then
		-- We only start when we have enough bandwidth to send any message on
		--  the first round. A message can be larger than `bandwidth` and still
		--  be sent so long as `bandwidth` is above BPS (and it will dip
		--  negative to recover).
		Me.Timer_Start( "comm_run", "ignore", RUN_DELAY_TIME, Comm.Run )
		return
	end
	
	while true do
		-- Creating tables quickly can "churn" memory, so we use a static work
		--  table for here.
		local to_send = wipe( m_comm_run_work_table )
		
		-- For NORMAL priority, we keep track of the lowest serial, so we can
		--  send that before anything else. FAST and URGENT messages are not
		--  queued in here.
		local norm_prio_job = nil
		local norm_prio_serial = nil
		
		for k, v in pairs( m_jobs.send ) do
			local priority, complete = v.priority, v.complete
			if priority == "NORMAL" and complete then
				-- Once we find a NORMAL priority job, LOW priority jobs are
				--  ignored until the NORMAL queue is finished. We just need to
				--  find the lowest serial - that gets sent first.
				norm_prio_job = norm_prio_job or v
				norm_prio_serial = norm_prio_serial or v.serial
				if v.serial < norm_prio_serial then
					norm_prio_job = v
					norm_prio_serial = v.serial
				end
			elseif priority == "LOW" and (not norm_prio_job) then
				if #v.text >= SEND_BUFFER or complete then
					to_send[ #to_send+1 ] = v
				end
			else
				-- other priorities don't use the send queue.
			end
		end
		
		if not norm_prio_job and #to_send == 0 then
			-- Nothing queued.
			return
		end
		
		local job = norm_prio_job or to_send[ random( 1, #to_send ) ]
		if m_bandwidth >= m_bps or m_bandwidth >= #job.text then
			DispatchPacket( job )
		else
			-- delay for more bandwidth.
			Me.Timer_Start( "comm_run", "ignore", RUN_DELAY_TIME, Comm.Run )
			return
		end
	end
end                                                        local Run = Comm.Run

-------------------------------------------------------------------------------
-- Start the queue process on the next frame (leaving this frame open to
--  continue adding more data to send etc.).
function Comm.RunNextFrame()
	Me.Timer_Start( "comm_run", "ignore", 0.01, Run )
end                                      local RunNextFrame = Comm.RunNextFrame

-------------------------------------------------------------------------------
-- This is our API for registering a message handler.
-- `dist` is the distribution you want to listen to, which can be:
--  "BROADCAST"  Listen for messages from the data broadcast channel.
--  "WHISPER"    Listen for messages that are whispered to you (addonmsg).
--  "BNET"       Listen for messages that are whispered to you over Bnet.
--  "PARTY"      Listen for messages that are broadcast to your raid/party.
-- The "command" is the first word of any message, used to route the message
--  to a handler.
-- `handler` has the signature( job, sender ).
-- `job` is the job object. `sender` is the source, which can be a bnet game
--  account ID for "BNET" messages, or a fullname for "WHISPER" and "PARTY" and
--  "BROADCAST" messages.
-- Both `dist` and `command` can be tables, which will route all entries in
--  those tables to the handler.
function Comm.SetMessageHandler( dist, command, handler )
	-- bnet, direct, broadcast, party
	if type( dist ) == "table" then
		for k, v in pairs( dist ) do
			Comm.SetMessageHandler( v, command, handler )
		end
	else
		if type( command ) == "table" then
			for k, v in pairs( command ) do
				Comm.SetMessageHandler( dist, v, handler )
			end
		else
			m_handlers[dist:upper()][command] = handler
		end
	end
end

