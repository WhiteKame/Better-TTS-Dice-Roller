-- FTC-GUID: 4e0e0b,beae28
--Based off: https://steamcommunity.com/sharedfiles/filedetails/?id=726800282
--Link for this mod: https://steamcommunity.com/sharedfiles/filedetails/?id=959360907
lastRolls={}
scaleBtn=3
printLastBtn={
    label="Last roll", click_function="printLast", function_owner=self,
    position={-2.5,0.1,-0.87}, rotation={0,0,0}, height=50, width=400,
    font_size=60, color={0,0,0}, font_color={1,1,1}, scale={scaleBtn,scaleBtn,scaleBtn}
}
printLast5Btn={
    label="Last 5 rolls", click_function="printLast5", function_owner=self,
    position={2.5,0.1,-0.87}, rotation={0,0,0}, height=50, width=400,
    font_size=60, color={0,0,0}, font_color={1,1,1}, scale={scaleBtn,scaleBtn,scaleBtn}
}

function printLast()
	printResults(1)
end

function printLast5()
	printResults(5)
end

function printResults(n)
	if #lastRolls==0 then
		printToAll("NO LAST ROLLS\n", "Yellow")
	else
		printToAll("LAST ROLLS\n")

		-- This little bit of complexity ensures we present the LAST n from
		-- _lastrolls_ and, if asked to present (say) the last 3 out of a table
		-- of 6, number them 3-2-1 despite them being indexes 4-5-6!
		n = math.min(n, #lastRolls)
		first = #lastRolls - n + 1
		for i = first, #lastRolls do
			result = lastRolls[i]
			printToAll("-- " .. #lastRolls - i + 1 .. " --\n" .. result.msg, result.color)
		end
	end
end

--Initialize Global Variables and pRNG Seed
ver = 'BCB-2022-12-30'
lastHolder = {}
customFace = {4, 6, 8, 10, 12, 20}
diceGuidFaces = {}
sortedKeys = {}
resultsTable = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
seedCounter = 0

thisBoxIsBlue = (self.guid == Global.getVar("blueDiceRoller_GUID")) and true or false

orderedOnNextRoll = false
groupSizeOnNextRoll = 1

objectToPlaceDiceOnGUID = thisBoxIsBlue and Global.getVar("blueDiceMat_GUID") or Global.getVar("redDiceMat_GUID")
objectToPlaceDiceOn = getObjectFromGUID(objectToPlaceDiceOnGUID)
if objectToPlaceDiceOn == nil then
    objectToPlaceDiceOn = self
end

--add seed perturbation
function generateSeed()
    local timeSeed = os.time()
    local clockSeed = math.floor(os.clock() * 1000000)
    local addressSeed = tonumber(tostring({}):sub(8), 16) -- get the memory address of the table
    local randomSeed = timeSeed + clockSeed + addressSeed
    return randomSeed % 2^31 -- make sure the seed is within a reasonable range
end
math.randomseed(generateSeed())


-- simplified implementation of the Mersenne Twister pseudo-random number generator
local mt = {}  -- mersenne Twister algorithm state array
local index = 0  -- current Status Index

-- initialize the Mersenne Twister generator
function initMersenneTwister(seed)
    index = 0
    mt[0] = seed
    for i = 1, 623 do
        mt[i] = bit32.bxor(mt[i - 1], bit32.rshift(mt[i - 1], 30)) + i
    end
end

-- get the next random number
function nextMersenneTwister()
    local y = mt[index]
    y = bit32.bxor(y, bit32.rshift(y, 11))
    y = bit32.bxor(y, bit32.lshift(bit32.band(y, 0xFFFFFFF), 7))
    y = bit32.bxor(y, bit32.lshift(bit32.band(y, 0xFFFFFFF), 15))
    y = bit32.bxor(y, bit32.rshift(y, 18))
    index = (index + 1) % 624
    return y
end

-- generate random numbers and map them to the [min, max] interval
function mersenneRandom(min, max)
    local result = nextMersenneTwister()
    return math.floor(result % (max - min + 1)) + min
end

-- initialize
initMersenneTwister(os.time())

-- used to nil out a passed parameter
--   remember, this will leave the parameter itself nil
-- LUA will not clear out globally scoped variables automatically
-- setting each element to nil will allow the gc to clear it out
function clearDataForGC(data)
  if data == nil then
    -- nothing needs to be done, return
    return
  end
  for n, element in ipairs(data) do
    element = nil
  end
end

--Determine the person who put the dice in the box.
function onObjectPickedUp(playerColor, obj)
	lastHolder[obj] = playerColor
end

--Reset the person holding the dice when no dice are held.
function onObjectDestroyed(obj)
	lastHolder[obj] = nil
end

--Reset description on load if empty.
function onLoad(save_state)
	if self.getDescription() == '' then
		setDefaultState()
	end
	self.createButton(printLastBtn)
	self.createButton(printLast5Btn)
end

--Returns description on game save.
function onSave()
	return self.getDescription()
end

--Reset description on drop if empty.
function onDropped(player_color)
	if self.getDescription() == '' then
		setDefaultState()
	end
end

--Sets default description.
function setDefaultState()
	self.setDescription(JSON.encode_pretty({Results = 'no', SmoothDice = 'no', RotateDice = 'no', Rows = 'yes', SortNoRows = 'asc', Step = 1.05, Version = ver}))
end

--Creates a table and sorts the dice guids by value.
function sortByVal(t, type)
	local keys = {}
	for key in pairs(t) do
		table.insert(keys, key)
	end
	if type == 'asc' then
		table.sort(keys, function(a, b) return t[a] < t[b] end)
	elseif type == 'desc' then
		table.sort(keys, function(a, b) return t[a] > t[b] end)
	end
	return keys
end

--Checks the item dropped in the bag has a guid.
function hasGuid(t, g)
	for k, v in ipairs(t) do
		if v.guid == g then return true end
	end

	return false
end

--Runs when non-dice is put into bag
function onObjectEnterContainer(container, obj)
    if container == self then
        if obj.tag == "Dice" then
            collision_info = {collision_object = obj}
            onCollisionEnter(collision_info)

            --Creates a timer to take the dice out and position them.
        	Wait.time(|| takeDiceOut(), 0.3)
        else
            local pos = self.getPosition()
            local f = self.getTransformRight()
            self.takeObject({
                position          = {pos.x+20,pos.y+50,pos.z+20},
                smooth            = false,
            })
        end
    end
end

--Runs when an object is dropped in bag.
function onCollisionEnter(collision_info)
	playerColor = lastHolder[collision_info.collision_object]
	if collision_info.collision_object.getGUID() == nil then return end
    clearDataForGC(diceGuidFaces)
    clearDataForGC(sortedKeys)
	diceGuidFaces = {}
	sortedKeys = {}

    -- Save number of faces on dice
	for k, v in ipairs(getAllObjects()) do
		if v.tag == 'Dice' then
			objType = tostring(v)
			faces = tonumber(string.match(objType, 'Die_(%d+).*'))
			if faces == nil then
				faces = tonumber(customFace[v.getCustomObject().type + 1])
			end
            diceGuidFaces[v.getGUID()] = faces
            table.insert(sortedKeys, v.getGUID())
		end
	end

--[[Benchmarking code
if resetclock ~= 1 then
clockstart = os.clock()
resetclock = 1
end--]]

end

function takeDiceOut(tab)
    local data = JSON.decode(self.getDescription())
    if data == nil then
        setDefaultState()
        data = JSON.decode(self.getDescription())
        printToAll('Warning - invalid description. Restored default configuration.', {0.8, 0.5, 0})
    end

    if data.Step < 1 then
        setDefaultState()
        data = JSON.decode(self.getDescription())
        printToAll('Warning - "step" can\'t be lower than 1. Restored default configuration.', {0.8, 0.5, 0})
    end

    clearDataForGC(diceGuids)
    diceGuids = {}

    for _, obj in pairs(self.getObjects()) do
        local faces = diceGuidFaces[obj.guid] or 6
        if obj.name == "BCB-D3" then
            faces = 3
        end
        diceGuids[obj.guid] =mersenneRandom(1, 6)  -- output a random number between 1 and 6
    end

    local ordered = orderedOnNextRoll
    orderedOnNextRoll = false
    local groupSize = groupSizeOnNextRoll
    groupSizeOnNextRoll = 1
    local objs = self.getObjects()
    local position = objectToPlaceDiceOn.getPosition()
    local rotation = objectToPlaceDiceOn.getRotation()
    local displayInRows = data.Rows ~= 'no'
    if ordered then displayInRows = false end

    local sortType = data.SortNoRows
    if ordered then sortType = "none" end

    local sortedKeys = sortByVal(diceGuids, sortType)
    clearDataForGC(Rows)
    Rows = {}
    local n = 1

    for _, key in pairs(sortedKeys) do
        if diceGuids[key] == math.floor(diceGuids[key]) then
            resultsTable[diceGuids[key]] = (resultsTable[diceGuids[key]] or 0) + 1
        end

        if hasGuid(objs, key) then
            Rows[diceGuids[key]] = (Rows[diceGuids[key]] or 0) + 1
            local newXPos, newZPos
            if displayInRows then
                local d12Xoffset = diceGuids[key] > 6 and -24 or 0
                newXPos = 0 - d12Xoffset - 20.4 + (Rows[diceGuids[key]] * data.Step)
                newZPos = -3.17 + ((((diceGuids[key] - 1) % 6) + 1) * data.Step)
            else
                local pos = n - 1
                local limit = 25
                if groupSize > 1 then
                    pos = pos + math.floor(pos / groupSize)
                    local step = groupSize + 1
                    local maxGroups = math.floor(limit / step)
                    local remainder = limit % (step * maxGroups)
                    limit = limit - remainder
                end
                local row = math.floor(pos / limit) + 1
                local col = pos % limit
                newXPos = 0 - 15.0 + (col * data.Step)
                newZPos = -3.17 + (row * data.Step)
            end

            local finalPosition = {
                position.x + (newXPos * math.cos((180 + rotation.y) * 0.0174532)) - (newZPos * math.sin((180 + rotation.y) * 0.0174532)),
                position.y + 2,
                position.z + (newXPos * math.sin(rotation.y * 0.0174532)) + (newZPos * math.cos(rotation.y * 0.0174532))
            }

            self.takeObject({
                guid = key,
                position = finalPosition,
                rotation = rotation,
                callback = 'setValueCallback',
                params = {diceGuids[key]},
                smooth = data.SmoothDice == 'yes'
            })

            n = n + 1
        end
    end

    printresultsTable()
end

--Function to count resultsTable for printing.
function sum(t)
	local sum = 0
	for k, v in pairs(t) do
		sum = sum + v
	end

	return sum
end

function setPlayerColor(params)
    playerColor = params.color
end

function setLastHolder(params)
    lastHolder[params.obj] = params.color
end

--Prints resultsTable.
function printresultsTable()
	local data = JSON.decode(self.getDescription())
	local description = {'Ones.', 'Twos.', 'Threes.', 'Fours.', 'Fives.', 'Sixes.', 'Sevens.', 'Eights.', 'Nines.', 'Tens.', 'Elevens.', 'Twelves.', 'Thirteens.', 'Fourteens.', 'Fifteens.', 'Sixteens.', 'Seventeens', 'Eighteens.', 'Nineteens.', 'Twenties.'}
	local msg = ''
	local color={1,1,1}
	for dieFace, numRolled in ipairs(resultsTable) do
		if numRolled > 0 then
			msg = msg .. numRolled .. ' ' .. description[dieFace] .. ' '
		end
	end

	local time = '[' .. os.date("%H") .. ':' .. os.date("%M") .. ':' .. os.date("%S") .. ' UTC] '
	if playerColor == nil then
		msg=time .. '~UNKNOWN PLAYER~ rolls:\n' .. msg .. '*******************************************************'
	else
		msg=time .. Player[playerColor].steam_name .. ' rolls:\n' .. msg .. '*******************************************************'
		color=stringColorToRGB(playerColor)
	end
	local rolltorecord={msg=msg, color=color}
	if sum(resultsTable) > 0 then
		if #lastRolls >= 5 then
			table.remove(lastRolls, 1)
		end
		table.insert(lastRolls, #lastRolls+1, rolltorecord)
	end

	if sum(resultsTable) > 0 and data.Results == 'yes' then
		printToAll(msg, color)
	end

	for k,v in ipairs(resultsTable) do
		resultsTable[k] = 0
	end
end

--Sets the value of the physical dice object and reorients them if needed.
function setValueCallback(obj, tab)
    local rotValues = obj.getRotationValues()
	obj.setRotation(rotValues[tab[1]].rotation + Vector(0, 180.0 + objectToPlaceDiceOn.getRotation()[2], 0))
end