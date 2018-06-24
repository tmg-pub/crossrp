
local _, Me = ...

Me.timers = {}

-- slot = string ID
-- mode = how this timer reacts to additional start calls
--          "push" = push execution back to new time
--          "ignore" = ignore the new call
--          "duplicate" = leave previous timer running and make new one
function Me.Timer_Start( slot, mode, time, func )
	if Me.timers[slot] then
		if mode == "push" then
			Me.timers[slot].cancel = true
		elseif mode == "duplicate" then
			
		else -- ignore/default
			return
		end
	end
	
	local this_timer = {
		cancel = false;
	}
	
	Me.timers[slot] = this_timer
	C_Timer.After( time, function()
		if this_timer.cancel then return end
		Me.timers[slot] = nil
		func()
	end)
end

function Me.Timer_Cancel( slot )
	if Me.timers[slot] then
		Me.timers[slot].cancel = true
		Me.timers[slot] = nil
	end
end