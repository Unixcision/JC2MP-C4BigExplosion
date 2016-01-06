class "C4Controller"

C4Controller.AnimationTimeout = 0.6
C4Controller.DetonationTimeout = 0.4
C4Controller.MaxPlantDistance = 6
C4Controller.PlantingOffset = Vector3(0.3, -0.06, -0.02)
C4Controller.DetonationOffset = Vector3(0.34, 0.02, 0.05)

function C4Controller:__init()
	self.dummies = {}
	self.planted = true
	self.crouched = false
	self.tossed = false
	self.underhand = false
	self.detonated = true
	self.plantedTimer = Timer()
	self.detonationTimer = Timer()

	Events:Subscribe("ModuleUnload", self, self.ModuleUnload)
	Events:Subscribe("InputPoll", self, self.InputPoll)
	Events:Subscribe("LocalPlayerInput", self, self.LocalPlayerInput)
	Events:Subscribe("PreTick", self, self.PreTick)
	Events:Subscribe("Render", self, self.Render)
end

function C4Controller:ModuleUnload()
	for k, dummy in pairs(self.dummies) do
		dummy:Remove()
	end
end

function C4Controller:InputPoll()
	if not self.planted then
		Input:SetValue(Action.LookLeft, 0)
		Input:SetValue(Action.LookUp, 0)
		Input:SetValue(Action.LookRight, 0)
		Input:SetValue(Action.LookDown, 0)
		Input:SetValue(Action.MoveLeft, 0)
		Input:SetValue(Action.MoveForward, 0)
		Input:SetValue(Action.MoveRight, 0)
		Input:SetValue(Action.MoveBackward, 0)

		if self.crouched then
			Input:SetValue(Action.Crouch, 1)
		end

		LocalPlayer:SetAngle(Angle(Camera:GetAngle().yaw, LocalPlayer:GetAngle().pitch, LocalPlayer:GetAngle().roll))

		if self.tossed then
			LocalPlayer:SetLeftArmState(AnimationState.LaSThrowTriggeredExplosive)
		elseif self.underhand then
			LocalPlayer:SetLeftArmState(AnimationState.LaSUnderThrowGrenade)
		else
			LocalPlayer:SetLeftArmState(AnimationState.LaSPlaceTriggeredExplosive)
		end
	elseif self.detonationTimer:GetSeconds() < C4Controller.DetonationTimeout then
		Input:SetValue(Action.Reload, 0)
		LocalPlayer:SetLeftArmState(AnimationState.LaSWieldGrenade)
	end
end

function C4Controller:LocalPlayerInput(args)
	local input = args.input

	if input == Action.FireLeft and self.planted then
		local raycast = Physics:Raycast(Camera:GetPosition(), Camera:GetAngle() * Vector3.Forward, 0, 500, false)
		local distance = raycast.distance
		local entity = raycast.entity

		if distance < C4Controller.MaxPlantDistance then
			self.crouched = Camera:GetAngle().pitch < -math.pi / 4
			self.tossed = not self.crouched and Camera:GetAngle().pitch > math.pi / 8
			self.underhand = not self.crouched and not self.tossed and distance > C4Controller.MaxPlantDistance - 2
			self.planted = false
			self.plantedTimer:Restart()
		end

		return false
	elseif input == Action.Reload and self.detonated then
		self.detonated = false
		self.detonationTimer:Restart()

		return false
	end
end

function C4Controller:PreTick()
	if not self.planted and self.plantedTimer:GetSeconds() > C4Controller.AnimationTimeout then
		local args = {}
		local position = LocalPlayer:GetBonePosition("ragdoll_LeftForeArm") + LocalPlayer:GetBoneAngle("ragdoll_LeftForeArm") * C4Controller.PlantingOffset
		local raycast = Physics:Raycast(position, (LocalPlayer:GetAimTarget().position - position):Normalized(), 0, 500, true)
		local entity = raycast.entity

		args.world = LocalPlayer:GetWorld()
		args.position = raycast.position
		args.angle = Angle.FromVectors(Vector3.Up, raycast.normal)
		args.values = {}

		if entity and table.find({"LocalPlayer", "Player", "Vehicle", "StaticObject"}, entity.__type) then
			args.position = entity:GetPosition()
			args.values.parent = entity

			if entity.__type == "LocalPlayer" or entity.__type == "Player" then
				local closestBone = nil

				for k, bone in pairs(entity:GetBones()) do
					if not closestBone or bone.position:Distance(raycast.position) < closestBone.position:Distance(raycast.position) then
						args.values.parent_bone = k
						args.values.position_offset = -bone.angle * (raycast.position - bone.position)
						args.values.angle_offset = -bone.angle * args.angle

						closestBone = bone
					end
				end
			else
				args.values.position_offset = -entity:GetAngle() * (raycast.position - entity:GetPosition())
				args.values.angle_offset = -entity:GetAngle() * args.angle
			end
		end

		Network:Send("Spawn", args)
		self.planted = true
	elseif not self.detonated and self.detonationTimer:GetSeconds() > C4Controller.DetonationTimeout / (self.tossed and 4 or 1) then
		Network:Send("Detonate", args)
		self.detonated = true
	end
end

function C4Controller:Render()
	for player in Client:GetPlayers() do
		self:ApplyDummy(player)
	end

	self:ApplyDummy(LocalPlayer)
end

function C4Controller:ApplyDummy(player)
	local state = player:GetLeftArmState()
	local dummy = self.dummies[player:GetId()]

	if table.find({AnimationState.LaSPlaceTriggeredExplosive, AnimationState.LaSUnderThrowGrenade, AnimationState.LaSThrowTriggeredExplosive}, state) then
		if not dummy then
			dummy = ClientStaticObject.Create({
				model = "wea35-tte.lod",
				position = Vector3(),
				angle = Angle()
			})

			self.dummies[player:GetId()] = dummy
		end

		dummy:SetAngle(player:GetBoneAngle("ragdoll_LeftForeArm"))
		dummy:SetPosition(player:GetBonePosition("ragdoll_LeftForeArm") + dummy:GetAngle() * C4Controller.PlantingOffset)
	elseif state == AnimationState.LaSWieldGrenade or player == LocalPlayer and self.detonationTimer:GetSeconds() < C4Controller.DetonationTimeout then
		if not dummy then
			dummy = ClientStaticObject.Create({
				model = "km05_02d.seq.blz/gp700_01-controller.lod",
				position = Vector3(),
				angle = Angle()
			})

			self.dummies[player:GetId()] = dummy
		end

		dummy:SetAngle(player:GetBoneAngle("ragdoll_LeftForeArm") * Angle(0, (math.pi - (math.pi / 8)) -(math.pi * 0.45 * math.min(self.detonationTimer:GetSeconds(), 0.5)), math.pi * 1.2))
		dummy:SetPosition(player:GetBonePosition("ragdoll_LeftForeArm") + player:GetBoneAngle("ragdoll_LeftForeArm") * C4Controller.DetonationOffset)
	elseif dummy then
		self.dummies[player:GetId()] = nil
		dummy:Remove()
	end
end

C4Controller = C4Controller()
