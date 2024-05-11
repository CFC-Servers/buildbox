AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.WantsTranslucency = true

ENT.ClassBlacklist = {
	["buildbox_zone"] = true,
	["quad_prop"] = true,
	["starfall_hologram"] = true,
	["starfall_hud"] = true,
	["starfall_processor"] = true,
	["starfall_prop"] = true,
	["starfall_screen"] = true,
	["starfall_cnextbot"] = true
}

function ENT:Initialize()
	self:SetModel("models/hunter/blocks/cube05x05x05.mdl")

	local mins, maxs = self:GetMins(), self:GetMaxs()

	self:DrawShadow(false)

	if CLIENT then
		self:SetRenderBounds(mins, maxs)
	else
		self:PhysicsInitBox(mins, maxs)
		self:SetCollisionBounds(mins, maxs)

		self:SetMoveType(MOVETYPE_NONE)
		self:SetNotSolid(true)
		self:SetTrigger(true)

		self:GetPhysicsObject():EnableMotion(false)

		self.Entities = {}
		self.Players = {}

		local entities = ents.FindInBox(self:LocalToWorld(mins), self:LocalToWorld(maxs))

		for _, v in pairs(entities) do
			self:StartTouch(v)
		end
	end
end

function ENT:SetupDataTables()
	self:NetworkVar("Vector", "Mins")
	self:NetworkVar("Vector", "Maxs")
end

if CLIENT then
	function ENT:Draw(flags)
	end

	local overlayMaterial = Material("models/shadertest/predator")

	function ENT:DrawTranslucent(flags)
		if not GetConVar("boxmarker_draw_effects"):GetBool() then
			return
		end

		local pos, ang = self:GetPos(), self:GetAngles()
		local mins, maxs = self:GetMins(), self:GetMaxs()

		-- Invert the draw direction if we're on the inside
		if EyePos():WithinAABox(self:LocalToWorld(mins), self:LocalToWorld(maxs)) then
			mins, maxs = maxs, mins
		end

		render.SetStencilEnable(true)
		render.ClearStencil()

		render.SetStencilTestMask(255)
		render.SetStencilWriteMask(255)
		render.SetStencilReferenceValue(1)

		render.SetStencilPassOperation(STENCIL_REPLACE)
		render.SetStencilFailOperation(STENCIL_KEEP)
		render.SetStencilZFailOperation(STENCIL_KEEP)

		render.SetStencilCompareFunction(STENCIL_ALWAYS)

		local color = Color(
			GetConVar("boxmarker_tint_red"):GetInt(),
			GetConVar("boxmarker_tint_green"):GetInt(),
			GetConVar("boxmarker_tint_blue"):GetInt(),
			GetConVar("boxmarker_tint_alpha"):GetInt()
		)

		render.SetColorMaterial()
		render.DrawBox(pos, ang, mins, maxs, color)

		render.SetStencilCompareFunction(STENCIL_EQUAL)

		render.UpdateRefractTexture()
		render.SetMaterial(overlayMaterial)

		overlayMaterial:SetFloat("$refractamount", 0.01)

		render.DrawScreenQuad()

		overlayMaterial:SetFloat("$refractamount", 1)

		render.SetStencilEnable(false)
	end
else
	function ENT:IsValidEntity(ent)
		if ent:EntIndex() == 0 or ent:CreatedByMap() then
			return false
		end

		if ent:IsNPC() or ent:IsPlayer() or ent:IsVehicle() then
			return false
		end

		if IsValid(ent.BuildBox) and ent.BuildBox != self then
			return false
		end

		if self.ClassBlacklist[ent:GetClass()] then
			return false
		end

		return true
	end

	function ENT:GetTopLevelEntity(ent)
		local top = ent

		while true do
			local parent = top:GetParent()

			if not IsValid(parent) then
				return top
			end

			top = parent
		end
	end

	function ENT:GetEntityHierarchy(ent)
		local entities = {ent}
		local iterate

		iterate = function(parent)
			for _, child in pairs(parent:GetChildren()) do
				entities[#entities + 1] = child

				iterate(child)
			end
		end

		iterate(ent)

		return entities
	end

	function ENT:ContainsEntity(ent)
		ent = self:GetTopLevelEntity(ent)

		return tobool(self.Entities[ent] or self.Players[ent])
	end

	function ENT:SetTransmit(entities, ply, should, claim)
		if not istable(entities) then
			entities = {entities}
		end

		for _, ent in pairs(entities) do
			if ent == ply then
				return
			end

			ent:SetPreventTransmit(ply, not should)

			if claim != nil then
				ent.BuildBox = claim and self or nil
			end
		end
	end

	function ENT:CaptureEntity(ent)
		local players = table.GetKeys(self.Players)
		local entities = self:GetEntityHierarchy(ent)

		-- Add to everyone inside
		local addFilter = RecipientFilter()

		addFilter:AddPlayers(players)

		self:SetTransmit(entities, addFilter, true, true)

		-- Remove from everyone outside
		local removeFilter = RecipientFilter()

		removeFilter:AddAllPlayers()
		removeFilter:RemovePlayers(players)

		self:SetTransmit(entities, removeFilter, false, true)
	end

	function ENT:ReleaseEntity(ent)
		local players = table.GetKeys(self.Players)
		local entities = self:GetEntityHierarchy(ent)

		-- Add to everyone outside
		local addFilter = RecipientFilter()

		addFilter:AddAllPlayers()
		addFilter:RemovePlayers(players)

		self:SetTransmit(entities, addFilter, true, false)

		-- Remove from everyone inside
		local removeFilter = RecipientFilter()

		removeFilter:AddPlayers(players)

		self:SetTransmit(entities, removeFilter, false, false)
	end

	function ENT:CapturePlayer(ply)
		ply.BuildBox = self

		for _, v in ents.Iterator() do
			if not self:IsValidEntity(v) then
				continue
			end

			self:SetTransmit(v, ply, self:ContainsEntity(v))
		end
	end

	function ENT:ReleasePlayer(ply)
		ply.BuildBox = nil

		for _, v in ents.Iterator() do
			if not self:IsValidEntity(v) then
				continue
			end

			self:SetTransmit(v, ply, not self:ContainsEntity(v))
		end
	end

	function ENT:UpdateTransmitState()
		return TRANSMIT_ALWAYS
	end

	function ENT:StartTouch(ent)
		if ent:IsPlayer() then
			self.Players[ent] = true
			self:CapturePlayer(ent)
		elseif self:IsValidEntity(ent) then
			self.Entities[ent] = true
			self:CaptureEntity(ent)
		end
	end

	function ENT:EndTouch(ent)
		if ent:IsPlayer() then
			self.Players[ent] = nil
			self:ReleasePlayer(ent)
		elseif self:IsValidEntity(ent) then
			self.Entities[ent] = nil

			if not ent:IsFlagSet(FL_KILLME) then
				self:ReleaseEntity(ent)
			end
		end
	end

	function ENT:OnRemove()
		for ply in pairs(self.Players) do
			self.Players[ply] = nil
			self:ReleasePlayer(ply)
		end

		for ent in pairs(self.Entities) do
			self.Entities[ent] = nil
			self:ReleaseEntity(ent)
		end
	end
end

if SERVER then
	hook.Add("PlayerInitialSpawn", "buildbox", function(ply)
		timer.Simple(0, function()
			if not IsValid(ply) or ply.BuildBox then
				return
			end

			for _, ent in ents.Iterator() do
				if ent.BuildBox then
					ent:SetPreventTransmit(ply, true)
				end
			end
		end)
	end)
end
