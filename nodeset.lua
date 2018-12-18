-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- A node set is a collection of people that you can send messages to, weighted
--  by how much estimated load they might have. The Select method chooses a
--  random node, biased towards less loaded nodes.
-------------------------------------------------------------------------------
local _, Main = ...
local Me = {
	Methods = {}
}
Main.NodeSet = Me

function Me.Methods:Select()
	
	local retry
	repeat
		retry = false
		
		if self.quota_sum < 0 then
			error( "Internal error." )
		end
		
		if self.quota_sum == 0 then 
			-- no bridges.
			return
		end
		
		local selection = math.random( 1, self.quota_sum )
		
		for key, node in pairs( self.nodes ) do
			selection = selection - node.quota
			if selection <= 0 then
				if GetTime() > node.time + 150 then
					-- This node expired. Remove it and retry.
					self:Remove( key )
					retry = true
					break
				end
				return key
			end
		end
	until retry == false
	
	error( "Internal error." )
end

function Me.Methods:HasBnetLink( destination )
	local fullname = Me.DestinationToFullname( destination )
	for key, node in pairs( self.nodes ) do
		local _, charname, _, realm, _, faction = BNGetGameAccountInfo( gameid )
		realm = realm:gsub( "%s*%-*", "" )
		charname = charname .. "-" .. realm
		if charname == fullname then return key end
	end
end

function Me.Methods:RemoveExpiredNodes()
	local removed = false
	for key, node in pairs( self.nodes ) do
		if GetTime() > node.time + 150 then
			self:Remove( key )
			removed = true
		end
	end
	return removed
end

function Me.Methods:Add( key, load )
	-- add
	local quota = math.ceil( 1000 / load )
	local node = self.nodes[key]
	if node then
		
		self.load_sum  = self.load_sum - node.load + load
		self.quota_sum = self.quota_sum - node.quota + quota
		
		node.load  = load
		node.quota = quota
		node.time  = GetTime()
	else
		self.nodes[key] = {
			load  = load;
			quota = quota;
			time  = GetTime();
		}
		self.node_count = self.node_count + 1
		self.load_sum   = self.load_sum + load
		self.quota_sum  = self.quota_sum + quota
	end
end

function Me.Methods:Remove( key )
	local node = self.nodes[key]
	if node then
		self.quota_sum  = self.quota_sum - node.quota
		self.load_sum   = self.load_sum - node.load
		self.node_count = self.node_count - 1
		self.nodes[key] = nil
	end
end

-------------------------------------------------------------------------------
function Me.Methods:GetLoadAverage()
	if not self.node_count then return end
	return math.floor( self.load_sum / self.node_count + 0.5 )
end

-------------------------------------------------------------------------------
function Me.Create()
	local object = {
		nodes      = {};
		node_count = 0;
		quota_sum  = 0;
		load_sum   = 0;
	}
	for k, v in pairs(Me.Methods) do
		object[k] = v
	end
	
	return object
end
