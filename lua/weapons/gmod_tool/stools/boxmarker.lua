TOOL.Category = "Construction"
TOOL.Name = "#tool.boxmarker.name"

TOOL.Information = {
	{name = "left"},
	{name = "right"},
	{name = "reload"}
}

TOOL.ClientConVar["active"] = 0

TOOL.ClientConVar["minx"] = 0
TOOL.ClientConVar["miny"] = 0
TOOL.ClientConVar["minz"] = 0

TOOL.ClientConVar["maxx"] = 0
TOOL.ClientConVar["maxy"] = 0
TOOL.ClientConVar["maxz"] = 0

local cardinals = {
	Vector(1, 0, 0),
	Vector(0, 1, 0),
	Vector(0, 0, 1)
}

function TOOL:LeftClick(trace)
	if trace.StartSolid then
		return
	end

	if SERVER then
		if game.SinglePlayer() then
			self:GetWeapon():CallOnClient("PrimaryAttack")
		end

		return true
	end

	local pos = trace.HitPos

	if not self:IsActive() then
		self:SetActive(true)
		self:SetBounds(pos, pos)
	else
		local mins, maxs = self:GetBounds()
		local ply = self:GetOwner()

		if ply:KeyDown(IN_USE) then
			local aimVector = ply:GetAimVector()
			local index, winningValue = 0, 0

			for k, direction in pairs(cardinals) do
				local value = math.abs(aimVector:Dot(direction))

				if value > winningValue then
					index = k
					winningValue = value
				end
			end

			local direction = cardinals[index]
			local center = LerpVector(0.5, mins, maxs)
			local diff = (pos - center) * direction

			pos = center + diff
		end

		mins.x = math.min(mins.x, pos.x)
		mins.y = math.min(mins.y, pos.y)
		mins.z = math.min(mins.z, pos.z)

		maxs.x = math.max(maxs.x, pos.x)
		maxs.y = math.max(maxs.y, pos.y)
		maxs.z = math.max(maxs.z, pos.z)

		self:SetBounds(mins, maxs)
	end

	if not game.SinglePlayer() then
		return true
	end
end

function TOOL:RightClick(trace)
	if not self:IsActive() or CLIENT then
		return true
	end

	local mins, maxs = self:GetBounds()
	local center = LerpVector(0.5, mins, maxs)

	mins = WorldToLocal(mins, angle_zero, center, angle_zero)
	maxs = WorldToLocal(maxs, angle_zero, center, angle_zero)

	local ent = ents.Create("buildbox_zone")

	ent:SetPos(center)
	ent:SetMins(mins)
	ent:SetMaxs(maxs)

	ent:Spawn()
	ent:Activate()

	local ply = self:GetOwner()

	ply:ConCommand("boxmarker_active 0")

	undo.Create("BuildBox")
		undo.AddEntity(ent)
		undo.SetPlayer(ply)
	undo.Finish()

	return true
end

function TOOL:Reload(trace)
	if SERVER then
		self:GetOwner():ConCommand("boxmarker_active 0")
	end

	return true
end

function TOOL:DrawHUD()
end

function TOOL:IsActive()
	return self:GetClientBool("active", false)
end

function TOOL:GetBounds()
	local mins, maxs = Vector(), Vector()

	mins.x = self:GetClientNumber("minx")
	mins.y = self:GetClientNumber("miny")
	mins.z = self:GetClientNumber("minz")

	maxs.x = self:GetClientNumber("maxx")
	maxs.y = self:GetClientNumber("maxy")
	maxs.z = self:GetClientNumber("maxz")

	return mins, maxs
end

if CLIENT then
	function TOOL:SetActive(bool)
		self.ClientConVars.active:SetBool(bool)
	end

	function TOOL:SetBounds(mins, maxs)
		self.ClientConVars.minx:SetFloat(mins.x)
		self.ClientConVars.miny:SetFloat(mins.y)
		self.ClientConVars.minz:SetFloat(mins.z)

		self.ClientConVars.maxx:SetFloat(maxs.x)
		self.ClientConVars.maxy:SetFloat(maxs.y)
		self.ClientConVars.maxz:SetFloat(maxs.z)
	end

	function TOOL.BuildCPanel(CPanel)
		CPanel:AddControl("header", {Description = "#tool.boxmarker.desc"})
	end

	-- Since we don't want people to load into a map with leftover settings from another map, we reset when the tool is loaded.
	hook.Add("PreRegisterTOOL", "tool.boxmarker", function(tool, mode)
		if mode != "boxmarker" then
			return
		end

		for _, convar in pairs(tool.ClientConVars) do
			convar:Revert()
		end
	end)

	local color = Color(255, 0, 0)

	hook.Add("PostDrawTranslucentRenderables", "tool.boxmarker", function(depth, skybox, skybox3D)
		if skybox or skybox3D then
			return
		end

		local ply = LocalPlayer()
		local weapon = ply:GetActiveWeapon()

		if not IsValid(weapon) or weapon:GetClass() != "gmod_tool" then
			return
		end

		local tool = ply:GetTool()

		if tool.Mode != "boxmarker" or not tool:IsActive() then
			return
		end

		local mins, maxs = tool:GetBounds()

		render.SetColorMaterial()

		-- Invert the draw direction if we're on the inside
		if EyePos():WithinAABox(mins, maxs) then
			mins, maxs = maxs, mins
		end

		render.DrawBox(vector_origin, angle_zero, mins, maxs, ColorAlpha(color, 50))
		render.DrawWireframeBox(vector_origin, angle_zero, mins, maxs, color)
	end)
end
