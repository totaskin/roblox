-- EnemyManager.luau
-- Spawns enemies, moves them along waypoints, handles death and base damage

local WaveData     = require(game.ReplicatedStorage.Shared.WaveData)
local EnemyPath    = require(game.ReplicatedStorage.Shared.EnemyPath)

local EnemyManager = {}

local activeEnemies: { [string]: any } = {}
local enemyIdCounter = 0
local mapName = "Map1"
local mapOffset = Vector3.new(0, 0, 0)
local onEnemyKilled: ((enemyData: any) -> ())? = nil
local onEnemyReachedEnd: ((enemyData: any) -> ())? = nil
local cachedWaypoints: { Vector3 }? = nil

local WAYPOINT_REACH_DIST = 4

local function getWaypoints(): { Vector3 }
	if cachedWaypoints then return cachedWaypoints end
	local mapFolder = workspace:FindFirstChild(mapName)
	if mapFolder then
		local points: { { index: number, pos: Vector3 } } = {}
		for _, part in ipairs(mapFolder:GetChildren()) do
			local index = tonumber(part.Name:match("Waypoint(%d+)"))
			if index then table.insert(points, { index = index, pos = part.Position }) end
		end
		if #points > 0 then
			table.sort(points, function(a, b) return a.index < b.index end)
			local waypoints = {}
			for _, p in ipairs(points) do table.insert(waypoints, p.pos + mapOffset) end
			cachedWaypoints = waypoints
			print("[EnemyManager] Loaded", #waypoints, "waypoints from Workspace." .. mapName)
			return waypoints
		end
	end
	local mapData = EnemyPath.getMap(mapName)
	local rawWaypoints = mapData.waypoints
	local offsetWaypoints = {}
	for _, wp in ipairs(rawWaypoints) do table.insert(offsetWaypoints, wp + mapOffset) end
	cachedWaypoints = offsetWaypoints
	return cachedWaypoints
end

local function newEnemyId(): string
	enemyIdCounter += 1
	return "enemy_" .. enemyIdCounter
end

function EnemyManager.setMap(name: string) mapName = name; cachedWaypoints = nil end
function EnemyManager.setMapOffset(offset: Vector3) mapOffset = offset; cachedWaypoints = nil end
function EnemyManager.onKilled(callback: (enemyData: any) -> ()) onEnemyKilled = callback end
function EnemyManager.onReachedEnd(callback: (enemyData: any) -> ()) onEnemyReachedEnd = callback end

local ENEMY_COLORS = {
	Grunt      = { body = Color3.fromRGB(0,   140, 60),  accent = Color3.fromRGB(255, 200, 0)   },
	Runner     = { body = Color3.fromRGB(255, 100, 0),   accent = Color3.fromRGB(255, 220, 50)  },
	Brute      = { body = Color3.fromRGB(0,   80,  200), accent = Color3.fromRGB(255, 255, 255) },
	Swarm      = { body = Color3.fromRGB(255, 50,  200), accent = Color3.fromRGB(255, 150, 255) },
	Armored    = { body = Color3.fromRGB(90,  50,  20),  accent = Color3.fromRGB(255, 240, 220) },
	BossGrunt  = { body = Color3.fromRGB(200, 0,   200), accent = Color3.fromRGB(255, 255, 0)   },
	BossRunner = { body = Color3.fromRGB(255, 0,   0),   accent = Color3.fromRGB(0,   255, 0)   },
	BossBrute  = { body = Color3.fromRGB(255, 200, 50),  accent = Color3.fromRGB(200, 50,  0)   },
	BossVoid   = { body = Color3.fromRGB(0,   255, 150), accent = Color3.fromRGB(255, 0,   100) },
}

local function addPart(model, name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cframe
	p.Anchored = true; p.CanCollide = false; p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function spawnEnemyModel(enemyData: any, startPos: Vector3): Model
	local model = Instance.new("Model")
	model.Name = enemyData.name
	local s = enemyData.size
	local palette = ENEMY_COLORS[enemyData.type] or ENEMY_COLORS.Grunt
	local bc = palette.body
	local ac = palette.accent
	local b = startPos
	local black = Color3.fromRGB(0,0,0)
	local white = Color3.fromRGB(255,255,255)
	local grey = Color3.fromRGB(160,160,160)
	local darkGrey = Color3.fromRGB(80,80,80)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"; root.Size = Vector3.new(0.1,0.1,0.1)
	root.Position = b; root.Anchored = true; root.CanCollide = false; root.Transparency = 1
	root.Parent = model

	local eType = enemyData.type or "Grunt"

	if eType == "Grunt" or eType == "BossGrunt" then
		-- BOMBARDIRO CROCODILO: flat croc body, open jaw with teeth, bulging eyes,
		-- scaly ridges, bomber wings, propeller beanie, 4 legs, long tail
		-- BOSSGUNT = LA VACA SATURNO: saturn ring, cow horns, cow spots, udder
		addPart(model,"Body",Vector3.new(1.8*s,0.9*s,3.2*s),CFrame.new(b+Vector3.new(0,1.0*s,0)),bc)
		addPart(model,"Belly",Vector3.new(1.4*s,0.15*s,2.8*s),CFrame.new(b+Vector3.new(0,0.5*s,0)),Color3.fromRGB(120,200,100))
		addPart(model,"Snout",Vector3.new(0.9*s,0.5*s,1.8*s),CFrame.new(b+Vector3.new(0,1.15*s,-2.2*s)),bc)
		addPart(model,"Jaw",Vector3.new(0.8*s,0.3*s,1.6*s),CFrame.new(b+Vector3.new(0,0.55*s,-2.1*s)),bc)
		addPart(model,"ToothL1",Vector3.new(0.12*s,0.2*s,0.12*s),CFrame.new(b+Vector3.new(-0.35*s,0.8*s,-2.8*s)),white)
		addPart(model,"ToothR1",Vector3.new(0.12*s,0.2*s,0.12*s),CFrame.new(b+Vector3.new(0.35*s,0.8*s,-2.8*s)),white)
		addPart(model,"ToothL2",Vector3.new(0.12*s,0.2*s,0.12*s),CFrame.new(b+Vector3.new(-0.35*s,0.8*s,-2.4*s)),white)
		addPart(model,"ToothR2",Vector3.new(0.12*s,0.2*s,0.12*s),CFrame.new(b+Vector3.new(0.35*s,0.8*s,-2.4*s)),white)
		addPart(model,"NostrilL",Vector3.new(0.15*s,0.1*s,0.15*s),CFrame.new(b+Vector3.new(-0.2*s,1.45*s,-3.0*s)),Color3.fromRGB(0,80,30))
		addPart(model,"NostrilR",Vector3.new(0.15*s,0.1*s,0.15*s),CFrame.new(b+Vector3.new(0.2*s,1.45*s,-3.0*s)),Color3.fromRGB(0,80,30))
		addPart(model,"EyeBulgeL",Vector3.new(0.45*s,0.45*s,0.45*s),CFrame.new(b+Vector3.new(-0.45*s,1.7*s,-1.0*s)),bc)
		addPart(model,"EyeBulgeR",Vector3.new(0.45*s,0.45*s,0.45*s),CFrame.new(b+Vector3.new(0.45*s,1.7*s,-1.0*s)),bc)
		addPart(model,"EyeWhiteL",Vector3.new(0.3*s,0.3*s,0.15*s),CFrame.new(b+Vector3.new(-0.45*s,1.8*s,-1.25*s)),white)
		addPart(model,"EyeWhiteR",Vector3.new(0.3*s,0.3*s,0.15*s),CFrame.new(b+Vector3.new(0.45*s,1.8*s,-1.25*s)),white)
		addPart(model,"PupilL",Vector3.new(0.15*s,0.15*s,0.08*s),CFrame.new(b+Vector3.new(-0.45*s,1.8*s,-1.33*s)),black)
		addPart(model,"PupilR",Vector3.new(0.15*s,0.15*s,0.08*s),CFrame.new(b+Vector3.new(0.45*s,1.8*s,-1.33*s)),black)
		for ri=0,4 do addPart(model,"Ridge"..ri,Vector3.new(0.2*s,0.3*s,0.3*s),CFrame.new(b+Vector3.new(0,1.55*s,-1.0*s+ri*0.7*s)),Color3.fromRGB(0,100,40)) end
		addPart(model,"LegFL",Vector3.new(0.45*s,0.7*s,0.45*s),CFrame.new(b+Vector3.new(-0.7*s,0.35*s,-1.0*s)),bc)
		addPart(model,"LegFR",Vector3.new(0.45*s,0.7*s,0.45*s),CFrame.new(b+Vector3.new(0.7*s,0.35*s,-1.0*s)),bc)
		addPart(model,"LegBL",Vector3.new(0.45*s,0.7*s,0.45*s),CFrame.new(b+Vector3.new(-0.7*s,0.35*s,1.0*s)),bc)
		addPart(model,"LegBR",Vector3.new(0.45*s,0.7*s,0.45*s),CFrame.new(b+Vector3.new(0.7*s,0.35*s,1.0*s)),bc)
		addPart(model,"Tail1",Vector3.new(0.5*s,0.4*s,1.2*s),CFrame.new(b+Vector3.new(0,0.9*s,2.0*s)),bc)
		addPart(model,"Tail2",Vector3.new(0.3*s,0.25*s,1.0*s),CFrame.new(b+Vector3.new(0,0.85*s,3.0*s)),bc)
		addPart(model,"WingL",Vector3.new(1.6*s,0.1*s,1.0*s),CFrame.new(b+Vector3.new(-1.2*s,1.5*s,0.2*s))*CFrame.Angles(0,0,math.rad(-15)),ac)
		addPart(model,"WingR",Vector3.new(1.6*s,0.1*s,1.0*s),CFrame.new(b+Vector3.new(1.2*s,1.5*s,0.2*s))*CFrame.Angles(0,0,math.rad(15)),ac)
		if eType == "BossGrunt" then
			addPart(model,"SaturnRing",Vector3.new(5*s,0.12*s,5*s),CFrame.new(b+Vector3.new(0,1.3*s,0))*CFrame.Angles(math.rad(15),0,0),ac,Enum.Material.Neon)
			addPart(model,"HornL",Vector3.new(0.15*s,0.8*s,0.15*s),CFrame.new(b+Vector3.new(-0.6*s,2.2*s,-0.8*s))*CFrame.Angles(0,0,math.rad(-20)),white)
			addPart(model,"HornR",Vector3.new(0.15*s,0.8*s,0.15*s),CFrame.new(b+Vector3.new(0.6*s,2.2*s,-0.8*s))*CFrame.Angles(0,0,math.rad(20)),white)
			addPart(model,"CowSpot1",Vector3.new(0.6*s,0.08*s,0.6*s),CFrame.new(b+Vector3.new(0.4*s,1.5*s,0.5*s)),black)
			addPart(model,"CowSpot2",Vector3.new(0.5*s,0.08*s,0.7*s),CFrame.new(b+Vector3.new(-0.3*s,1.5*s,-0.3*s)),black)
			addPart(model,"Udder",Vector3.new(0.5*s,0.3*s,0.5*s),CFrame.new(b+Vector3.new(0,0.35*s,0.3*s)),Color3.fromRGB(255,180,180))
		else
			addPart(model,"BeanieBase",Vector3.new(0.7*s,0.25*s,0.7*s),CFrame.new(b+Vector3.new(0,1.95*s,-0.8*s)),Color3.fromRGB(220,30,30))
			addPart(model,"BeanieNub",Vector3.new(0.15*s,0.2*s,0.15*s),CFrame.new(b+Vector3.new(0,2.15*s,-0.8*s)),ac)
			addPart(model,"PropA",Vector3.new(1.0*s,0.06*s,0.18*s),CFrame.new(b+Vector3.new(0,2.25*s,-0.8*s)),grey,Enum.Material.Metal)
			addPart(model,"PropB",Vector3.new(0.18*s,0.06*s,1.0*s),CFrame.new(b+Vector3.new(0,2.25*s,-0.8*s)),grey,Enum.Material.Metal)
		end

	elseif eType == "Runner" or eType == "BossRunner" then
		-- TUNG TUNG TUNG SAHUR / BRR BRR PATAPIM
		-- Giant drumstick man on stilt legs, drum torso, drumstick arms, tiny head
		local skinTone = Color3.fromRGB(200,150,100)
		local legH = 3.2*s
		-- Stilt legs with thigh/shin/knee joints
		addPart(model,"ThighL",Vector3.new(0.28*s,legH*0.5,0.28*s),CFrame.new(b+Vector3.new(-0.45*s,legH*0.75,0)),skinTone)
		addPart(model,"ThighR",Vector3.new(0.28*s,legH*0.5,0.28*s),CFrame.new(b+Vector3.new(0.45*s,legH*0.75,0)),skinTone)
		addPart(model,"ShinL",Vector3.new(0.22*s,legH*0.5,0.22*s),CFrame.new(b+Vector3.new(-0.45*s,legH*0.25,0)),skinTone)
		addPart(model,"ShinR",Vector3.new(0.22*s,legH*0.5,0.22*s),CFrame.new(b+Vector3.new(0.45*s,legH*0.25,0)),skinTone)
		addPart(model,"KneeL",Vector3.new(0.38*s,0.38*s,0.38*s),CFrame.new(b+Vector3.new(-0.45*s,legH*0.5,0)),Color3.fromRGB(180,130,80))
		addPart(model,"KneeR",Vector3.new(0.38*s,0.38*s,0.38*s),CFrame.new(b+Vector3.new(0.45*s,legH*0.5,0)),Color3.fromRGB(180,130,80))
		-- Feet with toes
		addPart(model,"FootL",Vector3.new(0.55*s,0.22*s,0.8*s),CFrame.new(b+Vector3.new(-0.45*s,0.11*s,-0.1*s)),ac)
		addPart(model,"FootR",Vector3.new(0.55*s,0.22*s,0.8*s),CFrame.new(b+Vector3.new(0.45*s,0.11*s,-0.1*s)),ac)
		addPart(model,"ToeL1",Vector3.new(0.15*s,0.1*s,0.2*s),CFrame.new(b+Vector3.new(-0.55*s,0.05*s,-0.55*s)),ac)
		addPart(model,"ToeR1",Vector3.new(0.15*s,0.1*s,0.2*s),CFrame.new(b+Vector3.new(0.55*s,0.05*s,-0.55*s)),ac)
		-- Drum torso (layered with skin membrane, rims, tension rods)
		local drumY = legH + 0.8*s
		addPart(model,"DrumShell",Vector3.new(1.8*s,1.6*s,1.8*s),CFrame.new(b+Vector3.new(0,drumY,0)),bc)
		addPart(model,"DrumSkin",Vector3.new(1.6*s,0.06*s,1.6*s),CFrame.new(b+Vector3.new(0,drumY+0.83*s,0)),Color3.fromRGB(240,220,180))
		addPart(model,"DrumRimT",Vector3.new(1.9*s,0.14*s,1.9*s),CFrame.new(b+Vector3.new(0,drumY+0.86*s,0)),ac,Enum.Material.Metal)
		addPart(model,"DrumRimB",Vector3.new(1.9*s,0.14*s,1.9*s),CFrame.new(b+Vector3.new(0,drumY-0.86*s,0)),ac,Enum.Material.Metal)
		-- Tension rods around drum
		for ri=0,5 do
			local angle = math.rad(ri * 60)
			local rx = math.cos(angle) * 0.92*s
			local rz = math.sin(angle) * 0.92*s
			addPart(model,"Rod"..ri,Vector3.new(0.06*s,1.2*s,0.06*s),CFrame.new(b+Vector3.new(rx,drumY,rz)),grey,Enum.Material.Metal)
		end
		-- Zig-zag stripes (front, back, sides)
		addPart(model,"StripeF1",Vector3.new(1.82*s,0.12*s,0.12*s),CFrame.new(b+Vector3.new(0,drumY+0.35*s,-0.9*s)),ac)
		addPart(model,"StripeF2",Vector3.new(1.82*s,0.12*s,0.12*s),CFrame.new(b+Vector3.new(0,drumY-0.35*s,-0.9*s)),ac)
		addPart(model,"StripeB1",Vector3.new(1.82*s,0.12*s,0.12*s),CFrame.new(b+Vector3.new(0,drumY+0.35*s,0.9*s)),ac)
		addPart(model,"StripeS1",Vector3.new(0.12*s,0.12*s,1.82*s),CFrame.new(b+Vector3.new(-0.9*s,drumY,0)),ac)
		addPart(model,"StripeS2",Vector3.new(0.12*s,0.12*s,1.82*s),CFrame.new(b+Vector3.new(0.9*s,drumY,0)),ac)
		-- Drumstick arms (shaft + rounded tip)
		addPart(model,"ArmShaftL",Vector3.new(0.14*s,0.14*s,2.0*s),CFrame.new(b+Vector3.new(-1.1*s,drumY+0.3*s,-0.2*s))*CFrame.Angles(math.rad(-25),0,0),Color3.fromRGB(180,140,80))
		addPart(model,"ArmShaftR",Vector3.new(0.14*s,0.14*s,2.0*s),CFrame.new(b+Vector3.new(1.1*s,drumY+0.3*s,-0.2*s))*CFrame.Angles(math.rad(-25),0,0),Color3.fromRGB(180,140,80))
		addPart(model,"ArmL",Vector3.new(0.4*s,0.4*s,0.4*s),CFrame.new(b+Vector3.new(-1.1*s,drumY+0.7*s,-1.1*s)),ac)
		addPart(model,"ArmR",Vector3.new(0.4*s,0.4*s,0.4*s),CFrame.new(b+Vector3.new(1.1*s,drumY+0.7*s,-1.1*s)),ac)
		-- Neck
		addPart(model,"Neck",Vector3.new(0.3*s,0.4*s,0.3*s),CFrame.new(b+Vector3.new(0,drumY+1.0*s,0)),skinTone)
		-- Head (rounder, with facial features)
		local headY = drumY + 1.5*s
		addPart(model,"Head",Vector3.new(0.9*s,0.9*s,0.9*s),CFrame.new(b+Vector3.new(0,headY,0)),skinTone)
		addPart(model,"Headband",Vector3.new(0.95*s,0.18*s,0.95*s),CFrame.new(b+Vector3.new(0,headY+0.25*s,0)),ac)
		addPart(model,"HeadbandKnot",Vector3.new(0.2*s,0.15*s,0.3*s),CFrame.new(b+Vector3.new(0,headY+0.25*s,0.5*s)),ac)
		-- Eyes with detail
		addPart(model,"EyeWL",Vector3.new(0.25*s,0.28*s,0.12*s),CFrame.new(b+Vector3.new(-0.22*s,headY+0.08*s,-0.44*s)),white)
		addPart(model,"EyeWR",Vector3.new(0.25*s,0.28*s,0.12*s),CFrame.new(b+Vector3.new(0.22*s,headY+0.08*s,-0.44*s)),white)
		addPart(model,"IrisL",Vector3.new(0.14*s,0.14*s,0.06*s),CFrame.new(b+Vector3.new(-0.22*s,headY+0.08*s,-0.51*s)),Color3.fromRGB(80,50,20))
		addPart(model,"IrisR",Vector3.new(0.14*s,0.14*s,0.06*s),CFrame.new(b+Vector3.new(0.22*s,headY+0.08*s,-0.51*s)),Color3.fromRGB(80,50,20))
		addPart(model,"PupilL",Vector3.new(0.08*s,0.1*s,0.04*s),CFrame.new(b+Vector3.new(-0.22*s,headY+0.08*s,-0.55*s)),black)
		addPart(model,"PupilR",Vector3.new(0.08*s,0.1*s,0.04*s),CFrame.new(b+Vector3.new(0.22*s,headY+0.08*s,-0.55*s)),black)
		addPart(model,"BrowL",Vector3.new(0.28*s,0.06*s,0.1*s),CFrame.new(b+Vector3.new(-0.22*s,headY+0.28*s,-0.42*s)),Color3.fromRGB(120,80,40))
		addPart(model,"BrowR",Vector3.new(0.28*s,0.06*s,0.1*s),CFrame.new(b+Vector3.new(0.22*s,headY+0.28*s,-0.42*s)),Color3.fromRGB(120,80,40))
		-- Nose and mouth
		addPart(model,"Nose",Vector3.new(0.12*s,0.12*s,0.1*s),CFrame.new(b+Vector3.new(0,headY-0.05*s,-0.48*s)),Color3.fromRGB(180,130,90))
		addPart(model,"Mouth",Vector3.new(0.35*s,0.1*s,0.06*s),CFrame.new(b+Vector3.new(0,headY-0.22*s,-0.44*s)),Color3.fromRGB(180,50,50))
		-- Ears
		addPart(model,"EarL",Vector3.new(0.08*s,0.2*s,0.15*s),CFrame.new(b+Vector3.new(-0.48*s,headY+0.1*s,0)),skinTone)
		addPart(model,"EarR",Vector3.new(0.08*s,0.2*s,0.15*s),CFrame.new(b+Vector3.new(0.48*s,headY+0.1*s,0)),skinTone)
		if eType == "BossRunner" then
			-- BRR BRR PATAPIM: glowing aura, spiked headband, neon drumsticks
			addPart(model,"AuraL",Vector3.new(0.5*s,0.5*s,0.5*s),CFrame.new(b+Vector3.new(-1.1*s,drumY+0.7*s,-1.1*s)),Color3.fromRGB(0,255,100),Enum.Material.Neon)
			addPart(model,"AuraR",Vector3.new(0.5*s,0.5*s,0.5*s),CFrame.new(b+Vector3.new(1.1*s,drumY+0.7*s,-1.1*s)),Color3.fromRGB(0,255,100),Enum.Material.Neon)
			for si=0,3 do
				local angle = math.rad(si * 90)
				addPart(model,"Spike"..si,Vector3.new(0.1*s,0.35*s,0.1*s),CFrame.new(b+Vector3.new(math.cos(angle)*0.5*s,headY+0.45*s,math.sin(angle)*0.5*s)),Color3.fromRGB(255,0,0),Enum.Material.Neon)
			end
		end

	elseif eType == "Brute" or eType == "BossBrute" then
		-- TRALALERO TRALALA / SPAGHETTINO MACARONINO
		-- Blue shark body on human legs with sneakers, detailed anatomy
		local jeans = Color3.fromRGB(60,60,150)
		local shoeWhite = Color3.fromRGB(240,240,240)
		local gumColor = Color3.fromRGB(180,30,30)
		-- Human legs (thigh, shin, knee cap)
		addPart(model,"ThighL",Vector3.new(0.55*s,0.9*s,0.55*s),CFrame.new(b+Vector3.new(-0.55*s,1.05*s,0)),jeans)
		addPart(model,"ThighR",Vector3.new(0.55*s,0.9*s,0.55*s),CFrame.new(b+Vector3.new(0.55*s,1.05*s,0)),jeans)
		addPart(model,"KneeCapL",Vector3.new(0.3*s,0.2*s,0.3*s),CFrame.new(b+Vector3.new(-0.55*s,0.65*s,-0.2*s)),Color3.fromRGB(50,50,130))
		addPart(model,"KneeCapR",Vector3.new(0.3*s,0.2*s,0.3*s),CFrame.new(b+Vector3.new(0.55*s,0.65*s,-0.2*s)),Color3.fromRGB(50,50,130))
		addPart(model,"ShinL",Vector3.new(0.45*s,0.75*s,0.45*s),CFrame.new(b+Vector3.new(-0.55*s,0.38*s,0)),jeans)
		addPart(model,"ShinR",Vector3.new(0.45*s,0.75*s,0.45*s),CFrame.new(b+Vector3.new(0.55*s,0.38*s,0)),jeans)
		-- Sneakers (detailed: upper, sole, laces, tongue)
		addPart(model,"ShoeL",Vector3.new(0.6*s,0.35*s,1.0*s),CFrame.new(b+Vector3.new(-0.55*s,0.18*s,-0.15*s)),shoeWhite)
		addPart(model,"ShoeR",Vector3.new(0.6*s,0.35*s,1.0*s),CFrame.new(b+Vector3.new(0.55*s,0.18*s,-0.15*s)),shoeWhite)
		addPart(model,"SoleL",Vector3.new(0.6*s,0.1*s,1.0*s),CFrame.new(b+Vector3.new(-0.55*s,0.04*s,-0.15*s)),darkGrey)
		addPart(model,"SoleR",Vector3.new(0.6*s,0.1*s,1.0*s),CFrame.new(b+Vector3.new(0.55*s,0.04*s,-0.15*s)),darkGrey)
		addPart(model,"TongueL",Vector3.new(0.3*s,0.15*s,0.2*s),CFrame.new(b+Vector3.new(-0.55*s,0.38*s,-0.5*s)),shoeWhite)
		addPart(model,"TongueR",Vector3.new(0.3*s,0.15*s,0.2*s),CFrame.new(b+Vector3.new(0.55*s,0.38*s,-0.5*s)),shoeWhite)
		addPart(model,"LaceL",Vector3.new(0.2*s,0.04*s,0.3*s),CFrame.new(b+Vector3.new(-0.55*s,0.35*s,-0.35*s)),Color3.fromRGB(255,50,50))
		addPart(model,"LaceR",Vector3.new(0.2*s,0.04*s,0.3*s),CFrame.new(b+Vector3.new(0.55*s,0.35*s,-0.35*s)),Color3.fromRGB(255,50,50))
		-- Shark body (torpedo, layered)
		addPart(model,"SharkBody",Vector3.new(2.2*s,1.6*s,3.0*s),CFrame.new(b+Vector3.new(0,2.4*s,0)),bc)
		addPart(model,"SharkBelly",Vector3.new(1.8*s,0.6*s,2.6*s),CFrame.new(b+Vector3.new(0,1.7*s,0)),white)
		addPart(model,"SharkSide",Vector3.new(2.25*s,0.3*s,2.8*s),CFrame.new(b+Vector3.new(0,2.1*s,0)),Color3.fromRGB(0,60,170))
		-- Shark nose (tapered snout)
		addPart(model,"Snout",Vector3.new(1.4*s,1.0*s,1.4*s),CFrame.new(b+Vector3.new(0,2.6*s,-1.9*s)),bc)
		addPart(model,"SnoutTip",Vector3.new(0.8*s,0.6*s,0.6*s),CFrame.new(b+Vector3.new(0,2.5*s,-2.5*s)),bc)
		-- Grinning mouth with gums and teeth
		addPart(model,"GumTop",Vector3.new(1.1*s,0.1*s,0.9*s),CFrame.new(b+Vector3.new(0,2.15*s,-2.0*s)),gumColor)
		addPart(model,"GumBot",Vector3.new(1.1*s,0.1*s,0.9*s),CFrame.new(b+Vector3.new(0,1.8*s,-2.0*s)),gumColor)
		addPart(model,"MouthInside",Vector3.new(0.9*s,0.25*s,0.7*s),CFrame.new(b+Vector3.new(0,1.97*s,-2.0*s)),Color3.fromRGB(120,20,30))
		-- Teeth (upper + lower rows)
		for ti=0,5 do
			local tx = -0.4*s + ti*0.16*s
			addPart(model,"ToothU"..ti,Vector3.new(0.08*s,0.18*s,0.08*s),CFrame.new(b+Vector3.new(tx,2.05*s,-2.4*s)),white)
			addPart(model,"ToothD"..ti,Vector3.new(0.07*s,0.15*s,0.07*s),CFrame.new(b+Vector3.new(tx,1.88*s,-2.4*s)),white)
		end
		-- Dorsal fin (tall, layered)
		addPart(model,"DorsalFin",Vector3.new(0.14*s,1.6*s,1.2*s),CFrame.new(b+Vector3.new(0,3.8*s,0)),bc)
		addPart(model,"DorsalEdge",Vector3.new(0.06*s,1.4*s,0.8*s),CFrame.new(b+Vector3.new(0,3.9*s,0.3*s)),Color3.fromRGB(0,60,170))
		-- Pectoral fins (arms, with finger-like tips)
		addPart(model,"FinArmL",Vector3.new(1.4*s,0.18*s,0.7*s),CFrame.new(b+Vector3.new(-1.5*s,2.5*s,-0.3*s))*CFrame.Angles(0,0,math.rad(-30)),bc)
		addPart(model,"FinArmR",Vector3.new(1.4*s,0.18*s,0.7*s),CFrame.new(b+Vector3.new(1.5*s,2.5*s,-0.3*s))*CFrame.Angles(0,0,math.rad(30)),bc)
		addPart(model,"FinTipL",Vector3.new(0.3*s,0.1*s,0.4*s),CFrame.new(b+Vector3.new(-2.2*s,2.7*s,-0.3*s)),Color3.fromRGB(0,60,170))
		addPart(model,"FinTipR",Vector3.new(0.3*s,0.1*s,0.4*s),CFrame.new(b+Vector3.new(2.2*s,2.7*s,-0.3*s)),Color3.fromRGB(0,60,170))
		-- Tail fin (vertical, forked)
		addPart(model,"TailBase",Vector3.new(0.12*s,0.8*s,0.6*s),CFrame.new(b+Vector3.new(0,2.6*s,1.8*s)),bc)
		addPart(model,"TailForkUp",Vector3.new(0.1*s,0.6*s,0.3*s),CFrame.new(b+Vector3.new(0,3.2*s,2.0*s))*CFrame.Angles(math.rad(-20),0,0),bc)
		addPart(model,"TailForkDn",Vector3.new(0.1*s,0.6*s,0.3*s),CFrame.new(b+Vector3.new(0,2.0*s,2.0*s))*CFrame.Angles(math.rad(20),0,0),bc)
		-- Eyes on sides (with iris detail)
		addPart(model,"EyeWL",Vector3.new(0.1*s,0.45*s,0.45*s),CFrame.new(b+Vector3.new(-1.12*s,2.9*s,-1.1*s)),white)
		addPart(model,"EyeWR",Vector3.new(0.1*s,0.45*s,0.45*s),CFrame.new(b+Vector3.new(1.12*s,2.9*s,-1.1*s)),white)
		addPart(model,"IrisL",Vector3.new(0.06*s,0.25*s,0.25*s),CFrame.new(b+Vector3.new(-1.16*s,2.9*s,-1.2*s)),Color3.fromRGB(20,20,20))
		addPart(model,"IrisR",Vector3.new(0.06*s,0.25*s,0.25*s),CFrame.new(b+Vector3.new(1.16*s,2.9*s,-1.2*s)),Color3.fromRGB(20,20,20))
		addPart(model,"EyePL",Vector3.new(0.04*s,0.12*s,0.12*s),CFrame.new(b+Vector3.new(-1.18*s,2.9*s,-1.25*s)),black)
		addPart(model,"EyePR",Vector3.new(0.04*s,0.12*s,0.12*s),CFrame.new(b+Vector3.new(1.18*s,2.9*s,-1.25*s)),black)
		-- Gill slits
		for gi=0,2 do
			addPart(model,"GillL"..gi,Vector3.new(0.04*s,0.3*s,0.06*s),CFrame.new(b+Vector3.new(-1.1*s,2.3*s+gi*0.15*s,-0.6*s)),darkGrey)
			addPart(model,"GillR"..gi,Vector3.new(0.04*s,0.3*s,0.06*s),CFrame.new(b+Vector3.new(1.1*s,2.3*s+gi*0.15*s,-0.6*s)),darkGrey)
		end
		if eType == "BossBrute" then
			-- SPAGHETTINO MACARONINO: spaghetti fork crown with noodles, chef hat
			addPart(model,"ForkHandle",Vector3.new(0.14*s,1.4*s,0.14*s),CFrame.new(b+Vector3.new(0,4.8*s,0)),grey,Enum.Material.Metal)
			addPart(model,"Prong1",Vector3.new(0.07*s,0.6*s,0.07*s),CFrame.new(b+Vector3.new(-0.18*s,5.7*s,0)),grey,Enum.Material.Metal)
			addPart(model,"Prong2",Vector3.new(0.07*s,0.6*s,0.07*s),CFrame.new(b+Vector3.new(0,5.7*s,0)),grey,Enum.Material.Metal)
			addPart(model,"Prong3",Vector3.new(0.07*s,0.6*s,0.07*s),CFrame.new(b+Vector3.new(0.18*s,5.7*s,0)),grey,Enum.Material.Metal)
			addPart(model,"Prong4",Vector3.new(0.07*s,0.6*s,0.07*s),CFrame.new(b+Vector3.new(-0.09*s,5.7*s,0.1*s)),grey,Enum.Material.Metal)
			-- Spaghetti noodles wrapped around fork
			addPart(model,"Noodle1",Vector3.new(0.7*s,0.08*s,0.08*s),CFrame.new(b+Vector3.new(0,5.5*s,0))*CFrame.Angles(0,math.rad(30),0),ac)
			addPart(model,"Noodle2",Vector3.new(0.7*s,0.08*s,0.08*s),CFrame.new(b+Vector3.new(0,5.35*s,0))*CFrame.Angles(0,math.rad(-40),0),ac)
			addPart(model,"Noodle3",Vector3.new(0.5*s,0.08*s,0.08*s),CFrame.new(b+Vector3.new(0,5.2*s,0))*CFrame.Angles(0,math.rad(60),0),ac)
			-- Meatball on fork
			addPart(model,"Meatball",Vector3.new(0.4*s,0.4*s,0.4*s),CFrame.new(b+Vector3.new(0,5.4*s,0.15*s)),Color3.fromRGB(140,60,30))
		end

	elseif eType == "Swarm" then
		-- LIRILI LARILA: fairy creature with detailed butterfly wings, antenna, face
		local bodyY = 0.7*s
		local pinkSkin = Color3.fromRGB(255,200,220)
		-- Torso (rounded)
		addPart(model,"Torso",Vector3.new(0.6*s,0.7*s,0.5*s),CFrame.new(b+Vector3.new(0,bodyY,0)),bc)
		addPart(model,"TorsoHighlight",Vector3.new(0.4*s,0.3*s,0.3*s),CFrame.new(b+Vector3.new(0,bodyY+0.1*s,-0.1*s)),Color3.fromRGB(255,80,220))
		-- Head
		addPart(model,"Head",Vector3.new(0.5*s,0.5*s,0.5*s),CFrame.new(b+Vector3.new(0,bodyY+0.6*s,0)),pinkSkin)
		addPart(model,"Cheeks",Vector3.new(0.55*s,0.25*s,0.3*s),CFrame.new(b+Vector3.new(0,bodyY+0.5*s,-0.1*s)),Color3.fromRGB(255,150,180))
		-- Eyes (big sparkly fairy eyes)
		addPart(model,"EyeWL",Vector3.new(0.18*s,0.22*s,0.08*s),CFrame.new(b+Vector3.new(-0.12*s,bodyY+0.65*s,-0.25*s)),white)
		addPart(model,"EyeWR",Vector3.new(0.18*s,0.22*s,0.08*s),CFrame.new(b+Vector3.new(0.12*s,bodyY+0.65*s,-0.25*s)),white)
		addPart(model,"IrisL",Vector3.new(0.12*s,0.15*s,0.04*s),CFrame.new(b+Vector3.new(-0.12*s,bodyY+0.65*s,-0.3*s)),Color3.fromRGB(100,0,200))
		addPart(model,"IrisR",Vector3.new(0.12*s,0.15*s,0.04*s),CFrame.new(b+Vector3.new(0.12*s,bodyY+0.65*s,-0.3*s)),Color3.fromRGB(100,0,200))
		addPart(model,"PupilL",Vector3.new(0.06*s,0.08*s,0.03*s),CFrame.new(b+Vector3.new(-0.12*s,bodyY+0.65*s,-0.33*s)),black)
		addPart(model,"PupilR",Vector3.new(0.06*s,0.08*s,0.03*s),CFrame.new(b+Vector3.new(0.12*s,bodyY+0.65*s,-0.33*s)),black)
		-- Sparkle in eyes
		addPart(model,"SparkL",Vector3.new(0.03*s,0.03*s,0.02*s),CFrame.new(b+Vector3.new(-0.1*s,bodyY+0.68*s,-0.34*s)),white,Enum.Material.Neon)
		addPart(model,"SparkR",Vector3.new(0.03*s,0.03*s,0.02*s),CFrame.new(b+Vector3.new(0.14*s,bodyY+0.68*s,-0.34*s)),white,Enum.Material.Neon)
		addPart(model,"Smile",Vector3.new(0.18*s,0.06*s,0.04*s),CFrame.new(b+Vector3.new(0,bodyY+0.45*s,-0.25*s)),Color3.fromRGB(200,50,80))
		-- Butterfly wings (4 wings, upper larger, with patterns)
		addPart(model,"WingTL",Vector3.new(1.0*s,0.8*s,0.06*s),CFrame.new(b+Vector3.new(-0.65*s,bodyY+0.5*s,0.15*s))*CFrame.Angles(0,0,math.rad(-12)),ac,Enum.Material.Neon)
		addPart(model,"WingTR",Vector3.new(1.0*s,0.8*s,0.06*s),CFrame.new(b+Vector3.new(0.65*s,bodyY+0.5*s,0.15*s))*CFrame.Angles(0,0,math.rad(12)),ac,Enum.Material.Neon)
		addPart(model,"WingBL",Vector3.new(0.7*s,0.5*s,0.06*s),CFrame.new(b+Vector3.new(-0.5*s,bodyY-0.1*s,0.15*s))*CFrame.Angles(0,0,math.rad(-8)),Color3.fromRGB(200,100,255),Enum.Material.Neon)
		addPart(model,"WingBR",Vector3.new(0.7*s,0.5*s,0.06*s),CFrame.new(b+Vector3.new(0.5*s,bodyY-0.1*s,0.15*s))*CFrame.Angles(0,0,math.rad(8)),Color3.fromRGB(200,100,255),Enum.Material.Neon)
		-- Wing eye spots (like real butterfly wings)
		addPart(model,"WingSpotL",Vector3.new(0.25*s,0.25*s,0.04*s),CFrame.new(b+Vector3.new(-0.7*s,bodyY+0.55*s,0.12*s)),Color3.fromRGB(0,200,255),Enum.Material.Neon)
		addPart(model,"WingSpotR",Vector3.new(0.25*s,0.25*s,0.04*s),CFrame.new(b+Vector3.new(0.7*s,bodyY+0.55*s,0.12*s)),Color3.fromRGB(0,200,255),Enum.Material.Neon)
		-- Antenna with glowing orb tips
		addPart(model,"AntennaL",Vector3.new(0.04*s,0.6*s,0.04*s),CFrame.new(b+Vector3.new(-0.12*s,bodyY+1.15*s,0))*CFrame.Angles(0,0,math.rad(-18)),black)
		addPart(model,"AntennaR",Vector3.new(0.04*s,0.6*s,0.04*s),CFrame.new(b+Vector3.new(0.12*s,bodyY+1.15*s,0))*CFrame.Angles(0,0,math.rad(18)),black)
		addPart(model,"GlowL",Vector3.new(0.15*s,0.15*s,0.15*s),CFrame.new(b+Vector3.new(-0.25*s,bodyY+1.45*s,0)),ac,Enum.Material.Neon)
		addPart(model,"GlowR",Vector3.new(0.15*s,0.15*s,0.15*s),CFrame.new(b+Vector3.new(0.25*s,bodyY+1.45*s,0)),ac,Enum.Material.Neon)
		-- Tiny arms
		addPart(model,"ArmL",Vector3.new(0.08*s,0.35*s,0.08*s),CFrame.new(b+Vector3.new(-0.35*s,bodyY+0.1*s,0))*CFrame.Angles(0,0,math.rad(-20)),pinkSkin)
		addPart(model,"ArmR",Vector3.new(0.08*s,0.35*s,0.08*s),CFrame.new(b+Vector3.new(0.35*s,bodyY+0.1*s,0))*CFrame.Angles(0,0,math.rad(20)),pinkSkin)
		-- Legs
		addPart(model,"LegL",Vector3.new(0.12*s,0.35*s,0.12*s),CFrame.new(b+Vector3.new(-0.14*s,0.18*s,0)),bc)
		addPart(model,"LegR",Vector3.new(0.12*s,0.35*s,0.12*s),CFrame.new(b+Vector3.new(0.14*s,0.18*s,0)),bc)
		addPart(model,"BootL",Vector3.new(0.15*s,0.1*s,0.2*s),CFrame.new(b+Vector3.new(-0.14*s,0.05*s,-0.04*s)),Color3.fromRGB(180,50,180))
		addPart(model,"BootR",Vector3.new(0.15*s,0.1*s,0.2*s),CFrame.new(b+Vector3.new(0.14*s,0.05*s,-0.04*s)),Color3.fromRGB(180,50,180))

	elseif eType == "Armored" then
		-- CAPPUCCINO ASSASSINO: detailed coffee cup with legs, foam, handle, knife, face
		local cupY = 0.9*s
		local brown = Color3.fromRGB(90,50,20)
		local darkBrown = Color3.fromRGB(60,30,10)
		local cream = Color3.fromRGB(255,240,220)
		-- Cup body (layered for ceramic look)
		addPart(model,"CupOuter",Vector3.new(1.4*s,1.8*s,1.4*s),CFrame.new(b+Vector3.new(0,cupY+0.9*s,0)),bc)
		addPart(model,"CupInner",Vector3.new(1.2*s,0.3*s,1.2*s),CFrame.new(b+Vector3.new(0,cupY+1.85*s,0)),darkBrown)
		addPart(model,"CupRim",Vector3.new(1.5*s,0.1*s,1.5*s),CFrame.new(b+Vector3.new(0,cupY+1.8*s,0)),Color3.fromRGB(110,65,30))
		addPart(model,"CupBase",Vector3.new(1.3*s,0.1*s,1.3*s),CFrame.new(b+Vector3.new(0,cupY+0.0*s,0)),Color3.fromRGB(110,65,30))
		-- Coffee liquid inside
		addPart(model,"Coffee",Vector3.new(1.1*s,0.08*s,1.1*s),CFrame.new(b+Vector3.new(0,cupY+1.75*s,0)),Color3.fromRGB(50,25,10))
		-- Foam top (layered, bubbly)
		addPart(model,"FoamBase",Vector3.new(1.45*s,0.35*s,1.45*s),CFrame.new(b+Vector3.new(0,cupY+2.0*s,0)),cream)
		addPart(model,"FoamBubble1",Vector3.new(0.4*s,0.25*s,0.4*s),CFrame.new(b+Vector3.new(0.2*s,cupY+2.25*s,0.15*s)),white)
		addPart(model,"FoamBubble2",Vector3.new(0.35*s,0.2*s,0.35*s),CFrame.new(b+Vector3.new(-0.2*s,cupY+2.2*s,-0.1*s)),white)
		addPart(model,"FoamSwirl",Vector3.new(0.5*s,0.25*s,0.5*s),CFrame.new(b+Vector3.new(0,cupY+2.3*s,0)),white)
		-- Latte art (heart shape approximated)
		addPart(model,"LatteArt",Vector3.new(0.3*s,0.04*s,0.3*s),CFrame.new(b+Vector3.new(0,cupY+2.42*s,0)),brown)
		-- Cup handle (right side, detailed C-shape)
		addPart(model,"HandleTop",Vector3.new(0.55*s,0.18*s,0.18*s),CFrame.new(b+Vector3.new(0.95*s,cupY+1.35*s,0)),bc)
		addPart(model,"HandleMid",Vector3.new(0.18*s,0.6*s,0.18*s),CFrame.new(b+Vector3.new(1.2*s,cupY+1.05*s,0)),bc)
		addPart(model,"HandleBot",Vector3.new(0.55*s,0.18*s,0.18*s),CFrame.new(b+Vector3.new(0.95*s,cupY+0.75*s,0)),bc)
		-- Angry face on cup
		addPart(model,"EyeWL",Vector3.new(0.3*s,0.25*s,0.12*s),CFrame.new(b+Vector3.new(-0.3*s,cupY+1.35*s,-0.7*s)),white)
		addPart(model,"EyeWR",Vector3.new(0.3*s,0.25*s,0.12*s),CFrame.new(b+Vector3.new(0.3*s,cupY+1.35*s,-0.7*s)),white)
		addPart(model,"IrisL",Vector3.new(0.15*s,0.15*s,0.06*s),CFrame.new(b+Vector3.new(-0.3*s,cupY+1.33*s,-0.77*s)),Color3.fromRGB(180,0,0))
		addPart(model,"IrisR",Vector3.new(0.15*s,0.15*s,0.06*s),CFrame.new(b+Vector3.new(0.3*s,cupY+1.33*s,-0.77*s)),Color3.fromRGB(180,0,0))
		addPart(model,"PupilL",Vector3.new(0.08*s,0.1*s,0.04*s),CFrame.new(b+Vector3.new(-0.3*s,cupY+1.33*s,-0.81*s)),black)
		addPart(model,"PupilR",Vector3.new(0.08*s,0.1*s,0.04*s),CFrame.new(b+Vector3.new(0.3*s,cupY+1.33*s,-0.81*s)),black)
		-- Angry eyebrows (angled)
		addPart(model,"BrowL",Vector3.new(0.35*s,0.07*s,0.1*s),CFrame.new(b+Vector3.new(-0.3*s,cupY+1.55*s,-0.68*s))*CFrame.Angles(0,0,math.rad(18)),darkBrown)
		addPart(model,"BrowR",Vector3.new(0.35*s,0.07*s,0.1*s),CFrame.new(b+Vector3.new(0.3*s,cupY+1.55*s,-0.68*s))*CFrame.Angles(0,0,math.rad(-18)),darkBrown)
		-- Angry mouth (snarl)
		addPart(model,"MouthBG",Vector3.new(0.5*s,0.2*s,0.08*s),CFrame.new(b+Vector3.new(0,cupY+0.9*s,-0.7*s)),Color3.fromRGB(40,0,0))
		addPart(model,"ToothL",Vector3.new(0.1*s,0.1*s,0.06*s),CFrame.new(b+Vector3.new(-0.12*s,cupY+1.0*s,-0.75*s)),white)
		addPart(model,"ToothR",Vector3.new(0.1*s,0.1*s,0.06*s),CFrame.new(b+Vector3.new(0.12*s,cupY+1.0*s,-0.75*s)),white)
		-- Knife arm (left side, detailed with guard)
		addPart(model,"KnifeArm",Vector3.new(0.15*s,0.5*s,0.15*s),CFrame.new(b+Vector3.new(-0.9*s,cupY+0.7*s,-0.3*s)),brown)
		addPart(model,"KnifeHandle",Vector3.new(0.14*s,0.45*s,0.14*s),CFrame.new(b+Vector3.new(-0.9*s,cupY+0.2*s,-0.3*s)),Color3.fromRGB(80,50,20))
		addPart(model,"KnifeGuard",Vector3.new(0.25*s,0.06*s,0.12*s),CFrame.new(b+Vector3.new(-0.9*s,cupY-0.0*s,-0.3*s)),grey,Enum.Material.Metal)
		addPart(model,"KnifeBlade",Vector3.new(0.06*s,0.9*s,0.22*s),CFrame.new(b+Vector3.new(-0.9*s,cupY-0.5*s,-0.3*s)),Color3.fromRGB(200,200,210),Enum.Material.Metal)
		addPart(model,"KnifeTip",Vector3.new(0.06*s,0.2*s,0.12*s),CFrame.new(b+Vector3.new(-0.9*s,cupY-1.0*s,-0.3*s)),Color3.fromRGB(200,200,210),Enum.Material.Metal)
		-- Stubby legs with shoes
		addPart(model,"LegL",Vector3.new(0.4*s,0.7*s,0.4*s),CFrame.new(b+Vector3.new(-0.35*s,0.35*s,0)),brown)
		addPart(model,"LegR",Vector3.new(0.4*s,0.7*s,0.4*s),CFrame.new(b+Vector3.new(0.35*s,0.35*s,0)),brown)
		addPart(model,"FootL",Vector3.new(0.45*s,0.18*s,0.55*s),CFrame.new(b+Vector3.new(-0.35*s,0.09*s,-0.05*s)),darkBrown)
		addPart(model,"FootR",Vector3.new(0.45*s,0.18*s,0.55*s),CFrame.new(b+Vector3.new(0.35*s,0.09*s,-0.05*s)),darkBrown)
		-- Saucer plate under cup
		addPart(model,"Saucer",Vector3.new(1.8*s,0.1*s,1.8*s),CFrame.new(b+Vector3.new(0,cupY-0.05*s,0)),cream)

	elseif eType == "BossVoid" then
		-- GLORBO FRUTTODRILLO: massive fruit-crocodile hybrid, neon spots, jeweled crown
		local fruitGreen = Color3.fromRGB(0,200,120)
		local fruitYellow = Color3.fromRGB(255,220,100)
		-- Massive croc body (layered)
		addPart(model,"BodyCore",Vector3.new(2.8*s,1.4*s,4.5*s),CFrame.new(b+Vector3.new(0,1.3*s,0)),bc)
		addPart(model,"BodyTop",Vector3.new(2.4*s,0.25*s,4.0*s),CFrame.new(b+Vector3.new(0,2.1*s,0)),fruitGreen)
		addPart(model,"Belly",Vector3.new(2.2*s,0.35*s,3.8*s),CFrame.new(b+Vector3.new(0,0.55*s,0)),fruitYellow)
		addPart(model,"BellyStripes",Vector3.new(1.8*s,0.1*s,3.4*s),CFrame.new(b+Vector3.new(0,0.48*s,0)),Color3.fromRGB(255,200,80))
		-- Fruit-croc snout (wider, more menacing)
		addPart(model,"SnoutUpper",Vector3.new(1.4*s,0.9*s,2.2*s),CFrame.new(b+Vector3.new(0,1.5*s,-3.0*s)),bc)
		addPart(model,"SnoutBridge",Vector3.new(1.0*s,0.2*s,2.0*s),CFrame.new(b+Vector3.new(0,2.0*s,-2.8*s)),fruitGreen)
		addPart(model,"JawLower",Vector3.new(1.2*s,0.5*s,2.0*s),CFrame.new(b+Vector3.new(0,0.75*s,-2.8*s)),bc)
		addPart(model,"MouthInside",Vector3.new(1.0*s,0.2*s,1.6*s),CFrame.new(b+Vector3.new(0,1.05*s,-2.7*s)),Color3.fromRGB(180,40,60))
		-- Big teeth (upper + lower)
		for ti=0,6 do
			local tx = -0.5*s + ti*0.17*s
			addPart(model,"ToothU"..ti,Vector3.new(0.1*s,0.3*s,0.1*s),CFrame.new(b+Vector3.new(tx,1.1*s,-3.8*s)),white)
			addPart(model,"ToothD"..ti,Vector3.new(0.08*s,0.22*s,0.08*s),CFrame.new(b+Vector3.new(tx,0.9*s,-3.7*s)),Color3.fromRGB(240,240,220))
		end
		-- Neon fruit spots (scattered, various colors)
		addPart(model,"Spot1",Vector3.new(0.7*s,0.12*s,0.7*s),CFrame.new(b+Vector3.new(0.6*s,2.15*s,0.5*s)),Color3.fromRGB(255,50,200),Enum.Material.Neon)
		addPart(model,"Spot2",Vector3.new(0.6*s,0.12*s,0.6*s),CFrame.new(b+Vector3.new(-0.7*s,2.15*s,-0.3*s)),Color3.fromRGB(0,255,200),Enum.Material.Neon)
		addPart(model,"Spot3",Vector3.new(0.8*s,0.12*s,0.8*s),CFrame.new(b+Vector3.new(0,2.15*s,1.2*s)),Color3.fromRGB(255,255,0),Enum.Material.Neon)
		addPart(model,"Spot4",Vector3.new(0.5*s,0.12*s,0.5*s),CFrame.new(b+Vector3.new(-0.4*s,2.15*s,1.8*s)),Color3.fromRGB(255,100,0),Enum.Material.Neon)
		addPart(model,"Spot5",Vector3.new(0.55*s,0.12*s,0.55*s),CFrame.new(b+Vector3.new(0.8*s,2.15*s,-0.8*s)),Color3.fromRGB(100,255,50),Enum.Material.Neon)
		addPart(model,"Spot6",Vector3.new(0.4*s,0.12*s,0.4*s),CFrame.new(b+Vector3.new(-0.9*s,2.15*s,0.8*s)),Color3.fromRGB(255,0,255),Enum.Material.Neon)
		-- Bulging eyes (with red irises for menace)
		addPart(model,"EyeBulgeL",Vector3.new(0.7*s,0.7*s,0.7*s),CFrame.new(b+Vector3.new(-0.7*s,2.3*s,-1.4*s)),bc)
		addPart(model,"EyeBulgeR",Vector3.new(0.7*s,0.7*s,0.7*s),CFrame.new(b+Vector3.new(0.7*s,2.3*s,-1.4*s)),bc)
		addPart(model,"EyeWL",Vector3.new(0.4*s,0.4*s,0.18*s),CFrame.new(b+Vector3.new(-0.7*s,2.4*s,-1.8*s)),white)
		addPart(model,"EyeWR",Vector3.new(0.4*s,0.4*s,0.18*s),CFrame.new(b+Vector3.new(0.7*s,2.4*s,-1.8*s)),white)
		addPart(model,"IrisL",Vector3.new(0.25*s,0.25*s,0.08*s),CFrame.new(b+Vector3.new(-0.7*s,2.4*s,-1.9*s)),Color3.fromRGB(255,0,0))
		addPart(model,"IrisR",Vector3.new(0.25*s,0.25*s,0.08*s),CFrame.new(b+Vector3.new(0.7*s,2.4*s,-1.9*s)),Color3.fromRGB(255,0,0))
		addPart(model,"PupilL",Vector3.new(0.12*s,0.2*s,0.05*s),CFrame.new(b+Vector3.new(-0.7*s,2.4*s,-1.95*s)),black)
		addPart(model,"PupilR",Vector3.new(0.12*s,0.2*s,0.05*s),CFrame.new(b+Vector3.new(0.7*s,2.4*s,-1.95*s)),black)
		addPart(model,"EyelidL",Vector3.new(0.45*s,0.15*s,0.2*s),CFrame.new(b+Vector3.new(-0.7*s,2.65*s,-1.75*s)),fruitGreen)
		addPart(model,"EyelidR",Vector3.new(0.45*s,0.15*s,0.2*s),CFrame.new(b+Vector3.new(0.7*s,2.65*s,-1.75*s)),fruitGreen)
		-- 4 stubby muscular legs with claws
		addPart(model,"ThighFL",Vector3.new(0.7*s,0.7*s,0.7*s),CFrame.new(b+Vector3.new(-1.0*s,0.7*s,-1.4*s)),bc)
		addPart(model,"LegFL",Vector3.new(0.55*s,0.5*s,0.55*s),CFrame.new(b+Vector3.new(-1.0*s,0.25*s,-1.4*s)),bc)
		addPart(model,"ThighFR",Vector3.new(0.7*s,0.7*s,0.7*s),CFrame.new(b+Vector3.new(1.0*s,0.7*s,-1.4*s)),bc)
		addPart(model,"LegFR",Vector3.new(0.55*s,0.5*s,0.55*s),CFrame.new(b+Vector3.new(1.0*s,0.25*s,-1.4*s)),bc)
		addPart(model,"ThighBL",Vector3.new(0.7*s,0.7*s,0.7*s),CFrame.new(b+Vector3.new(-1.0*s,0.7*s,1.4*s)),bc)
		addPart(model,"LegBL",Vector3.new(0.55*s,0.5*s,0.55*s),CFrame.new(b+Vector3.new(-1.0*s,0.25*s,1.4*s)),bc)
		addPart(model,"ThighBR",Vector3.new(0.7*s,0.7*s,0.7*s),CFrame.new(b+Vector3.new(1.0*s,0.7*s,1.4*s)),bc)
		addPart(model,"LegBR",Vector3.new(0.55*s,0.5*s,0.55*s),CFrame.new(b+Vector3.new(1.0*s,0.25*s,1.4*s)),bc)
		-- Claws
		for ci=0,2 do
			local cx = -0.15*s + ci*0.15*s
			addPart(model,"ClawFL"..ci,Vector3.new(0.06*s,0.06*s,0.2*s),CFrame.new(b+Vector3.new(-1.0*s+cx,0.06*s,-1.9*s)),Color3.fromRGB(200,200,180))
			addPart(model,"ClawFR"..ci,Vector3.new(0.06*s,0.06*s,0.2*s),CFrame.new(b+Vector3.new(1.0*s+cx,0.06*s,-1.9*s)),Color3.fromRGB(200,200,180))
		end
		-- Tail (3 segments)
		addPart(model,"Tail1",Vector3.new(0.8*s,0.6*s,1.7*s),CFrame.new(b+Vector3.new(0,1.1*s,2.8*s)),bc)
		addPart(model,"Tail2",Vector3.new(0.5*s,0.4*s,1.2*s),CFrame.new(b+Vector3.new(0,1.0*s,3.9*s)),bc)
		addPart(model,"Tail3",Vector3.new(0.3*s,0.25*s,0.8*s),CFrame.new(b+Vector3.new(0,0.95*s,4.7*s)),fruitGreen)
		-- Scaly ridges
		for ri=0,5 do addPart(model,"Ridge"..ri,Vector3.new(0.2*s,0.4*s,0.3*s),CFrame.new(b+Vector3.new(0,2.3*s,-1.5*s+ri*0.8*s)),fruitGreen) end
		-- Jeweled crown (ornate)
		addPart(model,"CrownBase",Vector3.new(1.4*s,0.25*s,1.4*s),CFrame.new(b+Vector3.new(0,2.8*s,-0.5*s)),ac,Enum.Material.Neon)
		addPart(model,"CrownBand",Vector3.new(1.5*s,0.15*s,1.5*s),CFrame.new(b+Vector3.new(0,2.7*s,-0.5*s)),Color3.fromRGB(200,0,80),Enum.Material.Neon)
		addPart(model,"CrownSpike1",Vector3.new(0.18*s,0.6*s,0.18*s),CFrame.new(b+Vector3.new(-0.4*s,3.2*s,-0.5*s)),ac,Enum.Material.Neon)
		addPart(model,"CrownSpike2",Vector3.new(0.18*s,0.75*s,0.18*s),CFrame.new(b+Vector3.new(0,3.3*s,-0.5*s)),ac,Enum.Material.Neon)
		addPart(model,"CrownSpike3",Vector3.new(0.18*s,0.6*s,0.18*s),CFrame.new(b+Vector3.new(0.4*s,3.2*s,-0.5*s)),ac,Enum.Material.Neon)
		-- Jewels on crown spikes
		addPart(model,"Jewel1",Vector3.new(0.15*s,0.15*s,0.15*s),CFrame.new(b+Vector3.new(-0.4*s,3.55*s,-0.5*s)),Color3.fromRGB(255,0,100),Enum.Material.Neon)
		addPart(model,"Jewel2",Vector3.new(0.2*s,0.2*s,0.2*s),CFrame.new(b+Vector3.new(0,3.72*s,-0.5*s)),Color3.fromRGB(0,255,255),Enum.Material.Neon)
		addPart(model,"Jewel3",Vector3.new(0.15*s,0.15*s,0.15*s),CFrame.new(b+Vector3.new(0.4*s,3.55*s,-0.5*s)),Color3.fromRGB(255,255,0),Enum.Material.Neon)
		-- Jewels on crown band
		addPart(model,"BandJewel1",Vector3.new(0.12*s,0.12*s,0.08*s),CFrame.new(b+Vector3.new(-0.3*s,2.75*s,-1.2*s)),Color3.fromRGB(0,200,255),Enum.Material.Neon)
		addPart(model,"BandJewel2",Vector3.new(0.12*s,0.12*s,0.08*s),CFrame.new(b+Vector3.new(0.3*s,2.75*s,-1.2*s)),Color3.fromRGB(255,100,0),Enum.Material.Neon)

	else
		-- Fallback: simple colored box with face
		addPart(model,"Body",Vector3.new(1.2*s,1.2*s,1.2*s),CFrame.new(b+Vector3.new(0,0.6*s,0)),bc)
		addPart(model,"Head",Vector3.new(0.8*s,0.8*s,0.8*s),CFrame.new(b+Vector3.new(0,1.6*s,0)),ac)
		addPart(model,"EyeL",Vector3.new(0.15*s,0.15*s,0.06*s),CFrame.new(b+Vector3.new(-0.2*s,1.7*s,-0.4*s)),white)
		addPart(model,"EyeR",Vector3.new(0.15*s,0.15*s,0.06*s),CFrame.new(b+Vector3.new(0.2*s,1.7*s,-0.4*s)),white)
	end

	-- Health bar billboard
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.new(0, 80, 0, 10)
	billboard.StudsOffset = Vector3.new(0, 3.5 * s, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = root
	billboard.Parent = root

	local bgBar = Instance.new("Frame")
	bgBar.Name = "BG"
	bgBar.Size = UDim2.new(1, 0, 1, 0)
	bgBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	bgBar.BorderSizePixel = 0
	bgBar.Parent = billboard

	local fillBar = Instance.new("Frame")
	fillBar.Name = "Fill"
	fillBar.Size = UDim2.new(1, 0, 1, 0)
	fillBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
	fillBar.BorderSizePixel = 0
	fillBar.Parent = bgBar

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = enemyData.health
	humanoid.Health = enemyData.health
	humanoid.Parent = model

	model.PrimaryPart = root
	model.Parent = workspace
	return model
end


function EnemyManager.spawnEnemy(enemyType: string, round: number)
	local enemyData = WaveData.scaleEnemy(enemyType, round)
	local waypoints = getWaypoints()
	if #waypoints == 0 then
		warn("[EnemyManager] No waypoints found!")
		return
	end

	local startPos = waypoints[1]
	local id = newEnemyId()
	local model = spawnEnemyModel(enemyData, startPos)

	activeEnemies[id] = {
		id            = id,
		model         = model,
		data          = enemyData,
		health        = enemyData.health,
		maxHealth     = enemyData.health,
		speed         = enemyData.speed,
		baseSpeed     = enemyData.speed,
		reward        = enemyData.reward,
		isBoss        = enemyData.isBoss,
		waypointIndex = 1,
		position      = startPos,
		facing        = CFrame.new(),
		animTime      = 0,
		slowTimer     = 0,
		slowFactor    = 1,
	}

	print("[EnemyManager] Spawned", enemyData.name, "(", id, ") at waypoint 1")
end

function EnemyManager.update(dt: number)
	local waypoints = getWaypoints()
	if #waypoints == 0 then return end

	for id, enemy in pairs(activeEnemies) do
		if not enemy.model or not enemy.model.Parent then
			activeEnemies[id] = nil
			continue
		end

		-- Update slow timer
		if enemy.slowTimer > 0 then
			enemy.slowTimer -= dt
			if enemy.slowTimer <= 0 then
				enemy.slowFactor = 1
				enemy.speed = enemy.baseSpeed
			end
		end

		-- Move toward current waypoint
		local targetWP = waypoints[enemy.waypointIndex]
		if not targetWP then
			-- Reached end
			if onEnemyReachedEnd then onEnemyReachedEnd(enemy.data) end
			if enemy.model then enemy.model:Destroy() end
			activeEnemies[id] = nil
			continue
		end

		local currentPos = enemy.position
		local dir = targetWP - currentPos
		local flatDir = Vector3.new(dir.X, 0, dir.Z)
		local dist = flatDir.Magnitude

		if dist < WAYPOINT_REACH_DIST then
			enemy.waypointIndex += 1
			if enemy.waypointIndex > #waypoints then
				if onEnemyReachedEnd then onEnemyReachedEnd(enemy.data) end
				if enemy.model then enemy.model:Destroy() end
				activeEnemies[id] = nil
				continue
			end
			continue
		end

		-- Movement
		local moveDir = flatDir.Unit
		local moveAmount = enemy.speed * enemy.slowFactor * dt
		local newPos = currentPos + moveDir * moveAmount
		enemy.position = newPos

		-- Face movement direction (smooth)
		local targetFacing = CFrame.lookAt(Vector3.zero, moveDir)
		enemy.facing = enemy.facing:Lerp(targetFacing, math.min(1, 10 * dt))

		-- Walking animation timer
		enemy.animTime = (enemy.animTime or 0) + dt * enemy.speed * 0.5

		-- Move entire model using PivotTo
		local rootCF = CFrame.new(newPos) * enemy.facing
		enemy.model:PivotTo(rootCF)

		-- Animate limbs (arms/legs swing)
		local swing = math.sin(enemy.animTime * 4) * 0.4
		for _, part in ipairs(enemy.model:GetChildren()) do
			local n = part.Name
			if part:IsA("BasePart") then
				-- Animate legs (front-left and back-right swing together, opposite pair swings other way)
				if n == "LegFL" or n == "LegL" or n == "ThighL" or n == "ThighFL" or n == "ShinL" then
					part.CFrame = part.CFrame * CFrame.new(0, 0, swing * 0.3)
				elseif n == "LegFR" or n == "LegR" or n == "ThighR" or n == "ThighFR" or n == "ShinR" then
					part.CFrame = part.CFrame * CFrame.new(0, 0, -swing * 0.3)
				elseif n == "LegBL" or n == "ThighBL" then
					part.CFrame = part.CFrame * CFrame.new(0, 0, -swing * 0.3)
				elseif n == "LegBR" or n == "ThighBR" then
					part.CFrame = part.CFrame * CFrame.new(0, 0, swing * 0.3)
				end
				-- Animate arms/fins/wings
				if n == "ArmL" or n == "ArmShaftL" or n == "FinArmL" or n == "WingL" or n == "WingTL" or n == "KnifeArm" or n == "KnifeBlade" then
					part.CFrame = part.CFrame * CFrame.Angles(swing * 0.3, 0, 0)
				elseif n == "ArmR" or n == "ArmShaftR" or n == "FinArmR" or n == "WingR" or n == "WingTR" then
					part.CFrame = part.CFrame * CFrame.Angles(-swing * 0.3, 0, 0)
				end
			end
		end

		-- Update health bar
		local hRoot = enemy.model:FindFirstChild("HumanoidRootPart")
		if hRoot then
			local bb = hRoot:FindFirstChild("HealthBar")
			if bb then
				local bg = bb:FindFirstChild("BG")
				if bg then
					local fill = bg:FindFirstChild("Fill")
					if fill then
						local pct = math.clamp(enemy.health / enemy.maxHealth, 0, 1)
						fill.Size = UDim2.new(pct, 0, 1, 0)
						if pct > 0.5 then
							fill.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
						elseif pct > 0.25 then
							fill.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
						else
							fill.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
						end
					end
				end
			end
		end
	end
end

function EnemyManager.damageEnemy(enemyId: string, damage: number): boolean
	local enemy = activeEnemies[enemyId]
	if not enemy then return false end

	enemy.health -= damage
	if enemy.health <= 0 then
		if onEnemyKilled then onEnemyKilled(enemy.data) end
		if enemy.model then enemy.model:Destroy() end
		activeEnemies[enemyId] = nil
		return true -- killed
	end
	return false -- still alive
end

function EnemyManager.getActiveEnemies(): { [string]: any }
	return activeEnemies
end

function EnemyManager.clearAll()
	for id, enemy in pairs(activeEnemies) do
		if enemy.model then enemy.model:Destroy() end
	end
	activeEnemies = {}
	enemyIdCounter = 0
	print("[EnemyManager] All enemies cleared.")
end

function EnemyManager.applySlow(enemyId: string, factor: number, duration: number)
	local enemy = activeEnemies[enemyId]
	if not enemy then return end
	enemy.slowFactor = math.min(enemy.slowFactor, factor)
	enemy.slowTimer = math.max(enemy.slowTimer, duration)
	enemy.speed = enemy.baseSpeed * enemy.slowFactor
end

return EnemyManager
