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

	-- Attach looping walking sound at low volume
	local walkSound = Instance.new("Sound")
	walkSound.Name = "WalkSound"
	walkSound.SoundId = "rbxassetid://140596208736991"
	walkSound.Volume = 0.15
	walkSound.Looped = true
	walkSound.RollOffMaxDistance = 40
	walkSound.Parent = root
	walkSound:Play()

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

-- Apply visual rune effect on enemy when hit
-- runeIds: array of rune type IDs applied to the turret that hit this enemy
function EnemyManager.applyRuneEffect(enemyId: string, runeIds: { number })
	local enemy = activeEnemies[enemyId]
	if not enemy or not enemy.model then return end
	
	local ResourceData = require(game.ReplicatedStorage.Shared.ResourceData)
	local root = enemy.model.PrimaryPart
	if not root then return end
	
	for _, runeId in ipairs(runeIds) do
		local runeData = ResourceData.Resources[runeId]
		if not runeData then continue end
		
		local color = runeData.color
		local runeName = runeData.name
		
		task.spawn(function()
			-- Create effect based on rune type
			if runeName == "Ember" then
				-- Fire effect: orange/red flames rising from enemy
				for i = 1, 6 do
					local flame = Instance.new("Part")
					flame.Size = Vector3.new(0.4, 0.6, 0.4)
					flame.Shape = Enum.PartType.Ball
					flame.Material = Enum.Material.Neon
					flame.Color = Color3.fromRGB(255, math.random(50, 150), 0)
					flame.Anchored = true
					flame.CanCollide = false
					flame.Position = root.Position + Vector3.new(
						(math.random() - 0.5) * 2,
						math.random() * 1.5,
						(math.random() - 0.5) * 2
					)
					flame.Parent = workspace
					
					task.spawn(function()
						for k = 1, 12 do
							task.wait(0.04)
							local t = k / 12
							flame.Position = flame.Position + Vector3.new(0, 0.15, 0)
							flame.Size = flame.Size * 0.9
							flame.Transparency = t
						end
						flame:Destroy()
					end)
					task.wait(0.05)
				end
				
			elseif runeName == "Frost" then
				-- Ice effect: blue crystals and frost particles
				for i = 1, 5 do
					local ice = Instance.new("Part")
					ice.Size = Vector3.new(0.3, 0.5, 0.3)
					ice.Material = Enum.Material.Glass
					ice.Color = Color3.fromRGB(150, 220, 255)
					ice.Anchored = true
					ice.CanCollide = false
					ice.Transparency = 0.3
					local angle = (i / 5) * math.pi * 2
					ice.Position = root.Position + Vector3.new(
						math.cos(angle) * 1.2,
						math.random() * 1.5,
						math.sin(angle) * 1.2
					)
					ice.Parent = workspace
					
					task.spawn(function()
						for k = 1, 15 do
							task.wait(0.05)
							ice.Transparency = 0.3 + (k / 15) * 0.7
						end
						ice:Destroy()
					end)
				end
				
			elseif runeName == "Spark" then
				-- Lightning effect: yellow electric bolts
				for i = 1, 4 do
					local bolt = Instance.new("Part")
					bolt.Size = Vector3.new(0.1, 0.1, 2)
					bolt.Material = Enum.Material.Neon
					bolt.Color = Color3.fromRGB(255, 255, 50)
					bolt.Anchored = true
					bolt.CanCollide = false
					local startPos = root.Position + Vector3.new(
						(math.random() - 0.5) * 2,
						2,
						(math.random() - 0.5) * 2
					)
					local endPos = root.Position + Vector3.new(
						(math.random() - 0.5) * 2,
						-0.5,
						(math.random() - 0.5) * 2
					)
					bolt.CFrame = CFrame.lookAt(startPos, endPos)
					bolt.Parent = workspace
					
					task.spawn(function()
						for k = 1, 6 do
							task.wait(0.03)
							bolt.Transparency = k / 6
							bolt.Color = Color3.fromRGB(255, 255, math.random(100, 255))
						end
						bolt:Destroy()
					end)
					task.wait(0.02)
				end
				
			elseif runeName == "Spore" then
				-- Nature effect: green spores floating up
				for i = 1, 8 do
					local spore = Instance.new("Part")
					spore.Size = Vector3.new(0.25, 0.25, 0.25)
					spore.Shape = Enum.PartType.Ball
					spore.Material = Enum.Material.Neon
					spore.Color = Color3.fromRGB(50, 255, 50)
					spore.Anchored = true
					spore.CanCollide = false
					spore.Position = root.Position + Vector3.new(
						(math.random() - 0.5) * 2,
						math.random() * 2,
						(math.random() - 0.5) * 2
					)
					spore.Parent = workspace
					
					task.spawn(function()
						local drift = Vector3.new((math.random() - 0.5) * 0.1, 0.1, (math.random() - 0.5) * 0.1)
						for k = 1, 15 do
							task.wait(0.04)
							spore.Position = spore.Position + drift
							spore.Transparency = k / 15
						end
						spore:Destroy()
					end)
					task.wait(0.03)
				end
				
			elseif runeName == "Shadow" then
				-- Dark effect: purple/black wisps
				for i = 1, 5 do
					local wisp = Instance.new("Part")
					wisp.Size = Vector3.new(0.5, 0.5, 0.5)
					wisp.Shape = Enum.PartType.Ball
					wisp.Material = Enum.Material.Neon
					wisp.Color = Color3.fromRGB(80, 0, 120)
					wisp.Anchored = true
					wisp.CanCollide = false
					wisp.Position = root.Position + Vector3.new(
						(math.random() - 0.5) * 1.5,
						math.random() * 1.5,
						(math.random() - 0.5) * 1.5
					)
					wisp.Parent = workspace
					
					task.spawn(function()
						for k = 1, 12 do
							task.wait(0.04)
							wisp.Position = wisp.Position + Vector3.new(
								(math.random() - 0.5) * 0.2,
								-0.05,
								(math.random() - 0.5) * 0.2
							)
							wisp.Size = wisp.Size * 1.05
							wisp.Transparency = k / 12
						end
						wisp:Destroy()
					end)
					task.wait(0.04)
				end
				
			elseif runeName == "Radiance" then
				-- Light effect: golden rays and sparkles
				for i = 1, 6 do
					local ray = Instance.new("Part")
					ray.Size = Vector3.new(0.15, 2, 0.15)
					ray.Material = Enum.Material.Neon
					ray.Color = Color3.fromRGB(255, 255, 150)
					ray.Anchored = true
					ray.CanCollide = false
					local angle = (i / 6) * math.pi * 2
					ray.CFrame = CFrame.new(root.Position + Vector3.new(math.cos(angle) * 0.8, 1, math.sin(angle) * 0.8))
						* CFrame.Angles(0, 0, math.rad(math.random(-15, 15)))
					ray.Parent = workspace
					
					task.spawn(function()
						for k = 1, 10 do
							task.wait(0.04)
							ray.Transparency = k / 10
							ray.Size = ray.Size + Vector3.new(0, 0.1, 0)
						end
						ray:Destroy()
					end)
				end
				
			elseif runeName == "Stone" then
				-- Earth effect: brown rocks flying out
				for i = 1, 5 do
					local rock = Instance.new("Part")
					rock.Size = Vector3.new(0.4, 0.4, 0.4)
					rock.Material = Enum.Material.Slate
					rock.Color = Color3.fromRGB(120, 90, 60)
					rock.Anchored = true
					rock.CanCollide = false
					rock.Position = root.Position + Vector3.new(0, 0.5, 0)
					rock.Parent = workspace
					
					local dir = Vector3.new(
						(math.random() - 0.5) * 2,
						math.random() * 0.5 + 0.3,
						(math.random() - 0.5) * 2
					).Unit
					
					task.spawn(function()
						for k = 1, 10 do
							task.wait(0.04)
							rock.Position = rock.Position + dir * 0.3
							rock.CFrame = rock.CFrame * CFrame.Angles(0.2, 0.1, 0.15)
							rock.Transparency = k / 10
						end
						rock:Destroy()
					end)
					task.wait(0.02)
				end
				
			elseif runeName == "Gale" then
				-- Wind effect: swirling white/blue particles
				for i = 1, 8 do
					local wind = Instance.new("Part")
					wind.Size = Vector3.new(0.2, 0.2, 0.6)
					wind.Material = Enum.Material.Neon
					wind.Color = Color3.fromRGB(200, 240, 255)
					wind.Anchored = true
					wind.CanCollide = false
					wind.Transparency = 0.3
					local angle = (i / 8) * math.pi * 2
					wind.Position = root.Position + Vector3.new(math.cos(angle) * 1.5, 1, math.sin(angle) * 1.5)
					wind.Parent = workspace
					
					task.spawn(function()
						for k = 1, 12 do
							task.wait(0.03)
							local newAngle = angle + k * 0.5
							wind.Position = root.Position + Vector3.new(
								math.cos(newAngle) * (1.5 - k * 0.1),
								1 + k * 0.1,
								math.sin(newAngle) * (1.5 - k * 0.1)
							)
							wind.Transparency = 0.3 + (k / 12) * 0.7
						end
						wind:Destroy()
					end)
				end
				
			elseif runeName == "Arcane" then
				-- Magic effect: purple runes and symbols
				for i = 1, 4 do
					local rune = Instance.new("Part")
					rune.Size = Vector3.new(1, 0.1, 1)
					rune.Material = Enum.Material.Neon
					rune.Color = Color3.fromRGB(180, 80, 255)
					rune.Anchored = true
					rune.CanCollide = false
					rune.Transparency = 0.2
					local height = i * 0.6
					rune.CFrame = CFrame.new(root.Position + Vector3.new(0, height, 0))
					rune.Parent = workspace
					
					task.spawn(function()
						for k = 1, 15 do
							task.wait(0.04)
							rune.CFrame = rune.CFrame * CFrame.Angles(0, 0.3, 0)
							rune.Size = rune.Size * 0.95
							rune.Transparency = 0.2 + (k / 15) * 0.8
						end
						rune:Destroy()
					end)
					task.wait(0.1)
				end
				
			elseif runeName == "Void" then
				-- Void effect: black hole with particles being sucked in
				local voidCore = Instance.new("Part")
				voidCore.Size = Vector3.new(1.5, 1.5, 1.5)
				voidCore.Shape = Enum.PartType.Ball
				voidCore.Material = Enum.Material.Neon
				voidCore.Color = Color3.fromRGB(10, 0, 20)
				voidCore.Anchored = true
				voidCore.CanCollide = false
				voidCore.Position = root.Position + Vector3.new(0, 1, 0)
				voidCore.Parent = workspace
				
				-- Spawn particles that get sucked into the void
				for i = 1, 10 do
					task.spawn(function()
						local particle = Instance.new("Part")
						particle.Size = Vector3.new(0.3, 0.3, 0.3)
						particle.Shape = Enum.PartType.Ball
						particle.Material = Enum.Material.Neon
						particle.Color = Color3.fromRGB(math.random(50, 150), 0, math.random(100, 200))
						particle.Anchored = true
						particle.CanCollide = false
						local angle = math.random() * math.pi * 2
						local dist = 2 + math.random() * 1.5
						particle.Position = voidCore.Position + Vector3.new(
							math.cos(angle) * dist,
							(math.random() - 0.5) * 2,
							math.sin(angle) * dist
						)
						particle.Parent = workspace
						
						for k = 1, 12 do
							task.wait(0.03)
							local toCenter = (voidCore.Position - particle.Position).Unit
							particle.Position = particle.Position + toCenter * 0.3
							particle.Size = particle.Size * 0.9
							particle.Transparency = k / 12
						end
						particle:Destroy()
					end)
					task.wait(0.05)
				end
				
				-- Shrink and fade the void core
				task.spawn(function()
					for k = 1, 15 do
						task.wait(0.05)
						voidCore.Size = voidCore.Size * 0.9
						voidCore.Transparency = k / 15
					end
					voidCore:Destroy()
				end)
			else
				-- Generic colored effect for any other rune
				for i = 1, 5 do
					local particle = Instance.new("Part")
					particle.Size = Vector3.new(0.4, 0.4, 0.4)
					particle.Shape = Enum.PartType.Ball
					particle.Material = Enum.Material.Neon
					particle.Color = color
					particle.Anchored = true
					particle.CanCollide = false
					particle.Position = root.Position + Vector3.new(
						(math.random() - 0.5) * 2,
						math.random() * 2,
						(math.random() - 0.5) * 2
					)
					particle.Parent = workspace
					
					task.spawn(function()
						for k = 1, 10 do
							task.wait(0.04)
							particle.Position = particle.Position + Vector3.new(0, 0.1, 0)
							particle.Transparency = k / 10
						end
						particle:Destroy()
					end)
					task.wait(0.03)
				end
			end
		end)
	end
end

return EnemyManager
