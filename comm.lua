-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- The low-level communications layer.
-------------------------------------------------------------------------------
local _, Me = ...

local RATE_LOW      = 200
local RATE_FULL     = 1000
local SEND_BUFFER   = 300
local MAX_BNET_SIZE = 400

-------------------------------------------------------------------------------
local Comm = {
	next_slot = 0;
	next_serial = 1;
	jobs = {
		send = {};
		recv = {};
	};
	
	last_run      = GetTime();
	bps           = RATE_LOW;
	burst         = RATE_LOW * 1.25;
	bandwidth     = 0;
	PROTO_VERSION = 1;
	send_overhead = 10;
	
	handlers = {
		BROADCAST = {};
		BNET      = {};
		WHISPER   = {};
		PARTY     = {};
	}
	
	-- priorities
	-- LOW: default prio, sent out of order
	-- NORMAL: for our direct traffic, sent in order and pause LOW queue
	-- FAST: sent in order instantly, bypasses our rate limiter
	-- URGENT: sent in order instantly and bypasses the global rate limiter
	--        (should be small messages)
	
	
}
Me.Comm = Comm

Comm.Job = {}

function Comm.Job.New( slot, type, dest )
	local job = setmetatable( {
		slot     = slot;
		time     = GetTime();
		type     = type;
		dest     = dest;
		complete = false;
		text     = "";
		prefix   = "";
		serial   = Comm.next_serial;
		priority = "NORMAL";
		pages_waiting = nil;
		next_page = 1;
		last_page = nil;
	}, {
		__index = Comm.Job;
	})
	
	Comm.next_serial = Comm.next_serial + 1
	
	return job
end

function Comm.Job:Reset()
	self.time      = GetTime()
	self.complete  = false
	self.text      = ""
	self.next_page = 1
	self.lage_page = nil
	if self.pages_waiting then
		wipe(self.pages_waiting)
	end
end

function Comm.Job:TryDispatch()
	if self.cancel_send or not self.sender then return end
	
	if self.priority == "FAST" then
		Comm.DispatchPacket( self, true )
	elseif self.priority == "URGENT" then
		self.nothrottle = true
		Comm.DispatchPacket( self, true )
	else
		Comm.RunNextFrame()
	end
end

-------------------------------------------------------------------------------
function Comm.Job:AddPage( index, is_last, text )
	if self.next_page > index then
		Comm.Job.Reset( self )
	end
	
	if self.complete then
		error( "Job is already complete." )
	end
	
	local new_data = false
	
	if is_last then
		self.last_page = index
	end
	
	if self.next_page == index then
		self.text = self.text .. text
		self.next_page = self.next_page + 1
		while self.pages_waiting and self.pages_waiting[self.next_page] do
			self.text = self.text .. self.pages_waiting[self.next_page]
			self.pages_waiting[self.next_page] = nil
			self.next_page = self.next_page + 1
		end
		new_data = true
	else
		self.pages_waiting = self.pages_waiting or {}
		self.pages_waiting[index] = text
	end
	
	if self.last_page and self.next_page > self.last_page then
		self.complete = true
	end
	
	self:TryDispatch()
	
	return new_data
end

-------------------------------------------------------------------------------
function Comm.Job:CancelSend()
	self.cancel_send = true
	Comm.RemoveJob( self )
end

-------------------------------------------------------------------------------
function Comm.Job:AddText( complete, text )
	if self.complete then
		error( "Job is already complete." )
	end
	self.time     = GetTime()
	self.text     = self.text .. text
	self.complete = complete
	
	self:TryDispatch()
end

-------------------------------------------------------------------------------
function Comm.Job:SetPriority( priority )
	self.priority = priority
end

-------------------------------------------------------------------------------
function Comm.Job:SetPrefix( prefix )
	self.prefix = prefix or ""
end

-------------------------------------------------------------------------------
function Comm.CancelSendByTag( tag )
	for k, v in pairs( Comm.jobs.send ) do
		if v.tags and v.tags[tag] then
			-- careful here because this modifies the list we're iterating over
			v:CancelSend()
		end
	end
end

-------------------------------------------------------------------------------
function Comm.GetJob( list, slot, type, dest )
	local job = Comm.jobs[list][slot]
	if job then
		if job.type ~= type or job.dest ~= dest then
			error( "Debug: Logic error." )
		end
		if GetTime() < job.time + 5*60 then
			return job
		else
			-- this job timed out. make a new one
		end
	end
	
	job = Comm.Job.New( slot, type, dest )
	job.list = list
	
	Comm.jobs[list][slot] = job
	return Comm.jobs[list][slot]
end
-------------------------------------------------------------------------------
function Comm.RemoveJob( job )
	if job.list then
		Comm.jobs[job.list][job.slot] = nil
		job.list = nil
	end
end
-------------------------------------------------------------------------------
function Comm.GetNextSlot()
	local slot = Comm.next_slot
	Comm.next_slot = (Comm.next_slot + 1) % (127*127)
	return slot
end

-------------------------------------------------------------------------------
function Comm.SendBnetPacket( game_account_id, slot, complete, text, prefix, priority )
	slot = slot or Comm.GetNextSlot()
	
	local job = Comm.GetJob( "send", slot, "BNET", game_account_id )
	job.sender   = true
	if prefix then job.prefix = prefix end
	if priority then job.priority = priority end
	
	if text then
		job:AddText( complete, text )
	end
	return job
end

-------------------------------------------------------------------------------
function Comm.SendBnetPacketPaged( game_account_id, slot, page, is_last, text, prefix, priority )
	slot = slot or Comm.GetNextSlot()
	
	local job = Comm.GetJob( "send", slot, "BNET", game_account_id )
	job.sender  = true
	if prefix then job.prefix = prefix end
	if priority then job.priority = priority end
	
	if text then
		job:AddPage( page, is_last, text )
	end
	return job
end

-------------------------------------------------------------------------------
function Comm.SendAddonPacket( target, slot, complete, text, prefix, priority )
	slot = slot or Comm.GetNextSlot()
	
	local job = Comm.GetJob( "send", slot, "ADDON", target )
	job.sender   = true
	if prefix then job.prefix = prefix end
	if priority then job.priority = priority end
	
	if text then
		job:AddText( complete, text )
	end
	return job
end

-------------------------------------------------------------------------------
function Comm.SendSMF( target, text, ... )
	if select( "#", ... ) > 0 then
		text = text:format( ... )
	end
	Comm.SendAddonPacket( target, nil, true, text, nil, "FAST" )
end

-------------------------------------------------------------------------------
function Comm.PackNumber2( number )
	return string.char( 1 + math.floor( number / 127 ), 1 + (number % 127) )
end

-------------------------------------------------------------------------------
function Comm.UnpackNumber2( text )
	return (text:byte(1) - 1) * 127 + (text:byte(2) - 1)
end

-------------------------------------------------------------------------------
function Comm.OnBnChatMsgAddon( event, prefix, message, _, sender )
	local crp_prefix, valid = prefix:match( "(.*)(%+RP)" )
	if not valid then return end
	
	local proto, part, rest = message:match( "([0-9]+)([<=>%-])(.*)" )
	if not proto then 
		Me.DebugLog( "Invalid BNET message from %s.", sender )
		return
	end
	if tonumber(proto) ~= Comm.PROTO_VERSION then
		Me.DebugLog( "Protocol version mismatch from %s.", sender )
	end
	
	if part == "-" then
		-- complete message.
		local job = Comm.Job.New( "temp", "BNET" )
		job:AddText( true, rest )
		job.firstpage = true
		job.prefix = crp_prefix
		Comm.OnDataReceived( job, "WHISPER", sender )
		return
	end
	
	local slot, page = Comm.UnpackNumber2(rest:sub( 1, 2 )), 
	                   Comm.UnpackNumber2(rest:sub( 3, 4 ))
	slot = sender .. "-" .. slot
	
	local job = Comm.GetJob( "recv", slot, "BNET" )
	job.prefix = crp_prefix
	local new_data = false
	if part == "<" then
		-- first page
		new_data = job:AddPage( page, false, rest:sub(5) )
		job.firstpage = true
	elseif part == "=" then
		-- middle page
		new_data = job:AddPage( page, false, rest:sub(5) )
		job.firstpage = false
	elseif part == ">" then
		-- last page
		new_data = job:AddPage( page, true, rest:sub(5) )
		job.firstpage = false
	end
	
	if job.complete then
		Comm.RemoveJob( job )
	end
	Comm.OnDataReceived( job, "WHISPER", sender )
end

function Comm.OnChatMsgAddon( event, prefix, message, dist, sender )
	local crp_prefix, valid = prefix:match( "(.*)(%+RP)" )
	if not valid then return end
	
	local proto, part, rest = message:match( "([0-9]+)([<=>%-])(.*)" )
	if not proto then 
		Me.DebugLog( "Invalid ADDON message from %s.", sender )
		return
	end
	if tonumber(proto) ~= Comm.PROTO_VERSION then
		Me.DebugLog( "Protocol version mismatch from %s.", sender )
	end
	
	if part == "-" then
		local job = Comm.Job.New( "temp", "ADDON" )
		job:AddText( true, rest )
		job.firstpage = true
		job.prefix = crp_prefix
		Comm.OnDataReceived( job, dist, sender )
		return
	end
	
	local slot = Comm.UnpackNumber2(rest:sub( 1, 2 ))
	slot = sender .. "-" .. slot
	
	local job = Comm.GetJob( "recv", slot, "ADDON" )
	job.prefix = crp_prefix
	if part == "<" then
		-- first page
		job:Reset()
		job:AddText( false, rest:sub(3) )
		job.firstpage = true
	elseif part == "=" then
		-- middle page
		job:AddText( false, rest:sub(3) )
		job.firstpage = false
	elseif part == ">" then
		-- last page
		job:AddText( true, rest:sub(3) )
		job.firstpage = false
	end
	
	
	if job.complete then
		Comm.RemoveJob( job )
	end
	Comm.OnDataReceived( job, dist, sender )
end

function Comm.RunNextFrame()
	Me.Timer_Start( "comm_run", "ignore", 0.01, Comm.Run )
end

function Comm.Run()
		
	if Comm.last_run == GetTime() then 
		Me.Timer_Start( "comm_run", "ignore", 0.25, Comm.Run )
		return
	end
	
	local delta = GetTime() - Comm.last_run
	Comm.bandwidth = math.min( Comm.bandwidth + delta * Comm.bps, Comm.burst )

	if Comm.bandwidth < RATE_LOW then
		-- we only start when we have above bps to send any message
		-- we find on the first round.
		Me.Timer_Start( "comm_run", "ignore", 0.25, Comm.Run )
		return
	end
	
	while true do
		local to_send = {}
		local norm_prio_packet = nil
		local norm_prio_serial = nil
		
		for k, v in pairs( Comm.jobs.send ) do
			if v.priority == "NORMAL" and v.complete then
				norm_prio_packet = norm_prio_packet or v
				norm_prio_serial = norm_prio_serial or v.serial
				if v.serial < norm_prio_serial then
					norm_prio_packet = v
					norm_prio_serial = v.serial
				end
			elseif v.priority == "LOW" and (not norm_prio_packet) then
				if #v.text >= SEND_BUFFER or v.complete then
					table.insert( to_send, v )
				end
			else
				-- other priorities don't use the send queue.
			end
		end
		
		if not norm_prio_packet and #to_send == 0 then
			-- Nothing queued.
			return
		end
		
		local job = norm_prio_packet or to_send[ math.random( 1, #to_send ) ]
		if Comm.bandwidth >= Comm.bps or Comm.bandwidth >= #job.text then
			Comm.DispatchPacket( job )
		else
			-- delay for more bandwidth.
			Me.Timer_Start( "comm_run", "ignore", 0.25, Comm.Run )
			return
		end
	end
end

function Comm.DispatchPacket( job, all )
	Comm.bandwidth = Comm.bandwidth - #job.text - Comm.send_overhead
	if job.type == "BNET" then
		job.send_position = job.send_position or 1
		job.send_page = job.send_page or 1
		local datapart = "-" -- entire data
		local slotpage = ""
		local text_to_send = job.text:sub( job.send_position, job.send_position+MAX_BNET_SIZE-1 )
		job.send_position = job.send_position + #text_to_send
		slotpage = Comm.PackNumber2( job.slot ) .. Comm.PackNumber2( job.send_page )
		
		if job.send_page == 1 then
			if job.send_position > #job.text and job.complete then
				slotpage = ""
				Comm.RemoveJob( job )
			else
				datapart = "<"
			end
		else
			if job.send_position > #job.text and job.complete then
				datapart = ">"
				Comm.RemoveJob( job )
			else
				datapart = "="
			end
		end
		job.send_page = job.send_page + 1
		
		if AddOn_Chomp and not job.nothrottle then
			-- todo: normal prio should use normal prio.
			AddOn_Chomp.BNSendGameData( job.dest, job.prefix .. "+RP", Comm.PROTO_VERSION .. datapart 
											.. slotpage .. text_to_send, job.prio or "LOW" )
		else
			BNSendGameData( job.dest, job.prefix .. "+RP", Comm.PROTO_VERSION .. datapart 
											.. slotpage .. text_to_send )
		end
	elseif job.type == "ADDON" then

		job.send_position = job.send_position or 1
		local firstpage = job.send_position == 1
		local slot = ""
		local header = tostring(Comm.PROTO_VERSION)
		local text_to_send
		if firstpage and job.complete and #job.text < (255-#header-1) then
			-- can fit in one packet
			text_to_send = job.text
			job.send_position = job.send_position + #text_to_send
			header = header .. "-"
			Comm.RemoveJob( job )
		else
			-- 255 = max message length, minus header, minus mark, minus page, minus 1 for inclusive range
			text_to_send = job.text:sub( job.send_position, job.send_position+(255-#header-1-2-1) )
			job.send_position = job.send_position + #text_to_send
			slot = Comm.PackNumber2( job.slot )
			if firstpage then
				header = header .. "<" .. slot
			else
				if job.send_position > #job.text and job.complete then
					header = header .. ">" .. slot
					Comm.RemoveJob( job )
				else
					header = header .. "=" .. slot
				end
			end
		end
		local dist, target
		if job.dest == "*" then
			dist   = "CHANNEL"
			target = GetChannelName( Me.Proto.channel_name )
		elseif job.dest == "P" then
			dist   = "RAID"
			target = nil
		else
			dist = "WHISPER"
			target = job.dest
		end
		
		if AddOn_Chomp and not job.nothrottle then
			-- we'll play nice :)
			-- todo: normal prio should use normal prio.
			AddOn_Chomp.SendAddonMessage( job.prefix .. "+RP", header .. text_to_send, dist, target, "LOW" )
		else
			C_ChatInfo.SendAddonMessage( job.prefix .. "+RP", header .. text_to_send, dist, target )
		end
	else
		error( "Unknown job type." )
	end
	
	if all and job.complete then
		if (job.send_position or 1) <= #job.text then
			Comm.DispatchPacket( job, all )
		end
	end
end

function Comm.SetMessageHandler( dist, command, handler )
	-- bnet, direct, broadcast, party
	if type(dist) == "table" then
		for k, v in pairs( dist ) do
			Comm.SetMessageHandler( v, command, handler )
		end
	else
		if type(command) == "table" then
			for k, v in pairs( command ) do
				Comm.SetMessageHandler( dist, v, handler )
			end
		else
			Comm.handlers[dist:upper()][command] = handler
		end
	end
end

function Comm.OnDataReceived( job, dist, sender )
	if job.proto_abort then return end
	Me.DebugLog2( "DATA RECEIVED", job.prefix, job.type, job.complete and "COMPLETE" or "PROGRESS", sender, job.text )
	
	if job.firstpage then
		local command = job.text:match( "^(%S+)" )
		if not command then
			job.proto_abort = true
			return
		end
		job.command = command
	end
	
	local handler_result
	if job.type == "BNET" then
		local handler = Comm.handlers.BNET[job.command]
		if handler then
			handler_result = handler( job, sender )
		else
			Me.DebugLog( "[Comm] Couldn't find handler for '%s' (BNET).", job.command )
		end
	elseif job.type == "ADDON" then
		if dist == "CHANNEL" then
			local handler = Comm.handlers.BROADCAST[job.command]
			if handler then
				handler_result = handler( job, sender )
			else
				Me.DebugLog( "[Comm] Couldn't find handler for '%s' (BROADCAST).", job.command )
			end
		elseif dist == "RAID" or dist == "PARTY" then
			local handler = Comm.handlers.PARTY[job.command]
			if handler then
				handler_result = handler( job, sender )
			else
				Me.DebugLog( "[Comm] Couldn't find handler for '%s' (PARTY).", job.command )
			end
		elseif dist == "WHISPER" then
			local handler = Comm.handlers.WHISPER[job.command]
			if handler then
				handler_result = handler( job, sender )
			else
				Me.DebugLog( "[Comm] Couldn't find handler for '%s' (WHISPER).", job.command )
			end
		end
	end
	
	if handler_result == false then
		job.proto_abort = true
	end
end
