-------------------------------------------------------------------------------
-- Cross RP by Tammya-MoonGuard (2018)
--
-- A node set is a collection of people that you can send messages to, weighted
--  by how much estimated load they might have. The Select method chooses a
--  random node, biased towards less loaded nodes.
-------------------------------------------------------------------------------
local _, Me = ...
local NodeSet = {}
Me.NodeSet = NodeSet

function NodeSet:Select( subset )
	local time = GetTime()
	
	local retry
	repeat
		retry = false
		
		if self.quota_sums[subset or "all"] < 0 then
			error( "Internal error." )
		end
		
		if self.quota_sums[subset or "all"] == 0 then 
			-- no bridges.
			return
		end
		
		local selection = math.random( 1, self.quota_sums[subset or "all"] )
		
		for key, node in pairs( self.nodes ) do
			if subset and node.subset ~= subset then
				-- ignore this node.
				-- wish i had a continue statement.
			else
				selection = selection - node.quota
				if selection <= 0 then
				--	if time > node.time + 150 then
				--		-- This node expired. Remove it and retry. (THIS IS MOVED TO PROTO UPDATE, BECAUSE BNET LINK EXPIRATION HAS TO BE HANDLED SPECIALLY.)
				--		self:Remove( key )
				--		retry = true
				--		break
				--	end
					return key
				end
			end
		end
	until retry == false
	
	error( "Internal error." )
end

function NodeSet:EraseSubset( subset )
	for key, node in pairs( self.nodes ) do
		if node.subset == subset then
			node.subset = nil
		end
	end
	
	self.load_sums[subset]   = 0
	self.quota_sums[subset]  = 0
	self.node_counts[subset] = 0
end

function NodeSet:HasBnetLink( destination )
	local fullname = Me.Proto.DestToFullname( destination )
	for key, node in pairs( self.nodes ) do
		local _, charname, _, realm, _, faction = BNGetGameAccountInfo( key )
		realm = realm:gsub( "%s*%-*", "" )
		charname = charname .. "-" .. realm
		if charname == fullname then return key end
	end
end

function NodeSet:KeyExists( key, subset )
	local node = self.nodes[key]
	if not node or (subset and node.subset ~= subset) then 
		return
	end
	return true
end

function NodeSet:RemoveExpiredNodes()
	local time = GetTime()
	local lost_connection = false
	for key, node in pairs( self.nodes ) do
		if time > node.time + 150 then
			if node.subset then
				if self.node_counts[node.subset] == 1 then
					lost_connection = true
				end
			end
			if self.node_counts.all == 1 then
				lost_connection = true
			end
			Me.DebugLog2( "Nodeset removed expired node.", key )
			self:Remove( key )
		end
	end
	return lost_connection
end

function NodeSet:Empty( subset )
	return self.node_counts[subset or "all"] == 0
end

function NodeSet:ChangeNodeSubset( key, subset )
	local node = self.nodes[key]
	if not node then return end
	if node.subset == subset then return end
	
	self:Add( key, node.load, subset )
end

function NodeSet:Add( key, load, subset )
	-- add
	local quota = math.ceil( 1000 / load )
	local node = self.nodes[key]
	if not node then
		node = {
			load   = 0;
			quota  = 0;
			time   = GetTime();
		}
		self.node_counts.all = self.node_counts.all + 1
		self.nodes[key] = node
	end
	
	self.load_sums.all  = self.load_sums.all - node.load + load
	self.quota_sums.all = self.quota_sums.all - node.quota + quota
	
	if node.subset then
		self.load_sums[node.subset] = self.load_sums[node.subset] - node.load
		self.quota_sums[node.subset] = self.quota_sums[node.subset] - node.quota
		self.node_counts[node.subset] = self.node_counts[node.subset] - 1
	end
	
	node.load  = load
	node.quota = quota
	node.subset = subset
	node.time = GetTime()
	
	if subset then
		self.load_sums[subset] = self.load_sums[subset] + load
		self.quota_sums[subset] = self.quota_sums[subset] + quota
		self.node_counts[subset] = self.node_counts[subset] + 1
	end
end

function NodeSet:Remove( key )
	local emptied_set = false
	local node = self.nodes[key]
	if node then
		self.quota_sums.all  = self.quota_sums.all - node.quota
		self.load_sums.all   = self.load_sums.all - node.load
		self.node_counts.all = self.node_counts.all - 1
		if self.node_counts.all == 0 then
			emptied_set = true
		end
		if node.subset then
			self.quota_sums[node.subset] = self.quota_sums[node.subset] - node.quota
			self.load_sums[node.subset] = self.load_sums[node.subset] - node.load
			self.node_counts[node.subset] = self.node_counts[node.subset] - 1
			if self.node_counts[node.subset] == 0 then
				emptied_set = true
			end
		end
		self.nodes[key] = nil
	end
	return emptied_set
end

-------------------------------------------------------------------------------
function NodeSet:Clear()
	wipe( self.nodes )
	for k, v in pairs( self.node_counts ) do
		self.node_counts[k] = 0
		self.quota_sums[k] = 0
		self.load_sums[k] = 0
	end
end

-------------------------------------------------------------------------------
function NodeSet:GetLoadAverage( subset )
	subset = subset or "all"
	local count = self.node_counts[subset]
	if not count or count == 0 then return end
	return math.floor( self.load_sums[subset] / count + 0.5 )
end

function NodeSet:SubsetCount( subset )
	return self.node_counts[subset]
end

-------------------------------------------------------------------------------
function NodeSet.Create( subsets )
	local object = setmetatable( {
		nodes       = {};
		node_counts = { all = 0 };
		quota_sums  = { all = 0 };
		load_sums   = { all = 0 };
	}, {
		__index = NodeSet;
	})
	
	if subsets then
		for k, v in pairs( subsets ) do
			object.node_counts[v] = 0
			object.quota_sums[v]  = 0
			object.load_sums[v]   = 0
		end
	end
	
	return object
end
