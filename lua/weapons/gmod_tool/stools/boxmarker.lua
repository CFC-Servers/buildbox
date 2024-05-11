TOOL.Category = "Construction"
TOOL.Name = "#tool.boxmarker.name"

TOOL.Information = {
	{name = "left", stage = 0},
	{name = "left_1", stage = 1},
	{name = "left_1_use", stage = 1},
	{name = "right", stage = 1},
	{name = "reload", stage = 1}
}

TOOL.CARDINAL_NORMAL = 0
TOOL.CARDINAL_FACING = 1

-- Tool settings

TOOL.ClientConVar["expand"] = 0
TOOL.ClientConVar["cardinal_mode"] = 0

-- Box convars
TOOL.ClientConVar["minx"] = 0
TOOL.ClientConVar["miny"] = 0
TOOL.ClientConVar["minz"] = 0

TOOL.ClientConVar["maxx"] = 0
TOOL.ClientConVar["maxy"] = 0
TOOL.ClientConVar["maxz"] = 0

-- Client options
TOOL.ClientConVar["draw_effects"] = 1

TOOL.ClientConVar["tint_red"] = 0
TOOL.ClientConVar["tint_green"] = 161
TOOL.ClientConVar["tint_blue"] = 255
TOOL.ClientConVar["tint_alpha"] = 5

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

		if self:GetStage() == 0 then
			self:SetStage(1)
		end

		return true
	end

	local pos = trace.HitPos

	if self:GetStage() == 0 then
		self:SetBounds(pos, pos)
	else
		local mins, maxs = self:GetBounds()
		local ply = self:GetOwner()

		if ply:KeyDown(IN_USE) then
			local normal
			local mode = self:GetClientNumber("cardinal_mode", self.CARDINAL_NORMAL)

			if mode == self.CARDINAL_NORMAL then
				normal = trace.HitNormal
			elseif mode == self.CARDINAL_FACING then
				normal = ply:GetAimVector()
			end

			local index, winningValue = 0, 0

			for k, direction in pairs(cardinals) do
				local value = math.abs(normal:Dot(direction))

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
	if self:GetStage() == 0 or CLIENT then
		return true
	end

	local mins, maxs = self:GetBounds()
	local expand = self:GetClientNumber("expand", 0)

	mins = mins - Vector(1, 1, 1) * expand
	maxs = maxs + Vector(1, 1, 1) * expand

	local center = LerpVector(0.5, mins, maxs)

	mins = WorldToLocal(mins, angle_zero, center, angle_zero)
	maxs = WorldToLocal(maxs, angle_zero, center, angle_zero)

	for _, v in pairs(ents.FindByClass("buildbox_zone")) do
		if util.IsOBBIntersectingOBB(center, angle_zero, mins, maxs, v:GetPos(), v:GetAngles(), v:GetMins(), v:GetMaxs()) then

			net.Start("buildbox.error")
			net.Send(self:GetOwner())

			return true
		end
	end

	local ent = ents.Create("buildbox_zone")

	ent:SetPos(center)
	ent:SetMins(mins)
	ent:SetMaxs(maxs)

	ent:Spawn()
	ent:Activate()

	self:SetStage(0)

	undo.Create("BuildBox")
		undo.AddEntity(ent)
		undo.SetPlayer(self:GetOwner())
	undo.Finish()

	return true
end

function TOOL:Reload(trace)
	self:SetStage(0)

	return true
end

function TOOL:DrawHUD()
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
		CPanel:AddControl("header", {description = "#tool.boxmarker.desc"})

		CPanel:AddControl("listbox", {
			label = "#tool.boxmarker.cardinal_mode",
			options = {
				["#tool.boxmarker.cardinal.normal"] = {boxmarker_cardinal_mode = 0},
				["#tool.boxmarker.cardinal.facing"] = {boxmarker_cardinal_mode = 1}
			}
		})

		CPanel:AddControl("slider", {
			type = "float",
			label = "#tool.boxmarker.expand",
			min = -20,
			max = 20,
			command = "boxmarker_expand"
		})

		CPanel:AddControl("header", {description = "#tool.boxmarker.clientoptions"})

		CPanel:AddControl("checkBox", {label = "#tool.boxmarker.draw_effects", Command = "boxmarker_draw_effects"})

		CPanel:AddControl("color", {
			label = "#tool.boxmarker.tint_color",
			red = "boxmarker_tint_red",
			green = "boxmarker_tint_green",
			blue = "boxmarker_tint_blue",
			alpha = "boxmarker_tint_alpha"
		})
	end

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

		if tool.Mode != "boxmarker" or tool:GetStage() != 1 then
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

	net.Receive("buildbox.error", function()
		notification.AddLegacy(language.GetPhrase("tool.boxmarker.error"), NOTIFY_ERROR, 2)
		surface.PlaySound("buttons/button10.wav")
	end)
else
	util.AddNetworkString("buildbox.error")
end
