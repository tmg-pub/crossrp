-- Traffic monitor

local _, Me = ...
local L = Me.Locale
local WINDOW_SIZE = 10 -- seconds

local m_traffic_data = {}
for i = 1, WINDOW_SIZE do
	m_traffic_data[i] = 0
end
m_write = 1
m_update_time = 0
m_elapsed_leftover = 0

local function PrepareUpdate()
	if m_update_time == GetTime() then return end -- up to date
	
	local elapsed = GetTime() - m_update_time + m_elapsed_leftover
	m_update_time = GetTime()
	
	if elapsed >= WINDOW_SIZE then
		-- reset
		for i = 1, WINDOW_SIZE do
			m_traffic_data[i] = 0
		end
		m_write = 1
		m_elapsed_leftover = 0
		return
	end
	
	while elapsed >= 1.0 do
		elapsed = elapsed - 1.0
		m_write = m_write + 1
		if m_write >= WINDOW_SIZE+1 then m_write = 1 end
		m_traffic_data[m_write] = 0
	end
	m_elapsed_leftover = elapsed
end

function Me.AddTraffic( bytes )
	PrepareUpdate()
	m_traffic_data[m_write] = m_traffic_data[m_write] + bytes
end

-- returns incoming bytes/sec
function Me.GetTraffic()
	PrepareUpdate()
	local sum = 0
	for k,v in ipairs( m_traffic_data ) do
		sum = sum + v
	end
	sum = sum / WINDOW_SIZE
	
	return sum
end

-- returns formatted incoming
-- e.g. 352  B/s
--   or 1.53 KB/s
function Me.GetTrafficFormatted()
	local sum = Me.GetTraffic()
	if sum >= 1000 then
		return string.format( "%.2f %s", sum/1000, L.KBPS )
	else
		return string.format( "%d %s", sum, L.BPS )
	end
end
