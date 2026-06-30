local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local MAX_LOCK_DISTANCE   = 75
local LOSE_DISTANCE       = 90
local FOV_DOT_THRESHOLD   = 0.45
local CHECK_LINE_OF_SIGHT = true
local ALLOW_LOCKING_PLAYERS = true

local SHOW_TARGET_NAME      = true
local SHOW_HEALTH_BAR       = true
local SHOW_DISTANCE         = true
local SHOW_TYPE_ICON        = true
local SHOW_OFFSCREEN_ARROW  = true
local TARGET_FOLDER: Instance = Workspace

local ENABLE_SOUND = false
local SOUND_LOCK_ON     = "rbxassetid://0"
local SOUND_UNLOCK      = "rbxassetid://0"
local SOUND_NO_TARGET   = "rbxassetid://0"

local character: Model? = nil
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil

local lockedTarget: Model? = nil

local unlockTarget

local function onCharacterAdded(char: Model)
	character = char
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
	lockedTarget = nil

	humanoid.Died:Connect(function()
		if unlockTarget then
			unlockTarget()
		end
	end)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = Workspace.CurrentCamera
end)

local function makeSound(id: string): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.5
	s.Parent = camera
	return s
end

local sndLockOn, sndUnlock, sndNoTarget
if ENABLE_SOUND then
	sndLockOn = makeSound(SOUND_LOCK_ON)
	sndUnlock = makeSound(SOUND_UNLOCK)
	sndNoTarget = makeSound(SOUND_NO_TARGET)
end

local function playSound(snd: Sound?)
	if ENABLE_SOUND and snd and snd.SoundId ~= "rbxassetid://0" then
		snd:Play()
	end
end

local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LockOnUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 50
screenGui.Parent = playerGui

local BTN_SIZE = 60

local glow = Instance.new("Frame")
glow.Name = "ButtonGlow"
glow.Size = UDim2.new(0, BTN_SIZE + 26, 0, BTN_SIZE + 26)
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
glow.BackgroundTransparency = 0.85
glow.ZIndex = 8
glow.Parent = screenGui

local glowCorner = Instance.new("UICorner")
glowCorner.CornerRadius = UDim.new(1, 0)
glowCorner.Parent = glow

local lockButton = Instance.new("ImageButton")
lockButton.Name = "LockOnButton"
lockButton.Size = UDim2.new(0, BTN_SIZE, 0, BTN_SIZE)
lockButton.AnchorPoint = Vector2.new(0.5, 0.5)
lockButton.Position = UDim2.new(1, -80, 0.55, 0)
lockButton.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
lockButton.BackgroundTransparency = 0.1
lockButton.AutoButtonColor = false
lockButton.Image = ""
lockButton.ZIndex = 10
lockButton.Parent = screenGui

glow.Position = lockButton.Position

local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(1, 0)
btnCorner.Parent = lockButton

local btnStroke = Instance.new("UIStroke")
btnStroke.Thickness = 2
btnStroke.Color = Color3.fromRGB(255, 255, 255)
btnStroke.Transparency = 0.35
btnStroke.Parent = lockButton

local iconRing = Instance.new("Frame")
iconRing.Name = "IconRing"
iconRing.Size = UDim2.new(0.5, 0, 0.5, 0)
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

local iconDot = Instance.new("Frame")
iconDot.Name = "IconDot"
iconDot.Size = UDim2.new(0, 6, 0, 6)
iconDot.AnchorPoint = Vector2.new(0.5, 0.5)
iconDot.Position = UDim2.new(0.5, 0, 0.5, 0)
iconDot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
iconDot.BackgroundTransparency = 1
iconDot.ZIndex = 11
iconDot.Parent = lockButton

local iconDotCorner = Instance.new("UICorner")
iconDotCorner.CornerRadius = UDim.new(1, 0)
iconDotCorner.Parent = iconDot

local noTargetLabel = Instance.new("TextLabel")
noTargetLabel.Name = "NoTargetLabel"
noTargetLabel.AnchorPoint = Vector2.new(0.5, 1)
noTargetLabel.Position = UDim2.new(0.5, 0, 0, -8)
noTargetLabel.Size = UDim2.new(0, 140, 0, 24)
noTargetLabel.BackgroundTransparency = 1
noTargetLabel.Text = "ไม่พบเป้าหมาย"
noTargetLabel.TextColor3 = Color3.fromRGB(255, 170, 60)
noTargetLabel.TextSize = 16
noTargetLabel.Font = Enum.Font.GothamBold
noTargetLabel.TextTransparency = 1
noTargetLabel.ZIndex = 12
noTargetLabel.Parent = lockButton

local glowPulseTween = TweenService:Create(
	glow,
	TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ BackgroundTransparency = 0.65 }
)
glowPulseTween:Play()

local dragging = false
local dragInputPos: Vector2? = nil
local dragStartPos: UDim2? = nil
local hasMoved = false
local DRAG_THRESHOLD = 6

local function syncGlowPosition()
	glow.Position = lockButton.Position
end

local function clampToScreen()
	local viewport = camera.ViewportSize
	local pos = lockButton.Position
	local x = math.clamp(pos.X.Offset, BTN_SIZE * 0.5, math.max(viewport.X - BTN_SIZE * 0.5, BTN_SIZE * 0.5))
	local y = math.clamp(pos.Y.Offset, BTN_SIZE * 0.5, math.max(viewport.Y - BTN_SIZE * 0.5, BTN_SIZE * 0.5))
	lockButton.AnchorPoint = Vector2.new(0.5, 0.5)
	lockButton.Position = UDim2.new(0, x, 0, y)
	syncGlowPosition()
end

local function setLockingVisual(state: boolean)
	if state then
		TweenService:Create(lockButton, TweenInfo.new(0.12), {
			BackgroundColor3 = Color3.fromRGB(220, 50, 50),
		}):Play()
		TweenService:Create(btnStroke, TweenInfo.new(0.12), {
			Color = Color3.fromRGB(255, 140, 140),
		}):Play()
		TweenService:Create(iconDot, TweenInfo.new(0.12), {
			BackgroundTransparency = 0,
		}):Play()
		TweenService:Create(glow, TweenInfo.new(0.12), {
			BackgroundColor3 = Color3.fromRGB(255, 90, 90),
		}):Play()
	else
		TweenService:Create(lockButton, TweenInfo.new(0.12), {
			BackgroundColor3 = Color3.fromRGB(35, 35, 40),
		}):Play()
		TweenService:Create(btnStroke, TweenInfo.new(0.12), {
			Color = Color3.fromRGB(255, 255, 255),
		}):Play()
		TweenService:Create(iconDot, TweenInfo.new(0.12), {
			BackgroundTransparency = 1,
		}):Play()
		TweenService:Create(glow, TweenInfo.new(0.12), {
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		}):Play()
	end
end

local noTargetFadeOutTween = TweenService:Create(noTargetLabel, TweenInfo.new(0.5), {
	TextTransparency = 1,
})

local function flashNoTarget()
	playSound(sndNoTarget)

	TweenService:Create(btnStroke, TweenInfo.new(0.08), {
		Color = Color3.fromRGB(255, 170, 60),
	}):Play()

	noTargetLabel.TextTransparency = 0
	task.delay(0.35, function()
		noTargetFadeOutTween:Play()
	end)

	task.delay(0.25, function()
		if not lockedTarget then
			TweenService:Create(btnStroke, TweenInfo.new(0.2), {
				Color = Color3.fromRGB(255, 255, 255),
			}):Play()
		end
	end)
end

local RETICLE_SIZE = 50
local BRACKET_LEN = 14
local BRACKET_THICK = 3

local reticle = Instance.new("Frame")
reticle.Name = "Reticle"
reticle.Size = UDim2.new(0, RETICLE_SIZE, 0, RETICLE_SIZE)
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.BackgroundTransparency = 1
reticle.Visible = false
reticle.ZIndex = 5
reticle.Parent = screenGui

local reticleScale = Instance.new("UIScale")
reticleScale.Scale = 1
reticleScale.Parent = reticle

local function makeBracketCorner(cornerAnchor: Vector2, xDir: number, yDir: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Bracket"
	holder.AnchorPoint = cornerAnchor
	holder.Position = UDim2.new(cornerAnchor.X, 0, cornerAnchor.Y, 0)
	holder.Size = UDim2.new(0, BRACKET_LEN, 0, BRACKET_LEN)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 6
	holder.Parent = reticle

	local horiz = Instance.new("Frame")
	horiz.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	horiz.BorderSizePixel = 0
	horiz.Size = UDim2.new(0, BRACKET_LEN, 0, BRACKET_THICK)
	horiz.AnchorPoint = Vector2.new(cornerAnchor.X, cornerAnchor.Y)
	horiz.Position = UDim2.new(cornerAnchor.X, 0, cornerAnchor.Y, 0)
	horiz.ZIndex = 6
	horiz.Parent = holder

	local vert = Instance.new("Frame")
	vert.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	vert.BorderSizePixel = 0
	vert.Size = UDim2.new(0, BRACKET_THICK, 0, BRACKET_LEN)
	vert.AnchorPoint = Vector2.new(cornerAnchor.X, cornerAnchor.Y)
	vert.Position = UDim2.new(cornerAnchor.X, 0, cornerAnchor.Y, 0)
	vert.ZIndex = 6
	vert.Parent = holder

	return holder
end

local bracketTL = makeBracketCorner(Vector2.new(0, 0), 1, 1)
local bracketTR = makeBracketCorner(Vector2.new(1, 0), -1, 1)
local bracketBL = makeBracketCorner(Vector2.new(0, 1), 1, -1)
local bracketBR = makeBracketCorner(Vector2.new(1, 1), -1, -1)
local allBrackets = { bracketTL, bracketTR, bracketBL, bracketBR }

local infoRow = Instance.new("Frame")
infoRow.Name = "InfoRow"
infoRow.AnchorPoint = Vector2.new(0.5, 0)
infoRow.Position = UDim2.new(0.5, 0, 1, 6)
infoRow.Size = UDim2.new(0, 180, 0, 18)
infoRow.BackgroundTransparency = 1
infoRow.ZIndex = 6
infoRow.Parent = reticle

local typeIcon = Instance.new("Frame")
typeIcon.Name = "TypeIcon"
typeIcon.AnchorPoint = Vector2.new(0, 0.5)
typeIcon.Position = UDim2.new(0, 0, 0.5, 0)
typeIcon.Size = UDim2.new(0, 10, 0, 10)
typeIcon.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
typeIcon.BackgroundTransparency = 0.1
typeIcon.BorderSizePixel = 0
typeIcon.Visible = SHOW_TYPE_ICON
typeIcon.ZIndex = 7
typeIcon.Parent = infoRow

local typeIconStroke = Instance.new("UIStroke")
typeIconStroke.Thickness = 1.5
typeIconStroke.Color = Color3.fromRGB(255, 60, 60)
typeIconStroke.Parent = typeIcon

local typeIconCorner = Instance.new("UICorner")
typeIconCorner.CornerRadius = UDim.new(0, 0)
typeIconCorner.Parent = typeIcon

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "TargetName"
nameLabel.AnchorPoint = Vector2.new(0, 0.5)
nameLabel.Position = UDim2.new(0, 16, 0.5, 0)
nameLabel.Size = UDim2.new(0, 164, 0, 18)
nameLabel.BackgroundTransparency = 1
nameLabel.Text = ""
nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
nameLabel.TextSize = 14
nameLabel.Font = Enum.Font.GothamBold
nameLabel.TextStrokeTransparency = 0.4
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.Visible = SHOW_TARGET_NAME
nameLabel.ZIndex = 7
nameLabel.Parent = infoRow

local healthBarBg = Instance.new("Frame")
healthBarBg.Name = "HealthBarBg"
healthBarBg.AnchorPoint = Vector2.new(0.5, 0)
healthBarBg.Position = UDim2.new(0.5, 0, 1, 26)
healthBarBg.Size = UDim2.new(0, 70, 0, 6)
healthBarBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
healthBarBg.BackgroundTransparency = 0.2
healthBarBg.BorderSizePixel = 0
healthBarBg.Visible = SHOW_HEALTH_BAR
healthBarBg.ZIndex = 6
healthBarBg.Parent = reticle

local healthBarBgCorner = Instance.new("UICorner")
healthBarBgCorner.CornerRadius = UDim.new(1, 0)
healthBarBgCorner.Parent = healthBarBg

local healthBarFill = Instance.new("Frame")
healthBarFill.Name = "HealthBarFill"
healthBarFill.Size = UDim2.new(1, 0, 1, 0)
healthBarFill.BackgroundColor3 = Color3.fromRGB(90, 220, 110)
healthBarFill.BorderSizePixel = 0
healthBarFill.ZIndex = 7
healthBarFill.Parent = healthBarBg

local healthBarFillCorner = Instance.new("UICorner")
healthBarFillCorner.CornerRadius = UDim.new(1, 0)
healthBarFillCorner.Parent = healthBarFill

local offscreenArrow = Instance.new("TextLabel")
offscreenArrow.Name = "OffscreenArrow"
offscreenArrow.AnchorPoint = Vector2.new(0.5, 0.5)
offscreenArrow.Size = UDim2.new(0, 28, 0, 28)
offscreenArrow.BackgroundTransparency = 1
offscreenArrow.Text = "▲"
offscreenArrow.TextColor3 = Color3.fromRGB(255, 60, 60)
offscreenArrow.TextSize = 26
offscreenArrow.Font = Enum.Font.GothamBold
offscreenArrow.TextStrokeTransparency = 0.3
offscreenArrow.Visible = false
offscreenArrow.ZIndex = 5
offscreenArrow.Parent = screenGui

local function isValidTargetModel(model: Instance): boolean
	if not model:IsA("Model") or model == character then
		return false
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		return false
	end
	local isPlayerChar = Players:GetPlayerFromCharacter(model) ~= nil
	if isPlayerChar and not ALLOW_LOCKING_PLAYERS then
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

local function collectCandidateModels(): {Model}
	local seen: {[Model]: boolean} = {}
	local list: {Model} = {}

	for _, obj in ipairs(TARGET_FOLDER:GetDescendants()) do
		if obj:IsA("Humanoid") and obj.Parent then
			local m = obj.Parent :: Model
			if not seen[m] then
				seen[m] = true
				table.insert(list, m)
			end
		end
	end

	if ALLOW_LOCKING_PLAYERS then
		for _, plr in ipairs(Players:GetPlayers()) do
			local m = plr.Character
			if m and not seen[m] then
				seen[m] = true
				table.insert(list, m)
			end
		end
	end

	return list
end

local function findBestTarget(): Model?
	if not rootPart then
		return nil
	end

	local camPos = camera.CFrame.Position
	local camLook = camera.CFrame.LookVector

	local best: Model? = nil
	local bestScore = -math.huge

	for _, targetModel in ipairs(collectCandidateModels()) do
		if isValidTargetModel(targetModel) then
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

local function validateLockedTarget(target: Model): (boolean, BasePart?, Humanoid?)
	if not target.Parent then
		return false, nil, nil
	end
	local hum = target:FindFirstChildOfClass("Humanoid")
	local hrp = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp or hum.Health <= 0 then
		return false, nil, nil
	end

	local dist = (hrp.Position - camera.CFrame.Position).Magnitude
	if dist > LOSE_DISTANCE then
		return false, nil, nil
	end

	if CHECK_LINE_OF_SIGHT then
		if not hasLineOfSight(camera.CFrame.Position, hrp.Position, {character, target}) then
			return false, nil, nil
		end
	end

	return true, hrp, hum
end

local function getDisplayName(target: Model): string
	local plr = Players:GetPlayerFromCharacter(target)
	if plr then
		return plr.DisplayName
	end
	return target.Name
end

local function updateReticleInfo(targetModel: Model, targetHumanoid: Humanoid, dist: number)
	local isPlayerTarget = Players:GetPlayerFromCharacter(targetModel) ~= nil

	if SHOW_TARGET_NAME or SHOW_DISTANCE then
		local label = ""
		if SHOW_TARGET_NAME then
			label = getDisplayName(targetModel)
		end
		if SHOW_DISTANCE then
			label = label .. (label ~= "" and "  •  " or "") .. string.format("%dm", math.floor(dist))
		end
		nameLabel.Text = label
	end

	if SHOW_TYPE_ICON then
		typeIconCorner.CornerRadius = isPlayerTarget and UDim.new(1, 0) or UDim.new(0, 0)
	end

	if SHOW_HEALTH_BAR then
		local pct = math.clamp(targetHumanoid.Health / math.max(targetHumanoid.MaxHealth, 1), 0, 1)
		healthBarFill.Size = UDim2.new(pct, 0, 1, 0)
		healthBarFill.BackgroundColor3 = Color3.fromRGB(
			255 - math.floor(165 * pct),
			90 + math.floor(130 * pct),
			100
		)
	end
end

local function hideOffscreenArrow()
	offscreenArrow.Visible = false
end

local function updateOffscreenArrow(targetRoot: BasePart)
	if not SHOW_OFFSCREEN_ARROW then
		hideOffscreenArrow()
		return
	end

	local screenPos, onScreen = camera:WorldToViewportPoint(targetRoot.Position)
	if onScreen then
		hideOffscreenArrow()
		return
	end

	local viewport = camera.ViewportSize
	local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
	local dir = Vector2.new(screenPos.X, screenPos.Y) - center

	if screenPos.Z < 0 then
		dir = -dir
	end
	if dir.Magnitude < 1 then
		dir = Vector2.new(0, -1)
	end
	dir = dir.Unit

	local margin = 64
	local maxX = math.max(viewport.X * 0.5 - margin, 1)
	local maxY = math.max(viewport.Y * 0.5 - margin, 1)
	local scaleX = (math.abs(dir.X) > 0.0001) and (maxX / math.abs(dir.X)) or math.huge
	local scaleY = (math.abs(dir.Y) > 0.0001) and (maxY / math.abs(dir.Y)) or math.huge
	local scale = math.min(scaleX, scaleY)

	local edgePoint = center + dir * scale
	offscreenArrow.Position = UDim2.new(0, edgePoint.X, 0, edgePoint.Y)
	offscreenArrow.Rotation = math.deg(math.atan2(dir.X, -dir.Y))
	offscreenArrow.Visible = true
end

local function updateReticlePosition(targetRoot: BasePart, targetModel: Model)
	local head = targetModel:FindFirstChild("Head")
	local worldPoint = (head and (head :: BasePart).Position or targetRoot.Position) + Vector3.new(0, 0.4, 0)
	local screenPos, onScreen = camera:WorldToViewportPoint(worldPoint)

	if onScreen then
		reticle.Visible = true
		reticle.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y)
	else
		reticle.Visible = false
	end

	updateOffscreenArrow(targetRoot)
end

local function playLockSnapAnimation()
	reticleScale.Scale = 0.55
	TweenService:Create(
		reticleScale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

unlockTarget = function()
	if lockedTarget then
		playSound(sndUnlock)
	end
	lockedTarget = nil
	reticle.Visible = false
	hideOffscreenArrow()
	setLockingVisual(false)
end

local function tryLockTarget()
	local target = findBestTarget()
	if target then
		lockedTarget = target
		setLockingVisual(true)
		playLockSnapAnimation()
		playSound(sndLockOn)
	else
		flashNoTarget()
	end
end

local function toggleLock()
	if lockedTarget then
		unlockTarget()
	else
		tryLockTarget()
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
		syncGlowPosition()
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

RunService.Heartbeat:Connect(function()
	if not character or not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	humanoid.AutoRotate = false

	local desiredLookDir: Vector3? = nil

	if lockedTarget then
		local valid, targetRoot, targetHumanoid = validateLockedTarget(lockedTarget)
		if valid and targetRoot and targetHumanoid then
			local toTarget = targetRoot.Position - rootPart.Position
			desiredLookDir = Vector3.new(toTarget.X, 0, toTarget.Z)

			updateReticlePosition(targetRoot, lockedTarget)
			updateReticleInfo(lockedTarget, targetHumanoid, (targetRoot.Position - camera.CFrame.Position).Magnitude)
		else
			unlockTarget()
		end
	end

	if not desiredLookDir then
		local camLook = camera.CFrame.LookVector
		desiredLookDir = Vector3.new(camLook.X, 0, camLook.Z)
	end

	if desiredLookDir.Magnitude > 0.001 then
		rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + desiredLookDir.Unit)
	end
end)

print("🚀 Lock-On System v5.0 Loaded Successfully!")
print("✅ ฟีเจอร์:")
print("  ✓ ล็อคได้ทั้ง NPC และผู้เล่นคนอื่น")
print("  ✓ Reticle แบบมุม (corner bracket) + snap animation ตอนล็อคติด")
print("  ✓ ลูกศรชี้ทิศเป้าตอนเป้าหลุดจอ")
print("  ✓ แสดงชื่อ/ระยะ/หลอดเลือด/ไอคอนประเภทเป้า")
print("  ✓ กรอบ glow รอบปุ่ม + เปลี่ยนสีตอนล็อคติด")
print("  ✓ รองรับเสียง (ใส่ SoundId เองแล้วเปิด ENABLE_SOUND)")
print("  ✓ เป้าหายไป -> ปลดล็อคอัตโนมัติทันที")
print("  ✓ ไม่สแกนทั้งแมพทุกเฟรม / ไม่สร้าง Instance ใหม่ในลูป -> เบาเครื่อง")
