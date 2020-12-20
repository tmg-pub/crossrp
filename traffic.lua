-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- A traffic monitor.
-------------------------------------------------------------------------------
local _, Me = ...
local L = Me.Locale

-------------------------------------------------------------------------------
-- The size of our measurement window, in seconds. This is how many entries
--  are in our data buffer. Each entry contains the amount of traffic received
--  in that second of time.
local WINDOW_SIZE = 60
-------------------------------------------------------------------------------
-- One of the best things about scripting languages, is that you can initialize
--      data with the script itself. `m_traffic_data` is a sort of ring buffer.
local m_traffic_data = {}
for i = 1, WINDOW_SIZE do
	m_traffic_data[i] = 0
end
local m_traffic_compiled = 0
local m_traffic_smooth   = 0
local SMOOTH_RATE = 1.0
-------------------------------------------------------------------------------
-- The position that we are next writing to in the traffic buffer. Every one
--  second this is incremented, but we aren't using any sort of timer
--  callbacks for that, we're just using the game time since the last call to
--  move this position along. `update_time` is the game time of our last
--  update. `elapsed_leftover` is how much we should add to that to accommodate
--  for any fractional seconds that we didn't use on the last pass.
m_write            = 1
m_update_time      = 0
m_elapsed_leftover = 0

-------------------------------------------------------------------------------
-- Call this before accessing the buffers, to update the write position and
--  empty the buffer over time.
--
local function PrepareUpdate( bytes_to_add )
	bytes_to_add = bytes_to_add or 0
	
	-- GameTime() doesn't change in the same frame, so this check will disable
	--  additional function calls to this in the same frame. A nice shortcut!
	if m_update_time == GetTime() then return end
	
	-- We're going to advance this many spaces in the buffer, the integer
	--  part of elapsed. Any leftover is saved into `elapsed_leftover` for the
	--  next pass.
	local elapsed = GetTime() - m_update_time + m_elapsed_leftover
	m_update_time = GetTime()
	
	if elapsed >= WINDOW_SIZE then
		-- If we've gone all the way past the window size since an update call
		--  we just reset everything, effectively what will happen anyway
		--  without the excess load of iterating over each second.
		for i = 1, WINDOW_SIZE do
			m_traffic_data[i] = 0
		end
		m_write = 1
		m_elapsed_leftover = 0
		return
	end
	
	local smooth_move = elapsed * SMOOTH_RATE
	
	-- Under normal conditions if we're reading the traffic often, this loop
	--  should only run up to one times, to advance to the next space. In
	--  low traffic situations without anything polling the traffic though,
	--  this will usually advance several spaces. Each second passed advances
	--  one space in the buffer. Maybe that period should be adjusted to
	--  500ms or something?
	while elapsed >= 1.0 do
		elapsed = elapsed - 1.0
		m_write = m_write + 1
		if m_write >= WINDOW_SIZE+1 then m_write = 1 end
		m_traffic_data[m_write] = 0
	end
	m_elapsed_leftover = elapsed
	
	local sum = 0
	for _, v in ipairs( m_traffic_data ) do
		sum = sum + v
	end
	local avg = (sum + bytes_to_add) / WINDOW_SIZE
	m_traffic_compiled = avg
	
	if m_traffic_smooth < m_traffic_compiled then
		m_traffic_smooth = math.min( m_traffic_smooth + smooth_move, 
		                                                   m_traffic_compiled )
	else
		m_traffic_smooth = math.max( m_traffic_smooth - smooth_move,
		                                                   m_traffic_compiled )
	end
end

-------------------------------------------------------------------------------
-- Call whenever your receive data to record it into our buffer.
--
function Me.AddTraffic( bytes )
	PrepareUpdate( bytes )
	m_traffic_data[m_write] = m_traffic_data[m_write] + bytes
end

-------------------------------------------------------------------------------
-- Returns bytes/sec the relay channel is using.
--
function Me.GetTraffic()
	PrepareUpdate( 0 )
	return m_traffic_compiled
end

-------------------------------------------------------------------------------
-- Returns bytes/sec but this value changes slowly over time.
--
function Me.GetTrafficSmooth()
	PrepareUpdate( 0 )
	return m_traffic_smooth
end

-------------------------------------------------------------------------------
-- Returns a formatted string for the user of incoming traffic.
-- e.g. "352 B/s" if under 1000
--  or "1.53 KB/s"
--
function Me.GetTrafficFormatted( smooth )
	local sum
	if smooth then
		sum = Me.GetTrafficSmooth()
	else
		sum = Me.GetTraffic()
	end
	if sum >= 1000 then
		return string.format( "%.2f %s", sum/1000, L.KBPS )
	else
		return string.format( "%d %s", sum, L.BPS )
	end
end
