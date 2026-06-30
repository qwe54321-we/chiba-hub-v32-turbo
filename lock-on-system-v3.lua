--[[
	===================================================================
	 LOCK-ON SYSTEM (ระบบล็อคเป้าหมายสไตล์จอยสติ๊ก) สำหรับ Roblox
	===================================================================
	วิธีติดตั้ง:
	1. นำสคริปต์นี้ไปวางใน StarterPlayer > StarterPlayerScripts
	   *** ต้องเป็น LocalScript เท่านั้น ***
	2. ไม่ต้องสร้าง UI เอง สคริปต์จะสร้างปุ่มกลมเล็กๆ ให้อัตโนมัติ
	   ลากปุ่มไปวางตรงไหนของจอก็ได้ (รองรับทั้งนิ้วและเมาส์)
	   แตะเฉยๆ = เปิด/ปิดล็อคเป้า, แตะค้างแล้วลาก = ย้ายตำแหน่งปุ่ม
	3. ตัวละครจะ "หันตามทิศกล้องเสมอ" (สไตล์ Shift Lock) แม้ไม่ได้ล็อคเป้า
	   และเมื่อกดล็อคเป้าติดศัตรู ตัวละครจะหันไปทางศัตรูแทนทันที
	   (หันแบบ instant ไม่มีการหน่วง/lerp เพื่อความเร็วสูงสุด)

	ปรับแต่งค่าต่างๆ ได้ที่ CONFIG ด้านล่าง
	===================================================================
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

----------------------------------------------------------------
-- CONFIG (ปรับค่าตรงนี้ได้ตามต้องการ)
----------------------------------------------------------------
local MAX_LOCK_DISTANCE     = 75    -- ระยะไกลสุดที่เริ่มล็อคเป้าได้ (studs)
local LOSE_DISTANCE         = 90    -- ถ้าเป้าห่างเกินนี้ จะปลดล็อคอัตโนมัติ
local FOV_DOT_THRESHOLD     = 0.45  -- มุมกล้องที่ยอมรับตอน "หาเป้าใหม่" (1 = ตรงกลางจอเป๊ะ, 0 = กว้าง 90 องศา)
local CHECK_LINE_OF_SIGHT   = true  -- เช็คว่ามีกำแพง/สิ่งกีดขวางบังเป้าหมายหรือไม่
local SEARCH_INTERVAL       = 0.15  -- ความถี่ในการสแกนหาเป้าใหม่ (วินาที) ตอนยังไม่มีเป้า
local EXCLUDE_OTHER_PLAYERS = true  -- true = ล็อคได้เฉพาะ NPC เท่านั้น, false = ล็อคผู้เล่นคนอื่นได้ด้วย
local TARGET_FOLDER: Instance = Workspace
	-- ถ้ามีศัตรูอยู่ใน Folder เฉพาะ เช่น Workspace.Enemies
	-- ให้เปลี่ยนเป็น Workspace:WaitForChild("Enemies") เพื่อลดภาระการสแกนทั้งแมพ
----------------------------------------------------------------

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil

local lockedTarget: Model? = nil
local locking = false
local lastSearchTime = 0

----------------------------------------------------------------
-- เก็บ reference ตัวละคร
----------------------------------------------------------------
local function onCharacterAdded(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
	lockedTarget = nil
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = Workspace.CurrentCamera
end)

----------------------------------------------------------------
-- UI: ปุ่ม Lock-On ขนาดเล็ก ลากวางได้ทุกตำแหน่งบนจอ
----------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LockOnUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Parent = playerGui

local BTN_SIZE = 58

local lockButton = Instance.new("ImageButton")
lockButton.Name = "LockOnButton"
lockButton.Size = UDim2.new(0, BTN_SIZE, 0, BTN_SIZE)
lockButton.AnchorPoint = Vector2.new(0.5, 0.5)
lockButton.Position = UDim2.new(1, -80, 0.55, 0)
lockButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
lockButton.BackgroundTransparency = 0.15
lockButton.AutoButtonColor = false
lockButton.Image = ""
lockButton.ZIndex = 10
lockButton.Parent = screenGui

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(1, 0)
btnCorner.Parent = lockButton

local btnStroke = Instance.new("UIStroke")
btnStroke.Thickness = 2
btnStroke.Color = Color3.fromRGB(255, 255, 255)
btnStroke.Transparency = 0.35
btnStroke.Parent = lockButton

-- ไอคอนวงแหวนเล็กตรงกลางปุ่ม (ไม่ใช้รูปภาพ เพื่อกันปัญหารูปโหลดไม่ขึ้น)
local iconRing = Instance.new("Frame")
iconRing.Name = "IconRing"
iconRing.Size = UDim2.new(0.45, 0, 0.45, 0)
iconRing.AnchorPoint = Vector2.new(0.5, 0.5)
iconRing.Position = UDim2.new(0.5, 0, 0.5, 0)
iconRing.BackgroundTransparency = 1
iconRing.ZIndex = 11
iconRing.Parent = lockButton

local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(1, 0)
iconCorner.Parent = iconRing

local iconStroke = Instance.new("UIStroke")
iconStroke.Thickness = 2
iconStroke.Color = Color3.fromRGB(255, 255, 255)
iconStroke.Parent = iconRing

----------------------------------------------------------------
-- ลากปุ่มไปวางตำแหน่งไหนของจอก็ได้ (รองรับนิ้วและเมาส์)
----------------------------------------------------------------
local dragging = false
local dragInputPos: Vector2? = nil
local dragStartPos: UDim2? = nil
local hasMoved = false
local DRAG_THRESHOLD = 6

local function clampToScreen()
	local viewport = camera.ViewportSize
	local absPos = lockButton.AbsolutePosition
	local absSize = lockButton.AbsoluteSize
	local x = math.clamp(absPos.X, 0, math.max(viewport.X - absSize.X, 0))
	local y = math.clamp(absPos.Y, 0, math.max(viewport.Y - absSize.Y, 0))
	lockButton.Position = UDim2.new(0, x, 0, y)
end

local function setLockingVisual(state: boolean)
	if state then
		lockButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
		btnStroke.Color = Color3.fromRGB(255, 140, 140)
	else
		lockButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
		btnStroke.Color = Color3.fromRGB(255, 255, 255)
	end
end

local function toggleLock()
	locking = not locking
	setLockingVisual(locking)
	if not locking then
		lockedTarget = nil
	end
end

lockButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		hasMoved = false
		dragInputPos = input.Position
		dragStartPos = lockButton.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging or not dragInputPos or not dragStartPos then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		local delta = input.Position - dragInputPos
		if delta.Magnitude > DRAG_THRESHOLD then
			hasMoved = true
		end
		lockButton.Position = UDim2.new(
			dragStartPos.X.Scale, dragStartPos.X.Offset + delta.X,
			dragStartPos.Y.Scale, dragStartPos.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not dragging then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
		if hasMoved then
			clampToScreen()
		else
			toggleLock()
		end
		dragInputPos = nil
		dragStartPos = nil
	end
end)

----------------------------------------------------------------
-- Reticle (วงแหวนแสดงเป้าหมายที่ล็อคอยู่)
----------------------------------------------------------------
local reticle = Instance.new("Frame")
reticle.Name = "Reticle"
reticle.Size = UDim2.new(0, 44, 0, 44)
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.BackgroundTransparency = 1
reticle.Visible = false
reticle.ZIndex = 5
reticle.Parent = screenGui

local reticleCorner = Instance.new("UICorner")
reticleCorner.CornerRadius = UDim.new(1, 0)
reticleCorner.Parent = reticle

local reticleStroke = Instance.new("UIStroke")
reticleStroke.Thickness = 3
reticleStroke.Color = Color3.fromRGB(255, 60, 60)
reticleStroke.Parent = reticle

----------------------------------------------------------------
-- ระบบหาเป้าหมาย
----------------------------------------------------------------
local function isValidTargetModel(model: Instance): boolean
	if not model:IsA("Model") or model == character then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		return false
	end
	if EXCLUDE_OTHER_PLAYERS and Players:GetPlayerFromCharacter(model) then
		return false
	end
	return true
end

local function hasLineOfSight(fromPos: Vector3, toPos: Vector3, ignore: {Instance}): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local result = Workspace:Raycast(fromPos, toPos - fromPos, params)
	return result == nil
end

local function findBestTarget(): Model?
	if not rootPart then
		return nil
	end

	local camPos = camera.CFrame.Position
	local camLook = camera.CFrame.LookVector

	local best: Model? = nil
	local bestScore = -math.huge

	for _, obj in ipairs(TARGET_FOLDER:GetDescendants()) do
		if obj:IsA("Humanoid") and obj.Parent and isValidTargetModel(obj.Parent) then
			local targetModel = obj.Parent :: Model
			local targetRoot = targetModel:FindFirstChild("HumanoidRootPart") :: BasePart
			local toTarget = targetRoot.Position - camPos
			local dist = toTarget.Magnitude

			if dist <= MAX_LOCK_DISTANCE and dist > 0 then
				local dirToTarget = toTarget.Unit
				local dot = camLook:Dot(dirToTarget)

				if dot >= FOV_DOT_THRESHOLD then
					local los = true
					if CHECK_LINE_OF_SIGHT then
						los = hasLineOfSight(camPos, targetRoot.Position, {character, targetModel})
					end
					if los then
						local score = dot - (dist / MAX_LOCK_DISTANCE) * 0.3
						if score > bestScore then
							bestScore = score
							best = targetModel
						end
					end
				end
			end
		end
	end

	return best
end

-- ตรวจว่าเป้าที่ล็อคอยู่ ยังใช้ได้อยู่ไหม คืนค่า (valid, targetRootPart)
local function validateLockedTarget(target: Model): (boolean, BasePart?)
	if not target.Parent then
		return false, nil
	end
	local hum = target:FindFirstChildOfClass("Humanoid")
	local hrp = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp or hum.Health <= 0 then
		return false, nil
	end

	local dist = (hrp.Position - camera.CFrame.Position).Magnitude
	if dist > LOSE_DISTANCE then
		return false, nil
	end

	if CHECK_LINE_OF_SIGHT then
		if not hasLineOfSight(camera.CFrame.Position, hrp.Position, {character, target}) then
			return false, nil
		end
	end

	return true, hrp
end

local function updateReticle(targetRoot: BasePart)
	local targetModel = targetRoot.Parent :: Model
	local head = targetModel:FindFirstChild("Head")
	local worldPoint = (head and (head :: BasePart).Position or targetRoot.Position) + Vector3.new(0, 0.4, 0)
	local screenPos, onScreen = camera:WorldToViewportPoint(worldPoint)
	if onScreen then
		reticle.Visible = true
		reticle.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y)
	else
		reticle.Visible = false
	end
end

----------------------------------------------------------------
-- อัปเดตทุกเฟรม: หาเป้า + หมุนตัวละคร (เร็วสุด ไม่มีหน่วง)
----------------------------------------------------------------
RunService.Heartbeat:Connect(function()
	if not character or not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	-- ควบคุมการหันของตัวละครเองเสมอ (สไตล์ Shift Lock)
	humanoid.AutoRotate = false

	local desiredLookDir: Vector3? = nil

	if locking then
		if not lockedTarget or not lockedTarget.Parent then
			local now = os.clock()
			if now - lastSearchTime >= SEARCH_INTERVAL then
				lastSearchTime = now
				lockedTarget = findBestTarget()
			end
		end

		if lockedTarget then
			local valid, targetRoot = validateLockedTarget(lockedTarget)
			if valid and targetRoot then
				local toTarget = targetRoot.Position - rootPart.Position
				desiredLookDir = Vector3.new(toTarget.X, 0, toTarget.Z)
				updateReticle(targetRoot)
			else
				lockedTarget = nil
				reticle.Visible = false
			end
		else
			reticle.Visible = false
		end
	else
		reticle.Visible = false
	end

	if not desiredLookDir then
		-- ไม่ได้ล็อคเป้า -> หันตามทิศกล้องเสมอ
		local camLook = camera.CFrame.LookVector
		desiredLookDir = Vector3.new(camLook.X, 0, camLook.Z)
	end

	if desiredLookDir.Magnitude > 0.001 then
		rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + desiredLookDir.Unit)
	end
end)

print("🚀 Lock-On System v3.0 Loaded Successfully!")
print("✅ ฟีเจอร์:")
print("  ✓ Reticle ตรงกลางจอ")
print("  ✓ Check Line of Sight")
print("  ✓ หมุนเร็วสูงสุด (Instant)")
print("  ✓ ลากปุ่มได้ทั้งจอ")
