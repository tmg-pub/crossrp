
local _, Me = ...
local Serializer = LibStub:GetLibrary("AceSerializer-3.0");

local MAX_PAYLOAD = 2000

-- PROTOCOL:
-- binary message
-- DAT:TAG:S:P:N:DATA
--   TAG = Custom Tag
--   S = 0: plain text, 1 = base64 text, 2 = base64 serialized struct
--   P = page#
--   N = number of pages
--   DATA = page

Me.data_queue = {
	-- [user][serial] = { tag, page, count, data }
}

-- unique per message for buffering purposes
Me.data_serial = 0

local function QueueData( tag, msg, pack )
	local serialized = "0"
	
	if pack then
		if type(msg) == "table" then
			serialized = "2"
			msg = Serializer:Serialize( msg )
		else
			serialized = "1"
		end
		
		msg = Me.ToBase64( msg )
	end
	
	local pages = {}
	
	-- split up message.
	-- this is off-by-one hell...
	local startpoint = 1
	while true do
		if #msg - (startpoint-1) > MAX_PAYLOAD then
			local splitpoint = startpoint + MAX_PAYLOAD
			
			for i = 1,16 do
				if i == 16 then return end -- invalid input
				
				local ch = msg:byte( splitpoint )
				if ch >= 32 and ch <= 128 or ch >= 192 then
					-- normall ascii or valid UTF-8 start character
					break
				end
				splitpoint = splitpoint - 1
			end
			
			table.insert( pages, msg:sub( startpoint, splitpoint-1 ))
			startpoint = splitpoint
		else
			table.insert( pages, msg:sub( startpoint ))
			break
		end
	end
	
	for k, v in ipairs( pages ) do
		Me.SendPacket( "DATA", table.concat({
				tag, serialized, string.format( "%X", Me.data_serial), k, #pages, v }, ":"))
	end
	Me.data_serial = (Me.data_serial + 1) % 4096
end

-------------------------------------------------------------------------------
function Me.SendData( tag, msg )
	QueueData( tag, msg, true )
end

-------------------------------------------------------------------------------
function Me.SendTextData( tag, msg )
	QueueData( tag, msg, false )
end	

-------------------------------------------------------------------------------
function Me.ProcessPacket.DATA( user, command, msg )
	local tag, serialized, serial, page, pagecount, data = msg:match( "^([^:]+):([0-3]):([0-9A-F]+):([0-9]+):([0-9]+):(.*)" )
	if not tag then return end
	Me.data_queue[user.name] = Me.data_queue[user.name] or {}
	local queue = Me.data_queue[user.name]
	print("DATA got queue")
	page = tonumber(page)
	pagecount = tonumber(pagecount)
	serial = tonumber(serial)
	if not queue[serial] then
		queue[serial] = {
			time = GetTime();
			pages = {}
		}
	else
		if GetTime() - queue[serial].time > 30 then
			--timeout
			queue[serial] = {
				time = GetTime();
				pages = {}
			}
		end
	end
	print("DATA got queue saving page", page)
	queue[serial].pages[page] = data
	
	local qs = queue[serial]
	
	for i = 1, pagecount do
		if not qs.pages[i] then
			-- unfinished message
			return
		end
	end
	print(" getting final message" )
	local final_message = ""
	for i = 1, pagecount do
		final_message = final_message .. qs.pages[i]
	end
		print(" getting final message1" )
	queue[serial] = nil
	serialized = tonumber( serialized )
	if serialized >= 1 then
		final_message = Me.FromBase64( final_message )
	end
		print(" getting final message2" )
	if serialized >= 2 then
		local good
		good, final_message = Serializer:Deserialize( final_message )
		if not good then return end
	end
		print(" getting final message3" )
	Me.ReceiveData( user, tag, serialized == 0, final_message )
end

-------------------------------------------------------------------------------
function Me.ReceiveData( user, tag, istext, data )
	if Me.DataHandlers[tag] then
		Me.DataHandlers[tag]( user, tag, istext, data )
	end
end
