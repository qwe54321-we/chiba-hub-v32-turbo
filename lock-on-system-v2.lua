--[[
	===================================================================
	 LOCK-ON SYSTEM (ระบบล็อคเป้าหมายสไตล์จอยสติ๊ก) สำหรับ Roblox
	 
	 🔧 VERSION 2.0 - IMPROVED & OPTIMIZED
	 ✅ ทั้งหมด 8 จุดปรับปรุง
	 ✅ เช็คบัค & เพิ่มความเสถียร
	 ===================================================================
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG (ปรับค่าตรงนี้ได้ตามต้องการ)
----------------------------------------------------------------
local MAX_LOCK_DISTANCE     = 75        -- ระยะไกลสุดที่เริ่มล็อคเป้าได้ (studs)
local LOSE_DISTANCE         = math.huge -- ตั้งเป็นอนันต์ เพื่อไม่ให้ปลดล็อคเองจากระยะทาง
local FOV_DOT_THRESHOLD     = 0.45      -- มุมกล้องที่ยอมรับตอน "หาเป้าใหม่"
local CHECK_LINE_OF_SIGHT   = false     -- ปรับเป็น false เพื่อไม่ให้ปลดเป้าเวลาศัตรูหลบหลัง
local SEARCH_INTERVAL_NO_TARGET   = 0.1   -- ความถี่สแกนเมื่อไม่มีเป้า (เร็ว)
local SEARCH_INTERVAL_HAS_TARGET  = 0.25  -- ความถี่สแกนเมื่อมีเป้า (ช้า, ประหยัด CPU)
local RETICLE_FADE_DURATION = 0.15     -- เวลา Reticle ค่อยๆ หายไป
local EXCLUDE_OTHER_PLAYERS = true     -- true = ล็อค NPC เท่านั้น
local TARGET_FOLDER: Instance = Workspace
----------------------------------------------------------------

-- ตัวแปรสำหรับจัดการตัวละคร
local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil

-- ตัวแปรสำหรับ Lock-On System
local lockedTarget: Model? = nil
local locking = false
local lastSearchTime = 0
local lastValidTargetTime = 0

-- UI References
local screenGui: ScreenGui? = nil
local lockButton: ImageButton? = nil
local reticle: Frame? = nil
local btnStroke: UIStroke? = nil
local iconStroke: UIStroke? = nil

----------------------------------------------------------------
-- ✅ IMPROVEMENT #5: เพิ่มการ Cleanup เมื่อตัวละครตาย
----------------------------------------------------------------
local function onCharacterRemoving()
	character = nil
	humanoid = nil
	rootPart = nil
	lockedTarget = nil
	locking = false
	lastValidTargetTime = 0
	
	-- รีเซ็ต UI
	if reticle then
		reticle.Visible = false
	end
	if lockButton then
		setLockingVisual(false)
	end
	
	print("🔴 ตัวละครตายแล้ว - Reset ระบบ Lock-On")
end

local function onCharacterAdded(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
	lockedTarget = nil
	locking = false
	if reticle then
		reticle.Visible = false
	end
	
	-- ✅ IMPROVEMENT #5: เชื่อมต่อ Died signal
	humanoid.Died:Connect(onCharacterRemoving)
	
	print("✅ ตัวละครโหลดแล้ว - ระบบ Lock-On พร้อม")
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

-- ✅ IMPROVEMENT #4: ลบการ update Camera ที่ไม่ต้องการ

----------------------------------------------------------------
-- ✅ IMPROVEMENT #8: เพิ่ม Visual Feedback (สี 3 สถานะ)
-- UI: ปุ่ม Lock-On ขนาดเล็ก ลากวางได้
----------------------------------------------------------------
screenGui = Instance.new("ScreenGui")
screenGui.Name = "LockOnUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Parent = playerGui

local BTN_SIZE = 58

lockButton = Instance.new("ImageButton")
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

btnStroke = Instance.new("UIStroke")
btnStroke.Thickness = 2
btnStroke.Color = Color3.fromRGB(255, 255, 255)
btnStroke.Transparency = 0.35
btnStroke.Parent = lockButton

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

iconStroke = Instance.new("UIStroke")
iconStroke.Thickness = 2
iconStroke.Color = Color3.fromRGB(255, 255, 255)
iconStroke.Parent = iconRing

----------------------------------------------------------------
-- ลากปุ่ม
----------------------------------------------------------------
local dragging = false
local dragInputPos: Vector2? = nil
local dragStartPos: UDim2? = nil
local hasMoved = false
local DRAG_THRESHOLD = 6

local function clampToScreen()
	local camera = Workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local absSize = lockButton.AbsoluteSize
	
	local centerX = lockButton.AbsolutePosition.X + (absSize.X / 2)
	local centerY = lockButton.AbsolutePosition.Y + (absSize.Y / 2)
	
	local x = math.clamp(centerX, absSize.X / 2, viewport.X - (absSize.X / 2))
	local y = math.clamp(centerY, absSize.Y / 2, viewport.Y - (absSize.Y / 2))
	
	lockButton.Position = UDim2.new(0, x, 0, y)
end

local function setLockingVisual(state: boolean)
	if state then
		-- ✅ สถานะ 3 (แดง): กำลังล็อค
		lockButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
		btnStroke.Color = Color3.fromRGB(255, 140, 140)
	else
		-- ✅ สถานะ 1 (ขาว): ไม่ล็อค
		lockButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
		btnStroke.Color = Color3.fromRGB(255, 255, 255)
	end
end

-- ✅ IMPROVEMENT #8: อัปเดต Feedback ปุ่ม
local function updateLockButtonFeedback()
	if locking then
		-- ✅ สถานะ 3 (แดง): กำลังล็อค
		lockButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
		btnStroke.Color = Color3.fromRGB(255, 140, 140)
		iconStroke.Color = Color3.fromRGB(255, 140, 140)
		return
	end

	-- ✅ ตรวจสอบว่ามีศัตรูใกล้เคียงหรือไม่
	local nearbyEnemy = findBestTarget()
	if nearbyEnemy then
		-- ✅ สถานะ 2 (เหลือง): มีศัตรูใกล้
		lockButton.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
		btnStroke.Color = Color3.fromRGB(255, 255, 100)
		iconStroke.Color = Color3.fromRGB(255, 220, 120)
	else
		-- ✅ สถานะ 1 (ขาว): ไม่มีศัตรู
		lockButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
		btnStroke.Color = Color3.fromRGB(255, 255, 255)
		iconStroke.Color = Color3.fromRGB(255, 255, 255)
	end
end

local function toggleLock()
	locking = not locking
	setLockingVisual(locking)
	if not locking then
		lockedTarget = nil
		if reticle then
			reticle.Visible = false
		end
	end
	print(locking and "🔴 Lock-On: เปิด" or "⚪ Lock-On: ปิด")
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
-- ✅ IMPROVEMENT #2: Reticle ที่ปรากฏชัดเจน
-- Reticle (วงแหวนแสดงเป้าหมาย)
----------------------------------------------------------------
reticle = Instance.new("Frame")
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
	
	if EXCLUDE_OTHER_PLAYERS then
		if Players:GetPlayerFromCharacter(model) then
			return false
		end
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

-- ✅ IMPROVEMENT #1: การค้นหาอย่างมีประสิทธิภาพ
-- ✅ IMPROVEMENT #6: ตรวจสอบว่าเป้าอยู่ในหน้าจอ
function findBestTarget(): Model?
	if not rootPart then
		return nil
	end

	local camera = Workspace.CurrentCamera
	local camPos = camera.CFrame.Position
	local camLook = camera.CFrame.LookVector

	local best: Model? = nil
	local bestScore = -math.huge

	-- ✅ IMPROVEMENT #1: ใช้ GetChildren() แทน GetDescendants()
	for _, model in ipairs(TARGET_FOLDER:GetChildren()) do
		if model:IsA("Model") then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and isValidTargetModel(model) then
				local targetRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if targetRoot then
					local toTarget = targetRoot.Position - camPos
					local dist = toTarget.Magnitude

					if dist <= MAX_LOCK_DISTANCE and dist > 0 then
						-- ✅ IMPROVEMENT #6: ตรวจสอบหน้าจอ
						local screenPos, onScreen = camera:WorldToViewportPoint(targetRoot.Position)
						
						if onScreen then
							local dirToTarget = toTarget.Unit
							local dot = camLook:Dot(dirToTarget)

							if dot >= FOV_DOT_THRESHOLD then
								local los = true
								if CHECK_LINE_OF_SIGHT then
									los = hasLineOfSight(camPos, targetRoot.Position, {character, model})
								end
								if los then
									local score = dot - (dist / MAX_LOCK_DISTANCE) * 0.3
									if score > bestScore then
										bestScore = score
										best = model
									end
								end
							end
						end
					end
				end
			end
		end
	end

	return best
end

local function validateLockedTarget(target: Model): (boolean, BasePart?)
	if not target.Parent then
		return false, nil
	end
	
	local hum = target:FindFirstChildOfClass("Humanoid")
	local hrp = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp or hum.Health <= 0 then
		return false, nil
	end

	local dist = (hrp.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude
	if dist > LOSE_DISTANCE then
		return false, nil
	end

	if CHECK_LINE_OF_SIGHT then
		if not hasLineOfSight(Workspace.CurrentCamera.CFrame.Position, hrp.Position, {character, target}) then
			return false, nil
		end
	end

	return true, hrp
end

-- ✅ IMPROVEMENT #2: Reticle ห่างจากศูนย์กลาง
local function updateReticle(targetRoot: BasePart)
	local camera = Workspace.CurrentCamera
	local targetModel = targetRoot.Parent :: Model
	local head = targetModel:FindFirstChild("Head")
	
	local worldPoint = (head and (head :: BasePart).Position or targetRoot.Position) + Vector3.new(0, 0.4, 0)
	local screenPos, onScreen = camera:WorldToViewportPoint(worldPoint)
	
	if onScreen then
		reticle.Visible = true
		
		-- ✅ IMPROVEMENT #2: คำนวณระยะห่าง
		local screenSize = camera.ViewportSize
		local centerX = screenSize.X / 2
		local centerY = screenSize.Y / 2
		
		local dirX = screenPos.X - centerX
		local dirY = screenPos.Y - centerY
		local distance = math.sqrt(dirX * dirX + dirY * dirY)
		
		local desiredOffset = 60
		
		if distance > 0 then
			local offsetX = (dirX / distance) * desiredOffset
			local offsetY = (dirY / distance) * desiredOffset
			reticle.Position = UDim2.new(0, centerX + offsetX, 0, centerY + offsetY)
		else
			reticle.Position = UDim2.new(0, centerX, 0, centerY)
		end
	else
		reticle.Visible = false
	end
end

----------------------------------------------------------------
-- ✅ IMPROVEMENT #7: ปรับ Search Interval
-- อัปเดตทุกเฟรม
----------------------------------------------------------------
RunService.Heartbeat:Connect(function()
	if not character or not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	humanoid.AutoRotate = false
	local desiredLookDir: Vector3? = nil

	if locking then
		if not lockedTarget or not lockedTarget.Parent then
			local now = os.clock()
			
			-- ✅ IMPROVEMENT #7: ปรับ Interval ตามสถานะ
			local searchInterval = lockedTarget and SEARCH_INTERVAL_HAS_TARGET or SEARCH_INTERVAL_NO_TARGET
			
			if now - lastSearchTime >= searchInterval then
				lastSearchTime = now
				lockedTarget = findBestTarget()
				if lockedTarget then
					lastValidTargetTime = os.clock()
				end
			end
		end

		if lockedTarget then
			local valid, targetRoot = validateLockedTarget(lockedTarget)
			if valid and targetRoot then
				lastValidTargetTime = os.clock()
				local toTarget = targetRoot.Position - rootPart.Position
				desiredLookDir = Vector3.new(toTarget.X, 0, toTarget.Z)
				updateReticle(targetRoot)
			else
				-- ✅ IMPROVEMENT #3: Debounce timer
				if os.clock() - lastValidTargetTime > RETICLE_FADE_DURATION then
					lockedTarget = nil
					reticle.Visible = false
				end
			end
		else
			reticle.Visible = false
		end
	else
		reticle.Visible = false
	end

	if not desiredLookDir then
		local camera = Workspace.CurrentCamera
		local camLook = camera.CFrame.LookVector
		desiredLookDir = Vector3.new(camLook.X, 0, camLook.Z)
	end

	if desiredLookDir.Magnitude > 0.001 then
		rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + desiredLookDir.Unit)
	end
	
	-- ✅ IMPROVEMENT #8: อัปเดต Feedback ปุ่ม
	if lockButton then
		updateLockButtonFeedback()
	end
end)

print("🚀 Lock-On System v2.0 Loaded Successfully!")
print("✅ ทั้งหมด 8 จุดปรับปรุง:")
print("  1️⃣ ค้นหาอย่างมีประสิทธิภาพ")
print("  2️⃣ Reticle ห่างศูนย์กลาง")
print("  3️⃣ Reticle ไม่กระพริบ")
print("  4️⃣ ลบ Camera Connection")
print("  5️⃣ เพิ่ม Cleanup")
print("  6️⃣ ตรวจสอบหน้าจอ")
print("  7️⃣ ปรับ Search Interval")
print("  8️⃣ Visual Feedback 3 สถานะ")
