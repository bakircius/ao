-- Initialize global variables
LatestGameState = LatestGameState or nil
InAction = InAction or false
Logs = Logs or {}

-- Color codes for logs
local colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

-- Logs messages
local function addLog(msg, text)
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
local function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Initiates an attack
local function attackPlayer(energy)
  print(colors.red .. "Player in range. Attacking." .. colors.reset)
  ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(energy)})
end

-- Moves player randomly
local function moveRandomly()
  print(colors.red .. "No player in range or insufficient energy. Moving randomly." .. colors.reset)
  local directionMap = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
  local randomIndex = math.random(#directionMap)
  ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionMap[randomIndex]})
end

-- Determines the closest target player
local function findClosestTarget(player)
  local closestTarget = nil
  local minDistance = math.huge

  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id then
      local distance = math.sqrt((player.x - state.x)^2 + (player.y - state.y)^2)
      if distance < minDistance then
        minDistance = distance
        closestTarget = state
      end
    end
  end

  return closestTarget, minDistance
end

-- Decides the next action based on player proximity and energy.
local function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  if not player then
    print(colors.red .. "Player state not found." .. colors.reset)
    InAction = false
    return
  end

  local closestTarget, distance = findClosestTarget(player)
  if player.energy > 5 and closestTarget and distance <= 1 then
    attackPlayer(player.energy)
  elseif closestTarget and distance <= 5 then
    moveToTarget(player, closestTarget)
  else
    moveRandomly()
  end

  InAction = false
end

-- Moves player towards the target
local function moveToTarget(player, target)
  local dx = target.x - player.x
  local dy = target.y - player.y
  local direction = ""

  if math.abs(dx) > math.abs(dy) then
    if dx > 0 then
      direction = "Right"
    else
      direction = "Left"
    end
  else
    if dy > 0 then
      direction = "Down"
    else
      direction = "Up"
    end
  end

  print(colors.blue .. "Moving towards target: " .. direction .. colors.reset)
  ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = direction})
end

-- Handles game announcements and triggers state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      autoPay()
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      requestGameState()
    else
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Requests game state update on each tick if no action is in progress.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      requestGameState()
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Automates payment confirmation when waiting period starts.
local function autoPay()
  print("Auto-paying confirmation fees.")
  ao.send({Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
end

-- Requests the game state from the server.
local function requestGameState()
  InAction = true
  print(colors.gray .. "Getting game state..." .. colors.reset)
  ao.send({Target = Game, Action = "GetGameState"})
end

-- Updates the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    print("Game state updated. Print 'LatestGameState' for detailed view.")
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
  end
)

-- Decides the next best action based on the updated game state.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then
      InAction = false
      return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- Automatically attacks when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      local playerEnergy = LatestGameState.Players[ao.id].energy
      if playerEnergy == nil then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        attackPlayer(playerEnergy)
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)
