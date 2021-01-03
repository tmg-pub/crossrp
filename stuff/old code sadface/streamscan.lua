-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- Stream scanner.
-------------------------------------------------------------------------------
local _, Me = ...

local m_scanning
local m_oldest_message
local m_club
local m_stream
local m_start_time
local m_end_time
local m_waiting_for_messages
local m_callback
local m_frame
local m_last_report_percent
local REQUEST_LINES = 400

-------------------------------------------------------------------------------
local function RangeIsEmpty( range )
	return range.newestMessageId.epoch < range.oldestMessageId.epoch 
	   or (range.newestMessageId.epoch == range.oldestMessageId.epoch 
		   and range.newestMessageId.position < range.oldestMessageId.position)
end

-------------------------------------------------------------------------------
local function MessageEqual( m1, m2 )
	return m1.epoch == m2.epoch and m1.position == m2.position
end

-------------------------------------------------------------------------------
local function ContinueScan()
	Me.Timer_Cancel( "streamscan_retry" )
	
	m_waiting_for_messages = false
	
	local fresh = false
	if m_oldest_message == nil then
		local ranges = C_Club.GetMessageRanges( m_club, m_stream );
		if not ranges or #ranges == 0 then
			-- Don't have any messages...?
			m_scanning = false
			m_callback( "FAILED", m_club, m_stream )
			return
		end
		local range = ranges[#ranges]
		
		m_oldest_message = range.newestMessageId
		if m_oldest_message.epoch < range.oldestMessageId.epoch then
			-- Something is wrong?
			-- This boilerplate shit needed is dumb.
			m_scanning = false
			m_callback( "FAILED", m_club, m_stream )
			return
		end
		
		m_callback( "STARTED", m_club, m_stream )
		fresh = true
	end
	
	local messages = C_Club.GetMessagesBefore( m_club, m_stream, 
	                                          m_oldest_message, 1000 )
	local last = #messages
	if not fresh 
	         and MessageEqual( messages[last].messageId, m_oldest_message) then
		last = last - 1
	end
	
	if last > 0 then
		local nperiod = (m_end_time - m_start_time)
		local percent = (m_end_time - messages[1].messageId.epoch/1000000) / nperiod
		percent = math.min( math.floor(percent * 100), 100 )
		percent = math.max( percent, 0 )
		percent = 100-percent
		
		if percent >= m_next_report_percent then
			Me.Print( "Scanning stream... (%d%%)", percent )
			m_next_report_percent = (math.floor(percent / 5) + 1) * 5
		end
		
		for i = last, 1, -1 do
			m_callback( "MESSAGE", m_club, m_stream, messages[i] )
		end
	end
	
	m_oldest_message = messages[1].messageId
	local pos = m_oldest_message.epoch/1000000
	
	if C_Club.IsBeginningOfStream( m_club, m_stream, m_oldest_message ) 
	                                                  or pos <= m_end_time then
		m_scanning = false
		m_callback( "COMPLETE", m_club, m_stream )
		return
	end
	
	local has_messages = C_Club.RequestMoreMessagesBefore( m_club, m_stream, 
	                                          m_oldest_message, REQUEST_LINES )
	if has_messages then
		-- A tiny delay so we don't freeze the game up.
		C_Timer.After( 0.01, ContinueScan )
	else
		Me.Timer_Start( "streamscan_retry", "push", 8.0, ContinueScan )
		m_waiting_for_messages = true
	end
end

-------------------------------------------------------------------------------
local function SetupEventListener()
	if m_event_registered then return end
	m_event_registered = true
	
	Me:RegisterEvent( "CLUB_MESSAGE_HISTORY_RECEIVED", function( event, ... )
		if not m_scanning then return end
		local clubId, streamId, downloadedRange, contiguousRange = ...;
		if clubId == m_club and streamId == m_stream then
			Me.Timer_Start( "streamscan_retry", "push", 1.0, ContinueScan )
		end
	end)
end

-------------------------------------------------------------------------------
function Me.ScanStreamHistory( club, stream, period, callback )
	if m_scanning then
		Me.Print( "Scan in progress!" )
		return false
	end
	
	SetupEventListener()
	
	m_scanning            = true
	m_oldest_message      = nil
	m_club                = club
	m_stream              = stream
	m_start_time          = time()
	m_end_time            = m_start_time - period
	m_callback            = callback
	m_next_report_percent = 0
	
	local ranges = C_Club.GetMessageRanges( m_club, m_stream )
	if not ranges or #ranges == 0 or RangeIsEmpty(ranges[#ranges]) then
		m_waiting_for_messages = true
		C_Club.RequestMoreMessagesBefore( m_club, m_stream, nil)
		return true
	end
	
	C_Timer.After( 0.01, ContinueScan )
	return true
end

-------------------------------------------------------------------------------
do
-------------------------------------------------------------------------------
local m_active_time = {}
local m_scan_time = 0

local function ShowResults( club, stream )
	local members = {}
	local active_past_day = 0
	local active_past_week = 0
	for _, v in pairs( C_Club.GetClubMembers( club, stream ) ) do
		local mi = C_Club.GetMemberInfo( club, v )
		local active_time = m_active_time[mi.memberId] or 0;
		
		local period = m_scan_time - active_time
		local day = math.floor(period / (60*60*24))
		day = math.min( day, 7 )
		
		if period < 60*60*24 then
			active_past_day = active_past_day + 1
		end
		
		if period < 60*60*24*7 then
			active_past_week = active_past_week + 1
		end
		members[day] = members[day] or {}
		table.insert( members[day], {
			active = active_time;
			name   = mi.name;
		})
	end
	
	Me.Print( "Members active in the past 24 hours: %d", active_past_day )
	Me.Print( "Members active in the past week: %d", active_past_week )
	
	for day = 0, 7 do
		local memberset = members[day]
		if memberset then
			table.sort( memberset, function( a, b ) 
				return a.active > b.active 
			end)
			
			if day == 7 then
				Me.Print( "|cffff4000Not active in the past week:" )
			elseif day >= 1 then
				Me.Print( "|cffffff10Active in the past %d days:", day+1 )
			else
				Me.Print( "|cff10ff10Active in the last 24 hours:" )
			end
			
			local text = ""
			for _, member in ipairs( memberset ) do
				if text ~= "" then
					text = text .. ", "
				end
				text = text .. member.name
				if #text > 800 then
					print( text )
					text = ""
				end
			end
			print( text )
		end
	end
end

local function ScanActiveCallback( event, club, stream, message )
	if event == "STARTED" then
		wipe( m_active_time )
	elseif event == "MESSAGE" then
		if not m_active_time[message.author.memberId] then
			local unixtime = math.floor(message.messageId.epoch / 1000000)
			m_active_time[message.author.memberId] = unixtime
		end
	elseif event == "COMPLETE" then
		ShowResults( club, stream )
	end
end

-------------------------------------------------------------------------------
SlashCmdList.SCANACTIVE = function( msg )
	if not Me.connected then
		Me.Print( "Not connected." )
		return
	end
	if Me.GetRole() > 2 then
		Me.Print( "This command is for Leaders only." )
		return
	end
	m_scan_time = time()
	Me.ScanStreamHistory( Me.club, Me.stream, 60*60*24*7, ScanActiveCallback )
end

-------------------------------------------------------------------------------
SLASH_SCANACTIVE1 = "/scanactive"

-------------------------------------------------------------------------------
end
-------------------------------------------------------------------------------
