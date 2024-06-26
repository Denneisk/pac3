local Angle = Angle
local RealTime = RealTime
local NULL = NULL

function pac.GenerateNewUniqueID(part_data, base)
	local part_data = table.Copy(part_data)
	base = base or tostring(part_data)

	local function fixpart(part)
		for key, val in pairs(part.self) do
			if val ~= "" and (key == "UniqueID" or key:sub(-3) == "UID") then
				part.self[key] = pac.Hash(base .. val)
			end
		end

		for _, part in pairs(part.children) do
			fixpart(part)
		end
	end

	return part_data
end


do
	local force_draw_localplayer = false

	pac.AddHook("ShouldDrawLocalPlayer", "draw_2d_entity", function()
		if force_draw_localplayer == true then
			return true
		end
	end)

	function pac.DrawEntity2D(ent, x, y, w, h, cam_pos, cam_ang, cam_fov, cam_nearz, cam_farz)

		pac.ShowEntityParts(ent)
		pac.ForceRendering(true)

		ent = ent or pac.LocalPlayer
		x = x or 0
		y = y or 0
		w = w or 64
		h = h or 64
		cam_ang = cam_ang or Angle(0, RealTime() * 25,  0)
		cam_pos = cam_pos or ent:LocalToWorld(ent:OBBCenter()) - cam_ang:Forward() * ent:BoundingRadius() * 2
		cam_fov = cam_fov or 90

		pac.SetupBones(ent)

		cam.Start2D()
			cam.Start3D(cam_pos, cam_ang, cam_fov, x, y, w, h, cam_nearz or 5, cam_farz or 4096)
				pac.FlashlightDisable(true)

				force_draw_localplayer = true
				ent:DrawModel()
				pac.RenderOverride(ent, "opaque")
				pac.RenderOverride(ent, "translucent")
				force_draw_localplayer = false

				pac.FlashlightDisable(false)
			cam.End3D()
		cam.End2D()

		pac.ForceRendering(false)
	end
end

function pac.SetupENT(ENT, owner)
	ENT.pac_owner = ENT.pac_owner or owner or "self"

	local function find(parent, name)
		for _, part in ipairs(parent:GetChildren()) do

			if part:GetName():lower():find(name) then
				return part
			end

			local part = find(part, name)
			if part then return part end
		end
	end

	function ENT:FindPACPart(outfit, name)

		name = name:lower()

		if not outfit.self then
			for _, val in pairs(outfit) do
				local part = self:FindPACPart(val, name)
				if part:IsValid() then
					return part
				end
			end

			return NULL
		end

		self.pac_part_find_cache = self.pac_part_find_cache or {}

		local part = self.pac_outfits[outfit.self.UniqueID] or NULL

		if part:IsValid() then
			local cached = self.pac_part_find_cache[name] or NULL

			if cached:IsValid() then return cached end

			part = find(part, name)


			if part then
				self.pac_part_find_cache[name] = part

				return part
			end
		end

		return NULL
	end

	function ENT:AttachPACPart(outfit, owner, keep_uniqueid)

		if not outfit.self then
			return self:AttachPACSession(outfit, owner)
		end

		if
			(outfit.self.OwnerName == "viewmodel" or outfit.self.OwnerName == "hands") and
			self:IsWeapon() and
			self.Owner:IsValid() and
			self.Owner:IsPlayer() and
			self.Owner ~= pac.LocalPlayer
		then
			return
		end

		if not keep_uniqueid then
			outfit = pac.GenerateNewUniqueID(outfit, self:EntIndex())
		end

		owner = owner or self.pac_owner or self.Owner

		if self.pac_owner == "self" then
			owner = self
		elseif self[self.pac_owner] then
			owner = self[self.pac_owner]
		end

		self.pac_outfits = self.pac_outfits or {}

		local part = self.pac_outfits[outfit.self.UniqueID] or NULL

		if part:IsValid() then
			part:Remove()
		end

		part = pac.CreatePart(outfit.self.ClassName, owner, outfit)

		self.pac_outfits[outfit.self.UniqueID] = part

		self.pac_part_find_cache = {}

		if self.pac_show_in_editor == nil then
			self:SetShowPACPartsInEditor(false)
			self.pac_show_in_editor = nil
		end

		return part
	end

	function ENT:RemovePACPart(outfit, keep_uniqueid)
		if not outfit.self then
			return self:RemovePACSession(outfit)
		end

		if not keep_uniqueid then
			outfit = pac.GenerateNewUniqueID(outfit, self:EntIndex())
		end

		self.pac_outfits = self.pac_outfits or {}

		local part = self.pac_outfits[outfit.self.UniqueID] or NULL

		if part:IsValid() then
			part:Remove()
		end

		self.pac_part_find_cache = {}
	end

	function ENT:GetPACPartPosAng(outfit, name)
		local part = self:FindPACPart(outfit, name)

		if part:IsValid() and part.GetWorldPosition then
			return part:GetWorldPosition(), part:GetWorldAngles()
		end
	end

	function ENT:AttachPACSession(session)
		for _, part in pairs(session) do
			self:AttachPACPart(part)
		end
	end

	function ENT:RemovePACSession(session)
		for _, part in pairs(session) do
			self:RemovePACPart(part)
		end
	end

	function ENT:SetPACDrawDistance(dist)
		self.pac_draw_distance = dist
	end

	function ENT:GetPACDrawDistance()
		return self.pac_draw_distance
	end

	function ENT:SetShowPACPartsInEditor(b)
		self.pac_outfits = self.pac_outfits or {}

		for _, part in pairs(self.pac_outfits) do
			part:SetShowInEditor(b)
		end

		self.pac_show_in_editor = b
	end

	function ENT:GetShowPACPartsInEditor()
		return self.pac_show_in_editor
	end
end

function pac.SetupSWEP(SWEP, owner)
	SWEP.pac_owner = owner or "Owner"
	pac.SetupENT(SWEP, owner)
end

function pac.AddEntityClassListener(class, session, check_func, draw_dist)

	if session.self then
		session = {session}
	end

	draw_dist = 0
	check_func = check_func or function(ent) return ent:GetClass() == class end

	local id = "auto_attach_" .. class

	local weapons = {}
	local function weapon_think()
		for _, ent in pairs(weapons) do
			if ent:IsValid() then
				if ent.Owner and ent.Owner:IsValid() then
					if not ent.AttachPACSession then
						pac.SetupSWEP(ent)
					end

					if ent.Owner:GetActiveWeapon() == ent then
						if not ent.pac_deployed then
							ent:AttachPACSession(session)
							ent.pac_deployed = true
						end

						ent.pac_last_owner = ent.Owner
					else
						if ent.pac_deployed then
							ent:RemovePACSession(session)
							ent.pac_deployed = false
						end
					end
				elseif (ent.pac_last_owner or NULL):IsValid() and not ent.pac_last_owner:Alive() then
					if ent.pac_deployed then
						ent:RemovePACSession(session)
						ent.pac_deployed = false
					end
				end
			end
		end
	end

	local function created(ent)
		if ent:IsValid() and check_func(ent) then
			if ent:IsWeapon() then
				weapons[ent:EntIndex()] = ent
				pac.AddHook("Think", id, weapon_think)
			else
				pac.SetupENT(ent)
				ent:AttachPACSession(session)
				ent:SetPACDrawDistance(draw_dist)
			end
		end
	end

	local function removed(ent)
		if ent:IsValid() and check_func(ent) and ent.pac_outfits then
			ent:RemovePACSession(session)
			weapons[ent:EntIndex()] = nil
		end
	end

	for _, ent in pairs(ents.GetAll()) do
		created(ent)
	end

	pac.AddHook("EntityRemoved", id, removed)
	pac.AddHook("OnEntityCreated", id, created)
end

function pac.RemoveEntityClassListener(class, session, check_func)
	if session.self then
		session = {session}
	end

	check_func = check_func or function(ent) return ent:GetClass() == class end

	for _, ent in pairs(ents.GetAll()) do
		if check_func(ent) and ent.pac_outfits then
			ent:RemovePACSession(session)
		end
	end

	local id = "auto_attach_" .. class

	pac.RemoveHook("Think", id)
	pac.RemoveHook("EntityRemoved", id)
	pac.RemoveHook("OnEntityCreated", id)
end

timer.Simple(0, function()
	if easylua and luadev then
		function easylua.PACSetClassListener(class_name, name, b)
			if b == nil then
				b = true
			end

			luadev.RunOnClients(("pac.%s(%q, {%s})"):format(b and "AddEntityClassListener" or "RemoveEntityClassListener", class_name, file.Read("pac3/".. name .. ".txt", "DATA")))
		end
	end
end)
