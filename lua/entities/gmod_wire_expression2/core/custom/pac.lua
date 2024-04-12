E2Lib.RegisterExtension("pac", true)

util.AddNetworkString("pac_e2_setkeyvalue_str")
util.AddNetworkString("pac_e2_setkeyvalue_num")
util.AddNetworkString("pac_e2_setkeyvalue_vec")
util.AddNetworkString("pac_e2_setkeyvalue_ang")

local enabledConvar = CreateConVar("pac_e2_ratelimit_enable", "1", {FCVAR_ARCHIVE}, "If the e2 ratelimit should be enabled.", 0, 1)
local rate = CreateConVar("pac_e2_ratelimit_refill", "0.025", {FCVAR_ARCHIVE}, "The speed at which the ratelimit buffer refills.", 0, 1000)
local buffer = CreateConVar("pac_e2_ratelimit_buffer", "300", {FCVAR_ARCHIVE}, "How large the ratelimit buffer should be.", 0, 1000)
local bytes = CreateConVar("pac_e2_bytelimit", "8192", FCVAR_ARCHIVE, "Limit number of bytes sent in a single tick.", 0, 65532)

local byteLimits = WireLib.RegisterPlayerTable()
local function canRunFunction(self, g, k, v)
	local byteLimit = byteLimits[self.player]
	if not byteLimit then
		byteLimit = { CurTime(), 0 }
		byteLimits[self.player] = byteLimit
	end

	local lim = #g + #k + #v
	if byteLimit[1] == CurTime() then
		lim = lim + byteLimit[2]
	end
	byteLimit[2] = lim

	if lim >= bytes:GetInt() then return self:throw("pac3 e2 byte limit exceeded", false) end

	if not enabledConvar:GetBool() then return true end

	local allowed = pac.RatelimitPlayer(self.player, "e2_extension", buffer:GetInt(), rate:GetInt())
	if not allowed then
		return self:throw("pac3 e2 ratelimit exceeded", false)
	end
	return true
end

e2function void pacSetKeyValue(entity owner, string global_id, string key, string value)
	if not canRunFunction(self, global_id, key, value) then return end
	net.Start("pac_e2_setkeyvalue_str")
		net.WriteEntity(self.player)
		net.WriteEntity(owner)
		net.WriteString(global_id)
		net.WriteString(key)

		net.WriteString(value)
	net.Broadcast()
end

e2function void pacSetKeyValue(entity owner, string global_id, string key, number value)
	if not canRunFunction(self, global_id, key, "nmbr") then return end -- Workaround because I don't want to add cases for each type, 4 bytes
	net.Start("pac_e2_setkeyvalue_num")
		net.WriteEntity(self.player)
		net.WriteEntity(owner)
		net.WriteString(global_id)
		net.WriteString(key)

		net.WriteFloat(value)
	net.Broadcast()
end

e2function void pacSetKeyValue(entity owner, string global_id, string key, vector value)
	if not canRunFunction(self, global_id, key, "vctrvctrvctr") then return end -- 4 bytes, 3 times
	net.Start("pac_e2_setkeyvalue_vec")
		net.WriteEntity(self.player)
		net.WriteEntity(owner)
		net.WriteString(global_id)
		net.WriteString(key)

		net.WriteVector(value)
	net.Broadcast()
end

e2function void pacSetKeyValue(entity owner, string global_id, string key, angle value)
	if not canRunFunction(self, global_id, key, "vctrvctrvctr") then return end
	net.Start("pac_e2_setkeyvalue_ang")
		net.WriteEntity(self.player)
		net.WriteEntity(owner)
		net.WriteString(global_id)
		net.WriteString(key)

		net.WriteAngle(value)
	net.Broadcast()
end
