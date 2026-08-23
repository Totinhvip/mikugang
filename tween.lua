-- [ TP ] bay bang BodyVelocity, thay Tp.lua cua tokaruun/New-MeyyHub
-- (ban do la Luraph v14.7 + whitelist jnkie, khong doc/sua duoc).
--
-- Do that 2026-08-22 tren acc EllieShad0wTurb0 @ place 2753915549:
--   quang  3000 speed 300 -> 300 studs/s, toi dich, giu duoc
--   quang 10000 speed 300 -> 300 studs/s, toi dich, giu duoc  (di THANG, khong chia chang)
--   speed 330            -> 14 studs/s, BI KEO VE   <- 330 vuot tran, server chan. TOI DA 300.
--
-- So voi 2 cach da thu:
--   tween chia chang 200 studs      : 259-262 studs/s, phai chia chang  (giu o tp_tween.lua.bak)
--   BodyVelocity + workspace.Gravity=0: 300 studs/s nhung tat trong luc CA CLIENT
--   BodyVelocity + PlatformStand BAT SUOT : 300 studs/s NHUNG toi noi khong danh duoc boss
--   BodyVelocity KHONG PlatformStand      : dung tren mat dat thi Humanoid ghi lai, 0 studs/s
--   BodyVelocity + PlatformStand chi khi DANG BAY : 301 studs/s va toi noi van danh duoc  <- dung cai nay
--
-- Khong bi "tween back" vi khong set CFrame ma day bang luc, server tu tinh vi tri nen chap nhan.
--
-- API (giu nguyen de kaitun khong phai sua 47 cho goi):
--   getgenv().TP(target)      nhan CFrame hoac Vector3, cho toi noi moi tra ve (true/false)
--   getgenv().TPAsync(target) khong cho, tra ve ngay
--   getgenv().TPStop()        dung bay, tra lai CanCollide + go mover
--   getgenv().TPFlying()      dang bay hay khong
--   _G.TocDoTween             toc do (mac dinh 300, DUNG dat qua 300)
--   _G.TPArrive               coi la toi dich khi con cach bao nhieu studs (mac dinh 8)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

_G.TocDoTween = _G.TocDoTween or 300
_G.TPArrive = _G.TPArrive or 8

-- Nap lai script nhieu lan thi moi lan them 1 Heartbeat, chung day nguoc nhau.
-- (Da dinh o ban tween: 8 TweenBlock lam acc dung im 46s.) Nen don sach truoc.
if getgenv().__TPConns then
	for _, c in ipairs(getgenv().__TPConns) do pcall(function() c:Disconnect() end) end
end
getgenv().__TPConns = {}

local conn, bodyVelocity, bodyGyro, targetPos
local flying = false
local noclipParts = {}
local noclipConn = nil

-- Noclip: ban goc chi tat CanCollide cho HumanoidRootPart nen dau/tay/chan/than van dam tuong
-- (Carter bao 2026-08-22: bay bi tong vao tuong). Phai tat cho MOI BasePart trong Character.
--   CanCollide = khong dam   CanTouch = khong kich hoat vung damage/bay   CanQuery = raycast bo qua
-- Quet 1 lan luc bat dau bay roi nho lai, moi frame chi gan co tren danh sach do
-- (goi GetDescendants moi frame nhu ban file 15 la phi CPU vo ich).
local function trackPart(v)
	if not v:IsA("BasePart") then return end
	if noclipParts[v] ~= nil then return end
	noclipParts[v] = { collide = v.CanCollide, touch = v.CanTouch, query = v.CanQuery }
end

local function scanNoclip(char)
	if not char then return end
	for _, v in ipairs(char:GetDescendants()) do trackPart(v) end
	if noclipConn then noclipConn:Disconnect() end
	-- deo accessory / cam tool giua chung thi bat luon part moi
	noclipConn = char.DescendantAdded:Connect(function(v)
		if v:IsA("BasePart") then trackPart(v) end
	end)
end

local function applyNoclip()
	for v, old in pairs(noclipParts) do
		if v.Parent then
			if v.CanCollide then v.CanCollide = false end
			if v.CanTouch then v.CanTouch = false end
			pcall(function() if v.CanQuery then v.CanQuery = false end end)
		else
			noclipParts[v] = nil
		end
	end
end

local function restoreNoclip()
	if noclipConn then noclipConn:Disconnect() noclipConn = nil end
	for v, old in pairs(noclipParts) do
		if v.Parent then
			pcall(function()
				v.CanCollide = old.collide
				v.CanTouch = old.touch
				v.CanQuery = old.query
			end)
		end
	end
	noclipParts = {}
end

local function removeMovers()
	if bodyVelocity then pcall(function() bodyVelocity:Destroy() end) bodyVelocity = nil end
	if bodyGyro then pcall(function() bodyGyro:Destroy() end) bodyGyro = nil end
end

local function setupMovers(root)
	if not bodyVelocity or bodyVelocity.Parent ~= root then
		if bodyVelocity then pcall(function() bodyVelocity:Destroy() end) end
		bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.Name = "FarmBV"
		bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
		bodyVelocity.Velocity = Vector3.zero
		bodyVelocity.Parent = root
	end
	if not bodyGyro or bodyGyro.Parent ~= root then
		if bodyGyro then pcall(function() bodyGyro:Destroy() end) end
		bodyGyro = Instance.new("BodyGyro")
		bodyGyro.Name = "FarmBG"
		bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
		bodyGyro.P = 9e4
		bodyGyro.D = 500
		bodyGyro.Parent = root
	end
end

local function stopFly()
	flying = false
	targetPos = nil
	if conn then conn:Disconnect() conn = nil end
	removeMovers()
	restoreNoclip()
	local char = LP.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if root then
		root.CanCollide = true
		pcall(function()
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end)
	end
	if hum then hum.PlatformStand = false end
end

local function step()
	if not flying or not targetPos then stopFly() return end
	local char = LP.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if not root or not hum then return end

	-- KHONG dung hum.PlatformStand = true. Do that 2026-08-23 (Carter bao boss Haki khong an damage):
	-- PlatformStand coi nhu nhan vat dang nga -> KHONG dung duoc vu khi. Acc bay toi sat boss
	-- (cach 23 studs, cam Dragon Talon, FastAttack loaded) ma boss khong mat mot diem mau nao;
	-- tat PlatformStand 12s thi boss tu 14733 HP xuong 0 ngay.
	-- BodyVelocity MaxForce 9e9 da du chong trong luc, khong can co nay.
	applyNoclip()
	setupMovers(root)

	local speed = _G.TocDoTween or 300
	local dist = (targetPos - root.Position).Magnitude
	if dist > 5 then
		bodyVelocity.Velocity = (targetPos - root.Position).Unit * speed
		-- Do that 2026-08-23 tren wegkopenri: dung TREN MAT DAT thi Humanoid ghi lai,
		-- BodyVelocity day 300 ma AssemblyLinearVelocity chi ~0.1 -> bay 15 giay di 0 studs.
		-- (Set thang AssemblyLinearVelocity = 200 thi 1 frame sau con 89.) Phai roi dieu khien
		-- Humanoid moi keo duoc: bat PlatformStand -> do lai duoc 301 studs/s.
		-- Ban truoc bat PlatformStand SUOT nen toi noi van khong danh duoc boss (Haki, 14733 HP
		-- khong suy chuyen). Nen chi bat KHI DANG BAY, toi dich la tra lai ngay o nhanh duoi.
		hum.PlatformStand = true
	else
		bodyVelocity.Velocity = Vector3.zero
		hum.PlatformStand = false
	end
	-- Do that 2026-08-23 (Carter bao "nhan vat quay quay quai"): AssemblyAngularVelocity do duoc
	-- (-3, 75, -131) rad/s, huong nhin lech dot=0.760 trong 2 giay.
	-- Nguyen nhan: lookAt(root.Position, targetPos) chay MOI FRAME. Khi toi sat dich (hoac bam
	-- mob dang chay) thi diem nhin gan trung than -> huong lat lien tuc, ma BodyGyro P=9e4 D=500
	-- bam rat manh nen thanh xoay loan.
	-- Sua: (1) chi lai huong khi con cach > 10 studs, gan roi thi giu nguyen huong cu;
	--      (2) nhin PHANG - bo chenh lech Y, khong thi nhan vat chui dau/ngua ra khi bay len xuong.
	if dist > 10 then
		local flat = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
		if (flat - root.Position).Magnitude > 1 then
			bodyGyro.CFrame = CFrame.lookAt(root.Position, flat)
		end
	end
end

local function startFly(target)
	local pos
	if typeof(target) == "Vector3" then pos = target
	elseif typeof(target) == "CFrame" then pos = target.Position
	else return false end
	targetPos = pos
	flying = true
	-- Ngoi thuyen thi HRP bi han vao VehicleSeat, BodyVelocity keo khong noi: do that 2026-08-23,
	-- TP tra false sau 23.6 giay ma chi nhich 42/25,304 studs. Phai roi ghe truoc.
	do
		local hum = LP.Character and LP.Character:FindFirstChildWhichIsA("Humanoid")
		if hum and hum.Sit then hum.Sit = false end
	end
	scanNoclip(LP.Character)
	if not conn then
		conn = RunService.Heartbeat:Connect(function()
			pcall(step)
		end)
		table.insert(getgenv().__TPConns, conn)
	end
	return true
end

table.insert(getgenv().__TPConns, LP.CharacterAdded:Connect(function(char)
	char:WaitForChild("HumanoidRootPart", 5)
	-- Chet giua duong bay (roi xuong bien) thi mover di theo xac cu -> lenh bay coi nhu mat,
	-- acc hoi sinh xong nam im, ben goi TP quay khong cho het gio (Carter bao 2026-08-23:
	-- "nhan nhiem vu dojo cai no rot xuong bien"). Nho lai dich va bay tiep sau khi hoi sinh.
	local resume = flying and targetPos or nil
	removeMovers()
	noclipParts = {}
	stopFly()
	if resume then
		task.wait(1)
		startFly(resume)
	end
end))
table.insert(getgenv().__TPConns, LP.CharacterRemoving:Connect(function()
	stopFly()
end))

getgenv().TPStop = stopFly
getgenv().TPFlying = function() return flying end
getgenv().TPAsync = function(target) return startFly(target) end

getgenv().TP = function(target)
	if not startFly(target) then return false end
	local pos = targetPos
	local arrive = _G.TPArrive or 8
	local deadline = os.clock() + 120
	local stuck, lastDist = 0, nil
	while os.clock() < deadline do
		task.wait(0.15)
		local char = LP.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then break end
		local d = (root.Position - pos).Magnitude
		if d <= arrive then
			-- tra lai dieu khien Humanoid ngay khi toi noi, khong thi treo tai cho voi
			-- PlatformStand = khong dung duoc vu khi (dung loi boss Haki hom truoc)
			local hum = char and char:FindFirstChildWhichIsA("Humanoid")
			if hum then hum.PlatformStand = false end
			-- KHONG stopFly: go luc ra la roi ngay. Do that 2026-08-23: bay xong Y=22,
			-- 3s sau Y=-14 (roi xuong nuoc, chet dan - dung loi Carter bao).
			-- Giu BodyVelocity voi van toc 0 -> treo tai cho, van danh duoc vi khong co PlatformStand.
			-- Muon dat chan xuong dat thi goi getgenv().TPStop().
			return true
		end
		-- khong nhich duoc ~4s lien thi thoi, khoi treo vo han
		if lastDist and math.abs(lastDist - d) < 2 then
			stuck = stuck + 1
			if stuck >= 27 then break end
		else
			stuck = 0
		end
		lastDist = d
	end
	-- het gio hoac ket: van giu bay (khoi roi), chi tra ve ket qua
	local char = LP.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (root.Position - pos).Magnitude <= arrive * 6
end

getgenv().TPLoaded = true
return getgenv().TP
