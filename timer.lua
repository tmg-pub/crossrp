-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- This is my HANDY timer API. Manages timers by unique IDs called "slots".
-------------------------------------------------------------------------------
local _, Me = ...

-------------------------------------------------------------------------------
-- A list of timer objects, indexed by their `slot`. The only thing these 
--  actually contain is a `cancel` flag. C_Timer doesn't have any way to cancel
--  a timer, so we store a cancel flag and then cancel it from inside our
--  handler. This is the only thing exposed to the outside, the rest of the
--                               callback info is accessed from a closure.
Me.timers = {}
-------------------------------------------------------------------------------
-- The last time each timer was triggered, indexed by `slot`.
Me.last_triggered = {}

-------------------------------------------------------------------------------
-- Returns true if the time since this timer last fired is greater than
--  `period` seconds.
--
function Me.Timer_NotOnCD( slot, period )
	local time_to_next 
	            = (Me.last_triggered[slot] or (-period)) + period - GetTime()
	if time_to_next <= 0 then
		return true
	end
end

-------------------------------------------------------------------------------
-- Start a new timer.
-- slot: Unique string ID for this timer.
-- mode: How this timer works or reacts to additional Start calls.
-- period: Seconds until the timer triggers.
-- func: Callback function.
--
-- Here are the different start modes:
--  "push"       Cancel existing timer. If you're using the same period and
--                unction, you're "pushing" its execution back. This might also
--                make it faster if your new period is shorter.
--  "ignore"     Ignore the new call. If you try to start a new timer under a
--                slot that's already waiting, then it ignores you.
--  "duplicate"  Leave previous timer running and make new one. If you call
--                Start three times for a single tag, the previous two will
--                still trigger, and they cannot be canceled or otherwise 
--                modified at that point.
--  "cooldown"   This is like ignore, but it allows triggering instantly, if 
--                the last call wasn't done within the period specified. 
--                Otherwise, it's "on cooldown", and the timer behaves like 
--                "ignore" and the trigger time is fixed to 
--                last_trigger_time + period. Or in other words, it only allows
--                execution of a function every `period` seconds, and if it's
--                "on cooldown", it schedules a call for when the cooldown
--                expires. The callback will fire from this execution path
--                (inside Timer_Start) when not on cooldown.
function Me.Timer_Start( slot, mode, period, func )
	if mode == "cooldown" and not Me.timers[slot] then
		-- Time until the cooldown expires.
		local time_to_next 
		         = (Me.last_triggered[slot] or (-period)) + period - GetTime()
		if time_to_next <= 0 then
			-- No cooldown, we can trigger instantly.
			Me.last_triggered[slot] = GetTime()
			func()
			return
		end
		
		-- Cooldown remains, ignore or schedule it.
		mode   = "ignore"
		period = time_to_next
	end
	
	if Me.timers[slot] then
		if mode == "push" then
			-- Cancel existing timer for "push".
			Me.timers[slot].cancel = true
		elseif mode == "duplicate" then
			-- Exiting timer will be forgotten and fire accordingly.
		else -- "ignore"/default
			return
		end
	end
	
	-- This is the only data we need to expose to the outside, and we capture
	--  it inside our anonymous callback.
	local this_timer = {
		cancel = false;
	}
	
	Me.timers[slot] = this_timer
	C_Timer.After( period, function()
		if this_timer.cancel then return end
		Me.timers[slot] = nil
		Me.last_triggered[slot] = GetTime()
		func()
	end)
end

-------------------------------------------------------------------------------
-- Cancels an existing timer. `slot` is what was passed to Timer_Start. Any
--  forgotten "duplicate" timers will not be cancelled.
function Me.Timer_Cancel( slot )
	if Me.timers[slot] then
		Me.timers[slot].cancel = true
		Me.timers[slot] = nil
	end
end
