-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- For private data that is inaccessible to other addons and the game UI.
-------------------------------------------------------------------------------
local _, Me = ...
-------------------------------------------------------------------------------
-- Other files should have this pattern if they want to share or use private
--  data, and only use the local reference. They also need to take care that
--  there aren't easy ways to tamper with the private data from outside.
--
--     Me.Private = Me.Private or {}
--     local Private = Me.Private
--
-- The principle here is that it's not easy to touch the private data without
--  editing the source code, so that difficulty is a deterrence for 
--  circumventing some limitations, like the war mode check.
Me.Private = nil
