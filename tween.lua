-- [ TP ] thay cho Tp.lua cua tokaruun/New-MeyyHub (Luraph v14.7 + whitelist jnkie).
-- API giu nguyen de kaitun dung duoc ngay: getgenv().TP(target) nhan ca CFrame lan Vector3.
--
-- Nguon cua tung con so trong file nay:
--   nguong 200 studs   : co che tween cua AutoBelt8Draco (kaitun.lua Heartbeat) - qua 200 thi keo
--                        khoi ve nguoi, chinh la cai chan teleport xa 1 frame bi security kick.
--   chia chang 900     : do that - server chan dich chuyen lien tuc qua ~900 studs, tween chang dai
--                        khong bao gio toi (memory project_server_gioi_han_dich_lien_tuc).
--   toc do 330         : nguong Carter chot, da thu 1600 -> disconnect.
--   SetSpawnPoint      : decompiled place_7449423635/ReplicatedStorage/DialoguesList/init.lua:268
--                        tra 0 = chi Pirates moi set duoc, -1 = that bai, nil = dung xa NPC.
--   15 toa do Home     : do that 2026-08-22 tren server df478a77, quet workspace.NPCs ten
--                        "Set Home Point" (NPCManager/NPCList.lua:110 dang ky NPC nay).
--   BypassMinDist 5000 : TPHome ton ~22s co dinh (cho chet + hoi sinh), tween chay ~205 studs/s
--                        -> hoa von quanh 4500 studs. Duoi nguong nay tween thang nhanh hon.
--
-- Verify chay that 2026-08-22 (acc yasonnubpa, Pirates, server 772e6fe0):
--   TP 600 studs   : 600/600   2.4s = 250 studs/s
--   TP 2500 studs  : 2500/2500 12.4s = 201 studs/s
--   TPSetHomeAt(8) : true sau 11.0s, LastSpawnPoint Hydra1 -> Hydra2, TPHomePos = 3356,54,2209
--   TPHome()       : tu cach home 3711 studs -> ve cach home 364 studs trong 21.8s

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer

getgenv().TPConfig = getgenv().TPConfig or {}
local Config = getgenv().TPConfig
Config.Speed = Config.Speed or 330
-- Do that 2026-08-22 tren quang 2500 studs (acc yasonnubpa, server 772e6fe0):
--   step 700 pause 0.30 ->  25 studs/s  (bi keo nguoc ve, dung chang lon)
--   step 500 pause 0.50 -> 128 studs/s
--   step 200 pause 0.25 -> 121 studs/s
--   step 200 pause 0.05 -> 155 studs/s
--   step 200 pause 0.10 -> 201 studs/s  <- tot nhat, di du 2500/2500 trong 12.4s
-- Moc so sanh ban Luraph cua tokaruun: 296 studs/s (2483/2500).
Config.StepDist = Config.StepDist or 200
Config.StepPause = Config.StepPause or 0.1
Config.FollowRange = Config.FollowRange or 200
Config.ArriveDist = Config.ArriveDist or 8
Config.BypassMinDist = Config.BypassMinDist or 5000
-- Carter chot 2026-08-22: dung TWEEN THUAN buoc 200 studs, TAT bypass.
-- Ly do: ban Luraph dat 300 studs nen hay bi keo nguoc (tween back); 200 studs thi khong bi.
-- Do that: buoc 200 + nghi 0.1s = 201 studs/s, di du 2500/2500 studs, khong lan nao bi keo ve.
-- Muon thu lai bypass: _G.TPConfig.UseBypass = true truoc khi nap (anchor hop 4026 studs/s
-- nhung chi chot duoc vi tri khi co PlayerSpawn trong ~3000 studs, xem memory project_tp_bypass_island).
Config.UseBypass = (Config.UseBypass == true)
Config.BypassGain = Config.BypassGain or 0.6
Config.BypassJump = Config.BypassJump or 3000
Config.BypassHold = Config.BypassHold or 0.6
Config.BypassMaxHops = Config.BypassMaxHops or 30
Config.Timeout = Config.Timeout or 25

local HOME_POINTS = {
	Vector3.new(-259, 20, 5473),
	Vector3.new(-12551, 336, -7410),
	Vector3.new(-5053, 314, -3007),
	Vector3.new(-11378, 331, -10392),
	Vector3.new(2252, 33, -6874),
	Vector3.new(-914, 58, -10889),
	Vector3.new(4554, 51, -1438),
	Vector3.new(3356, 54, 2209),
	Vector3.new(507, 24, -12439),
	Vector3.new(-9549, 141, 5535),
	Vector3.new(-16280, 49, 537),
	Vector3.new(-1896, 37, -11887),
	Vector3.new(-2077, 37, -10217),
	Vector3.new(5161, 1003, 484),
	Vector3.new(-1073, 24, -14179),
}

local Character, Humanoid, Root
local TweenBlock, CurrentTween
local shouldTween = false
local lastTarget = nil

local function refreshCharacter(char)
	Character = char or LP.Character
	if not Character then return false end
	Humanoid = Character:FindFirstChildOfClass("Humanoid")
	Root = Character:FindFirstChild("HumanoidRootPart")
	if TweenBlock and TweenBlock.Parent and Root then
		TweenBlock.CFrame = Root.CFrame
	end
	return Root ~= nil
end

local function ensureBlock()
	if TweenBlock and TweenBlock.Parent then return TweenBlock end
	TweenBlock = Instance.new("Part")
	TweenBlock.Name = "TP_TweenBlock"
	TweenBlock.Size = Vector3.new(1, 1, 1)
	TweenBlock.Anchored = true
	TweenBlock.CanCollide = false
	TweenBlock.CanTouch = false
	TweenBlock.CanQuery = false
	TweenBlock.Transparency = 1
	TweenBlock.CFrame = (Root and Root.CFrame) or CFrame.new()
	TweenBlock.Parent = Workspace
	return TweenBlock
end

local function stopTween()
	shouldTween = false
	if CurrentTween then
		pcall(function() CurrentTween:Cancel() end)
		CurrentTween = nil
	end
	if Root then
		local clip = Root:FindFirstChild("TP_BodyClip")
		if clip then clip:Destroy() end
	end
end

local function toCFrame(target)
	if typeof(target) == "Vector3" then return CFrame.new(target) end
	if typeof(target) == "CFrame" then return target end
	return nil
end

-- Nap lai script nhieu lan thi moi lan tao them 1 TweenBlock + 1 Heartbeat, chung keo nhan vat
-- ve cac huong khac nhau -> acc dung im. Do that 2026-08-22: 8 block ton tai cung luc, TP tra false
-- va di 0 studs trong 46s. Nen phai don sach truoc khi khoi tao.
for _, o in ipairs(Workspace:GetChildren()) do
	if o.Name == "TP_TweenBlock" then pcall(function() o:Destroy() end) end
end
if getgenv().__TPConns then
	for _, c in ipairs(getgenv().__TPConns) do pcall(function() c:Disconnect() end) end
end
getgenv().__TPConns = {}
do
	local hrp0 = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	if hrp0 then
		hrp0.Anchored = false
		local clip = hrp0:FindFirstChild("TP_BodyClip")
		if clip then clip:Destroy() end
	end
end

refreshCharacter()
ensureBlock()

local function nearestHomeOf(pos)
	local best, bestDist
	for _, hp in ipairs(HOME_POINTS) do
		local d = (hp - pos).Magnitude
		if not bestDist or d < bestDist then best, bestDist = hp, d end
	end
	return best, bestDist
end

-- Hoc home point dang dat o dau: LastSpawnPoint chi luu TEN ("Hydra1"), khong co toa do.
-- Moi lan hoi sinh, neu cho spawn nam sat mot NPC "Set Home Point" thi do chinh la home.
table.insert(getgenv().__TPConns, LP.CharacterAdded:Connect(function(char)
	task.wait(1)
	refreshCharacter(char)
	if Root then
		local hp, d = nearestHomeOf(Root.Position)
		if hp and d and d < 300 then
			getgenv().TPHomePos = hp
		end
	end
end))

table.insert(getgenv().__TPConns, RunService.Heartbeat:Connect(function()
	if not Character or not Character.Parent or not Root or not Root.Parent then
		refreshCharacter()
		return
	end
	if not (shouldTween and TweenBlock and TweenBlock.Parent) then
		return
	end
	if (Root.Position - TweenBlock.Position).Magnitude <= Config.FollowRange then
		Root.CFrame = TweenBlock.CFrame
	else
		TweenBlock.CFrame = Root.CFrame
	end
	for _, part in ipairs(Character:GetDescendants()) do
		if part:IsA("BasePart") then part.CanCollide = false end
	end
	if not Root:FindFirstChild("TP_BodyClip") then
		local bv = Instance.new("BodyVelocity")
		bv.Name = "TP_BodyClip"
		bv.MaxForce = Vector3.new(100000, 100000, 100000)
		bv.Velocity = Vector3.zero
		bv.Parent = Root
	end
end))

local function tweenStep(target)
	if not refreshCharacter() then return false end
	ensureBlock()
	shouldTween = true
	if CurrentTween then pcall(function() CurrentTween:Cancel() end) end

	local dist = (target.Position - Root.Position).Magnitude
	if dist <= Config.ArriveDist then
		TweenBlock.CFrame = target
		Root.CFrame = target
		return true
	end

	TweenBlock.CFrame = Root.CFrame
	local speed = math.max(tonumber(Config.Speed) or 330, 50)
	CurrentTween = TweenService:Create(
		TweenBlock,
		TweenInfo.new(dist / speed, Enum.EasingStyle.Linear),
		{ CFrame = target }
	)
	CurrentTween:Play()

	local deadline = os.clock() + math.min(dist / speed + 5, Config.Timeout)
	while os.clock() < deadline do
		task.wait(0.1)
		if not Root or not Root.Parent then
			if not refreshCharacter() then return false end
		end
		if (Root.Position - target.Position).Magnitude <= Config.ArriveDist * 2 then
			return true
		end
	end
	return (Root.Position - target.Position).Magnitude <= Config.ArriveDist * 4
end

local function holdingPhysicalFruit()
	for _, cont in ipairs({ LP.Character, LP.Backpack }) do
		if cont then
			for _, t in ipairs(cont:GetChildren()) do
				if t:IsA("Tool") and t:FindFirstChild("Fruit") then return true, t.Name end
			end
		end
	end
	return false
end

local function nearestHome(pos)
	local best, bestDist
	for _, hp in ipairs(HOME_POINTS) do
		local d = (hp - pos).Magnitude
		if not bestDist or d < bestDist then best, bestDist = hp, d end
	end
	return best, bestDist
end

local function setSpawnHere()
	local ok, res = pcall(function()
		return ReplicatedStorage.Remotes.CommF_:InvokeServer("SetSpawnPoint")
	end)
	if not ok then return false, "rpc" end
	if res == 0 then return false, "chi Pirates moi set duoc" end
	if res == -1 then return false, "that bai" end
	if res == nil then return false, "dung xa NPC" end
	return true
end

local function resetToHome()
	local held, name = holdingPhysicalFruit()
	if held then
		return false, "dang giu fruit vat ly (" .. tostring(name) .. "), reset se mat vao kho"
	end
	local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return false, "khong co Humanoid" end
	stopTween()
	hum.Health = 0
	local deadline = os.clock() + 20
	repeat task.wait(0.3) until (LP.Character and LP.Character ~= Character) or os.clock() > deadline
	task.wait(1.5)
	refreshCharacter(LP.Character)
	return Root ~= nil
end

-- [ ANCHOR HOP ] day la TP bypass that, do duoc 2026-08-22: 11671 studs trong 2.9s = 4000 studs/s
-- (tween thuong chi 201-259 studs/s, ban Luraph 296 studs/s).
-- Co che: nhay CFrame <= 3000 studs roi ANCHORED=true + ghi CFrame moi frame trong ~0.6s.
-- Server chap nhan vi tri moi thay vi keo ve; bo neo la o luon do.
-- Nhay ma KHONG neo thi bi keo ve sach (do: 1000/3000/5000 studs deu giu duoc 0-269 studs).
-- Nhay qua xa cung hong: 8727 studs -> bi keo ve, home khong doi.
local function anchorHop(dest)
	local holding = true
	task.spawn(function()
		while holding do
			local hh = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
			if hh then
				hh.CFrame = CFrame.new(dest)
				hh.Velocity = Vector3.zero
				hh.Anchored = true
			end
			RunService.Heartbeat:Wait()
		end
	end)
	task.wait(Config.BypassHold)
	holding = false
	task.wait(0.1)
	local hh = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	if hh then hh.Anchored = false end
	return refreshCharacter() and (Root.Position - dest).Magnitude < 200
end

-- Doi home point bang cach nhay toi PlayerSpawn cua dao roi neo lai:
-- workspace._WorldOrigin.PlayerSpawns.<Team>.<Ten> (16 diem: Hydra1/2/3, Loaf, IceCream, Peanut,
-- PineappleTown, SeaCastle, SubmergedIsland, Tiki, BigMansion, CandyCane, Chocolate, Default,
-- GreatTree, HauntedCastle). Game tu goi CommF_("SetLastSpawnPoint", <ten>) khi minh dung do
-- (calling_script = Workspace.Characters.<acc>.LastSpawnPoint, bat duoc bang spy).
-- Goi remote do THANG mà khong dung tai cho thi tra 1 nhung home KHONG doi.
getgenv().TPSetHomeIsland = function(islandName)
	local team = LP.Team and LP.Team.Name or "Pirates"
	local root = workspace:FindFirstChild("_WorldOrigin")
	local folder = root and root:FindFirstChild("PlayerSpawns")
	folder = folder and folder:FindFirstChild(team)
	local sp = folder and folder:FindFirstChild(islandName)
	if not sp then return false, "khong co spawn point ten " .. tostring(islandName) end
	local part = sp:IsA("BasePart") and sp or sp:FindFirstChildWhichIsA("BasePart")
	if not part then return false, "spawn point khong co Part" end
	local d = LP:FindFirstChild("Data")
	local before = d and d:FindFirstChild("LastSpawnPoint") and tostring(d.LastSpawnPoint.Value) or ""
	if not travel(CFrame.new(part.Position + Vector3.new(0, 3, 0))) then return false, "khong toi duoc" end
	for _ = 1, 12 do
		task.wait(0.25)
		local now = d and d:FindFirstChild("LastSpawnPoint") and tostring(d.LastSpawnPoint.Value) or ""
		if now == islandName then
			getgenv().TPHomePos = part.Position
			return true
		end
	end
	return false, "dung dung cho nhung home khong doi"
end

local function travel(target)
	local cf = toCFrame(target)
	if not cf then return false end
	if not refreshCharacter() then return false end

	lastTarget = cf
	local total = (cf.Position - Root.Position).Magnitude

	-- [ BYPASS DAY DU ] do 2026-08-22:
	--   anchor hop dua toi dich 11671 studs trong 2.9s (4026 studs/s) NHUNG 3s sau bi keo ve cho cu
	--   -> vi tri chua duoc "chot". Phai hop toi PlayerSpawn cua dao, doi home tu doi, roi RESET.
	--   Sau reset moi hoi sinh that su o dao do. Day chinh la chuoi Carter mo ta:
	--   tele bypass -> set spawn point -> reset nhan vat.
	if Config.UseBypass and total >= Config.BypassMinDist then
		local held, fname = holdingPhysicalFruit()
		if held then
			warn("[TP] bo qua bypass: dang giu " .. tostring(fname))
		else
			local team = LP.Team and LP.Team.Name or "Pirates"
			local wo = workspace:FindFirstChild("_WorldOrigin")
			local spFolder = wo and wo:FindFirstChild("PlayerSpawns")
			spFolder = spFolder and spFolder:FindFirstChild(team)
			-- chon PlayerSpawn gan dich nhat
			local best, bestPart, bestDist
			if spFolder then
				for _, sp in ipairs(spFolder:GetChildren()) do
					local part = sp:IsA("BasePart") and sp or sp:FindFirstChildWhichIsA("BasePart")
					if part then
						local dGoal = (cf.Position - part.Position).Magnitude
						if not bestDist or dGoal < bestDist then best, bestPart, bestDist = sp, part, dGoal end
					end
				end
			end
			-- chi bypass khi spawn do that su gan dich hon cho dang dung
			if bestPart and bestDist < total * Config.BypassGain then
				local d = LP:FindFirstChild("Data")
				for _ = 1, Config.BypassMaxHops do
					if not refreshCharacter() then break end
					local remain = (bestPart.Position - Root.Position).Magnitude
					if remain <= 150 then break end
					local step = math.min(Config.BypassJump, remain)
					local dir = (bestPart.Position - Root.Position).Unit
					if not anchorHop(Root.Position + dir * step) then break end
				end
				-- doi home tu doi (game goi SetLastSpawnPoint khi minh dung tai spawn)
				local changed = false
				for _ = 1, 12 do
					task.wait(0.2)
					local now = d and d:FindFirstChild("LastSpawnPoint") and tostring(d.LastSpawnPoint.Value) or ""
					if now == best.Name then changed = true break end
				end
				if changed then
					getgenv().TPHomePos = bestPart.Position
					resetToHome()
					if refreshCharacter() then
						total = (cf.Position - Root.Position).Magnitude
					end
				end
			end
		end
	end

	-- guard phai co gian theo quang duong: truoc day cung 60 chang -> tran 60*200 = 12000 studs,
	-- do that 2026-08-22 di tu home #1 sang home #2 (~12000 studs) bi cat giua duong, con 5862 studs.
	local guard = 0
	local guardMax = math.ceil(total / math.max(Config.StepDist, 1)) + 40
	local stuckAt, stuckCount = nil, 0
	while true do
		if not refreshCharacter() then return false end
		local remain = (cf.Position - Root.Position).Magnitude
		if remain <= Config.ArriveDist * 2 then
			stopTween()
			return true
		end
		-- khong nhich duoc 8 vong lien tiep thi thoi, khoi treo vo han
		if stuckAt and math.abs(stuckAt - remain) < 5 then
			stuckCount = stuckCount + 1
			if stuckCount >= 8 then
				stopTween()
				return false
			end
		else
			stuckCount = 0
		end
		stuckAt = remain
		guard = guard + 1
		if guard > guardMax then
			stopTween()
			return false
		end
		local step = cf
		if remain > Config.StepDist then
			local dir = (cf.Position - Root.Position).Unit
			step = CFrame.new(Root.Position + dir * Config.StepDist)
		end
		tweenStep(step)
		-- Do that 2026-08-22 (quang 2500 studs, acc yasonnubpa):
		--   chia chang lien tuc khong nghi -> ket o ~700 studs, tra false (900/600/400 deu vay).
		--   chang 500 + stopTween + nghi 0.5s -> di du 2500/2500 trong 19.5s = 128 studs/s.
		--   nghi 1.5s thi tut con 17 studs/s, nen dung tang nghi.
		stopTween()
		if remain > Config.StepDist then
			task.wait(Config.StepPause)
		end
	end
end

getgenv().TP = function(target)
	return travel(target)
end

-- Di toi NPC "Set Home Point" thu i roi dat home o do. Dung truoc khi can bypass toi vung do.
getgenv().TPSetHomeAt = function(i)
	local hp = HOME_POINTS[i]
	if not hp then return false, "khong co home point so " .. tostring(i) end
	if not travel(CFrame.new(hp + Vector3.new(0, 4, 0))) then return false, "khong toi duoc NPC" end
	task.wait(1)
	local ok, why = setSpawnHere()
	if ok then getgenv().TPHomePos = hp end
	return ok, why
end

-- Ve thang home point hien tai (nhanh nhat, khong phu thuoc quang duong).
getgenv().TPHome = function()
	return resetToHome()
end

getgenv().TPStop = stopTween
getgenv().TPHomePoints = HOME_POINTS
getgenv().TPSetSpawnHere = setSpawnHere
getgenv().TPResetToHome = resetToHome
getgenv().TPLoaded = true

return getgenv().TP
