-- [ BRING MOB ] tach tu kaitun.lua (dong 1116-1223) de dung chung cho nhieu script.
-- Sua o day 1 lan, moi script keo ve deu duoc.
--
-- Cach dung:
--   loadstring(game:HttpGet("<link raw github>"))()
--   -- xong la no tu chay. Bat/tat: _G.BringMobs = false
--
-- API:
--   _G.BringMobs        bat/tat keo mob            (mac dinh true)
--   _G.BringOwnerCheck  bo qua mob khong so huu    (mac dinh true)
--   _G.BringMoverGuard  xoa mover cua game gan vao (mac dinh true)
--   _G.BringRadius      ban kinh keo               (mac dinh 275)
--   getgenv().BringStop()    nha het mob + ngat Heartbeat
--   getgenv().BringCount()   dang keo bao nhieu con
--   _G.BringMoverGuardCount  dem so mover da xoa (de kiem guard co chay khong)
--
-- Nguon cac con so:
--   275 studs      : ban kinh cu cua kaitun, chay that on dinh
--   P=2e9 D=5e5    : BodyPosition du manh de thang mover cua game
--   raycast 500    : tim mat dat de mob dung ngang chan, khong lo lung tren dau
--   AuroraBP/BG    : ten cu, GIU NGUYEN vi mover guard loc theo ten nay

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer

_G.BringMobs = (_G.BringMobs ~= false)
_G.BringOwnerCheck = (_G.BringOwnerCheck ~= false)
_G.BringMoverGuard = (_G.BringMoverGuard ~= false)
_G.BringRadius = _G.BringRadius or 275

-- Nap lai script nhieu lan thi moi lan them 1 Heartbeat + 1 DescendantAdded, chung danh nhau.
-- (Da dinh loi nay o tp.lua: 8 TweenBlock lam acc dung im.) Nen don sach truoc.
if getgenv().__BringConns then
	for _, c in ipairs(getgenv().__BringConns) do pcall(function() c:Disconnect() end) end
end
getgenv().__BringConns = {}

local activeMobs = {}

local function playerRoot()
	local char = LP.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function stopOne(mob)
	local data = activeMobs[mob]
	if not data then return end
	if data.rootPart then pcall(function() data.rootPart.CanCollide = true end) end
	if data.bodyPos then pcall(function() data.bodyPos:Destroy() end) end
	if data.bodyGyro then pcall(function() data.bodyGyro:Destroy() end) end
	activeMobs[mob] = nil
end

local function startOne(mob)
	if activeMobs[mob] then return end
	local rootPart = mob:FindFirstChild("HumanoidRootPart")
	local humanoid = mob:FindFirstChild("Humanoid")
	if not rootPart or not humanoid then return end

	-- khong so huu network thi server bo qua moi luc keo -> dung phi cong
	if _G.BringOwnerCheck and isnetworkowner and mob.PrimaryPart then
		local ok, owner = pcall(isnetworkowner, mob.PrimaryPart)
		if ok and not owner then return end
	end

	local bodyPos = Instance.new("BodyPosition")
	bodyPos.Name = "AuroraBP"
	bodyPos.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bodyPos.P = 2000000000
	bodyPos.D = 500000
	bodyPos.Parent = rootPart

	local bodyGyro = Instance.new("BodyGyro")
	bodyGyro.Name = "AuroraBG"
	bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
	bodyGyro.Parent = rootPart

	activeMobs[mob] = { rootPart = rootPart, humanoid = humanoid, bodyPos = bodyPos, bodyGyro = bodyGyro }
	pcall(function() rootPart.CanCollide = false end)
end

-- Game (hoac script khac) gan BodyMover/AlignPosition/... vao mob dang keo de giang lai.
-- Thay la xoa ngay, tru 2 mover cua minh.
local enemies = Workspace:FindFirstChild("Enemies")
if enemies then
	table.insert(getgenv().__BringConns, enemies.DescendantAdded:Connect(function(item)
		if not _G.BringMoverGuard then return end
		if item.Name == "AuroraBP" or item.Name == "AuroraBG" then return end
		if not (item:IsA("BodyMover") or item:IsA("AlignPosition")
			or item:IsA("AlignOrientation") or item:IsA("LinearVelocity")) then return end
		task.defer(function()
			local root = item.Parent
			local model = root and root.Parent
			if model and activeMobs[model] then
				pcall(function() item:Destroy() end)
				_G.BringMoverGuardCount = (_G.BringMoverGuardCount or 0) + 1
			end
		end)
	end))
end

local function update()
	if not _G.BringMobs then
		for mob in pairs(activeMobs) do stopOne(mob) end
		return
	end
	local root = playerRoot()
	if not root then
		for mob in pairs(activeMobs) do stopOne(mob) end
		return
	end
	local pos = root.Position
	local folder = Workspace:FindFirstChild("Enemies")
	if not folder then return end
	local radius = _G.BringRadius or 275

	local toRemove = {}
	for mob, data in pairs(activeMobs) do
		if not data.rootPart or not data.rootPart.Parent or not data.humanoid
			or data.humanoid.Health <= 0
			or (data.rootPart.Position - pos).Magnitude > radius then
			table.insert(toRemove, mob)
		end
	end
	for _, mob in ipairs(toRemove) do stopOne(mob) end

	for _, mob in ipairs(folder:GetChildren()) do
		if not activeMobs[mob] then
			local humanoid = mob:FindFirstChild("Humanoid")
			local rootPart = mob:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and rootPart
				and (rootPart.Position - pos).Magnitude <= radius then
				startOne(mob)
			end
		end
	end

	-- keo mob ve ngang chan minh, khong lo lung tren dau
	local groundY = pos.Y - 3
	do
		local ray = Ray.new(pos + Vector3.new(0, 10, 0), Vector3.new(0, -500, 0))
		local _, hit = Workspace:FindPartOnRayWithIgnoreList(ray, { LP.Character, folder })
		if hit then groundY = hit.Y + 2 end
	end
	local target = Vector3.new(pos.X, groundY, pos.Z)

	for _, data in pairs(activeMobs) do
		if data.rootPart and data.bodyPos and data.bodyGyro then
			data.bodyPos.Position = target
			data.bodyGyro.CFrame = CFrame.new(target)
			pcall(function()
				data.rootPart.AssemblyLinearVelocity = Vector3.zero
				data.rootPart.AssemblyAngularVelocity = Vector3.zero
			end)
		end
	end
end

pcall(function() sethiddenproperty(LP, "SimulationRadius", math.huge) end)
table.insert(getgenv().__BringConns, RunService.Heartbeat:Connect(update))

getgenv().BringStop = function()
	_G.BringMobs = false
	for mob in pairs(activeMobs) do stopOne(mob) end
	for _, c in ipairs(getgenv().__BringConns or {}) do pcall(function() c:Disconnect() end) end
	getgenv().__BringConns = {}
end

getgenv().BringCount = function()
	local n = 0
	for _ in pairs(activeMobs) do n = n + 1 end
	return n
end

getgenv().BringLoaded = true
return true
