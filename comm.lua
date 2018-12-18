-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- The low-level communications layer.
-------------------------------------------------------------------------------
local _, Me = ...

local RATE_THROTTLED = 200
local RATE_FULL      = 1000
local SEND_BUFFER    = 300
local MAX_BNET_SIZE  = 400

-------------------------------------------------------------------------------
local Comm = {
	next_slot = 0;
	jobs = {
		send = {};
		recv = {};
	};
	
	last_run      = GetTime();
	bps           = RATE_THROTTLED;
	burst         = RATE_THROTTLED * 1.25;
	bandwidth     = 0;
	PROTO_VERSION = 1;
	send_overhead = 10;
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
		pages_waiting = {};
		next_page = 1;
		last_page = nil;
	}, {
		__index = Comm.Job;
	})
	
	return job
end

function Comm.Job:Reset()
	self.time      = GetTime()
	self.complete  = false
	self.text      = ""
	self.next_page = 1
	self.lage_page = nil
	wipe(self.pages_waiting)
end

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
		while self.pages_waiting[self.next_page] do
			self.text = self.text .. self.pages_waiting[self.next_page]
			self.pages_waiting[self.next_page] = nil
			self.next_page = self.next_page + 1
		end
		new_data = true
	else
		self.pages_waiting[index] = text
	end
	
	if self.last_page and self.next_page > self.last_page then
		self.complete = true
	end
	
	if self.sender then
		Comm.RunNextFrame()
	end
	
	return new_data
end

-------------------------------------------------------------------------------
function Comm.Job:AddText( complete, text )
	if self.complete then
		error( "Job is already complete." )
	end
	self.time     = GetTime()
	self.text     = self.text .. text
	self.complete = complete
	
	if self.sender then
		Comm.RunNextFrame()
	end
end

-------------------------------------------------------------------------------
function Comm.GetJob( direction, slot, type, dest )
	local job = Comm.jobs[direction][slot]
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
	
	Comm.jobs[direction][slot] = Comm.Job.New( slot, type, dest )
	return Comm.jobs[direction][slot]
end

function Comm.RemoveJob( direction, job )
	Comm.jobs[direction][job.slot] = nil
end

function Comm.GetNextSlot()
	local slot = Comm.next_slot
	Comm.next_slot = (Comm.next_slot + 1) % (127*127)
	return slot
end

-------------------------------------------------------------------------------
function Comm.SendBnetPacket( game_account_id, slot, complete, text )
	slot = slot or Comm.GetNextSlot()
	
	local job = Comm.GetJob( "send", slot, "BNET", game_account_id )
	job.sender = true
	if text then
		job:AddText( complete, text )
	end
	return job
end

-------------------------------------------------------------------------------
function Comm.SendBnetPacketPaged( game_account_id, slot, page, is_last, text )
	slot = slot or Comm.GetNextSlot()
	
	local job = Comm.GetJob( "send", slot, "BNET", game_account_id )
	job.sender = true
	if text then
		job:AddPage( page, is_last, text )
	end
	return job
end

-------------------------------------------------------------------------------
function Comm.SendAddonPacket( target, slot, complete, text )
	slot = slot or Comm.GetNextSlot()
	
	local job = Comm.GetJob( "send", slot, "ADDON", target )
	job.sender = true
	if text then
		job:AddText( complete, text )
	end
	return job
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
	if prefix ~= "+RP" then return end
	
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
		Me.Proto.OnDataReceived( job, "WHISPER", sender )
		return
	end
	
	local slot, page = Comm.UnpackNumber2(rest:sub( 1, 2 )), 
	                   Comm.UnpackNumber2(rest:sub( 3, 4 ))
	slot = sender .. "-" .. slot
	
	local job = Comm.GetJob( "recv", slot, "BNET" )
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
		Comm.RemoveJob( "recv", job )
	end
	Me.Proto.OnDataReceived( job, "WHISPER", sender )
end

function Comm.OnChatMsgAddon( event, prefix, message, dist, sender )
	if prefix ~= "+RP" then return end
	--Me.DebugLog2( "ADDONMSG:", message, dist, sender )
	
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
		Me.Proto.OnDataReceived( job, dist, sender )
		return
	end
	
	local slot = Comm.UnpackNumber2(rest:sub( 1, 2 ))
	slot = sender .. "-" .. slot
	
	local job = Comm.GetJob( "recv", slot, "ADDON" )
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
		Comm.RemoveJob( "recv", job )
	end
	Me.Proto.OnDataReceived( job, dist, sender )
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

	if Comm.bandwidth < Comm.bps then
		-- we only start when we have above bps to send any message
		-- we find on the first round.
		Me.Timer_Start( "comm_run", "ignore", 0.25, Comm.Run )
		return
	end
	
	while true do
		local to_send = {}
		
		for k, v in pairs( Comm.jobs.send ) do
			if #v.text >= SEND_BUFFER or v.complete then
				table.insert( to_send, v )
			end
		end
		
		if #to_send == 0 then
			-- Nothing queued.
			return
		end
		
		local job = to_send[ math.random( 1, #to_send ) ]
		if Comm.bandwidth >= Comm.bps or Comm.bandwidth >= #job.text then
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
						Comm.RemoveJob( "send", job )
					else
						datapart = "<"
					end
				else
					if job.send_position > #job.text and job.complete then
						datapart = ">"
						Comm.RemoveJob( "send", job )
					else
						datapart = "="
					end
				end
				job.send_page = job.send_page + 1
				
				if AddOn_Chomp then
					AddOn_Chomp.BNSendGameData( job.dest, "+RP", Comm.PROTO_VERSION .. datapart 
													.. slotpage .. text_to_send, job.prio or "LOW" )
				else
					BNSendGameData( job.dest, "+RP", Comm.PROTO_VERSION .. datapart 
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
					header = header .. "-"
					Comm.RemoveJob( "send", job )
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
							Comm.RemoveJob( "send", job )
						else
							header = header .. "=" .. slot
						end
					end
				end
				local dist, target
				if job.dest == "*" then
					dist   = "CHANNEL"
					target = GetChannelName( Me.Proto.channel_name )
				else
					dist = "WHISPER"
					target = job.dest
				end
				
				if AddOn_Chomp then
					-- we'll play nice :)
					AddOn_Chomp.SendAddonMessage( "+RP", header .. text_to_send, dist, target, "LOW" )
				else
					C_ChatInfo.SendAddonMessage( "+RP", header .. text_to_send, dist, target )
				end
			else
				error( "Unknown job type." )
			end
		else
			-- delay for more bandwidth.
			Me.Timer_Start( "comm_run", "ignore", 0.25, Comm.Run )
			return
		end
	end
end
