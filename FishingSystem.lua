--!strict
--[[
	this code was completely written without AI
	you can see the whole process of writing by this link in Google Drive
	
	https://drive.google.com/file/d/1M6eq35zA7BQfFiciGyUdV-vB70OnbGwK/view?usp=sharing
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

type RewardFrame = Frame & {
	AcceptButton: TextButton,
	RewardText: TextLabel,
	FishImage: ImageLabel,
	InfoFrame: Frame & {
		RarityLabel: TextLabel,
		WeightLabel: TextLabel,
	}
}

local Signal = require(ReplicatedStorage.Utils.Signal)
local TableUtils = require(ReplicatedStorage.Utils.TableUtils)
local FishingDescription = require(script.Parent.FishingDescription)
local FishingConfig = require(script.Parent.FishingConfig)
local PowerHandler = require(script.PowerHandler)
local BiteIndicator = require(script.BiteIndicator)

local fishingGuiTemplate = ReplicatedStorage.FishingManager.UI.Objects.FishingGui :: ScreenGui
local rewardFrameTemplate = ReplicatedStorage.FishingManager.UI.Objects.RewardFrame :: RewardFrame
local messageLabelTemplate = ReplicatedStorage.FishingManager.UI.Objects.MessageLabel :: TextLabel

local player = Players.LocalPlayer :: Player
local playerGui = player.PlayerGui 

local TEXT_REWARD_TEXT = "You caught a"
local TEXT_RARITY_TEXT = "Rarity:"
local TEXT_WEIGHT_TEXT = "Weight:"
local TEXT_FISH_BROKE = "The fish broke"
local TEXT_FISH_MISSED = "The fish was missed"

local FishingSystem = {}
FishingSystem.__index = FishingSystem

FishingSystem.actionSignal = Signal.new()
FishingSystem.releaseSignal = Signal.new()
FishingSystem.cancelSignal = Signal.new()

export type ClassType = typeof(setmetatable({} :: {
	activeRod: string,
	fishingState: number,
	fishType: string,
	fishWeight: number,
	castTime: number,
	biteIndicator: BiteIndicator.ClassType,
	tensionHandler: TensClassType,
	screenGui: ScreenGui,
	connections: { [string]: Signal.SignalConnection },
}, FishingSystem))

type TensionBar = Frame & {
	CatchZone: Frame,
	FishIcon: ImageLabel,
	ProgressLabel: TextLabel,
}

local tensionBarTemplate = ReplicatedStorage.FishingManager.UI.Objects.TensionBar :: TensionBar

local TensionHandler = {}
TensionHandler.__index = TensionHandler

type FinishedFunc = (boolean) -> ()

export type TensClassType = typeof(setmetatable({} :: {
	fishType: string,
	startTime: number,
	prevStep: number,
	preventLose: boolean,
	progress: number,
	progressSpeed: number,

	catchPosition: number,
	catchRising: boolean,
	catchZoneSpeed: number,
	catchZoneSize: number,

	fishPosition: number,
	fishRising: boolean,
	fishDestination: number,
	fishMoveTime: number,

	tensionBarUI: TensionBar,
	catchZoneUI: Frame,
	fishIconUI: ImageLabel,
	progressLabelUI: TextLabel,

	finishedFunc: FinishedFunc,
	connection: RBXScriptConnection
}, TensionHandler))

local START_FISH_POSITION = 50
local PLACEHOLDER_FISH_DESTINATION = 80
local PLACEHOLDER_FISH_MOVE_TIME = 5

-- Here we create TensionHandler, which implements the fishing mini-game
function TensionHandler.new(fishType: string, fishWeight: number, rodType: string, finishedFunc: FinishedFunc): TensClassType
	local tensionBar = tensionBarTemplate:Clone()
	local catchZone = tensionBar.CatchZone
	local fishIcon = tensionBar.FishIcon
	local progressLabel = tensionBar.ProgressLabel

	local minWeight = FishingDescription.fishTypes[fishType].weightMin
	local maxWeight = FishingDescription.fishTypes[fishType].weightMax
	local decelerationPercent = (fishWeight - minWeight) * 100 / maxWeight

	local baseSpeed = FishingDescription.fishTypes[fishType].fishingSpeedProgress
	local progressSpeed = baseSpeed * (decelerationPercent / 100)

	local self = {
		-- Base
		fishType = fishType,
		startTime = os.clock(),
		prevStep = os.clock(),
		preventLose = true,
		progress = 0,
		progressSpeed = progressSpeed,

		-- Catch Zone
		catchPosition = START_FISH_POSITION,
		catchRising = false,
		catchZoneSpeed = FishingDescription.rodTypes[rodType].catchZoneSpeed,
		catchZoneSize = FishingDescription.fishTypes[fishType].catchZone,

		-- Fish Behavior
		fishPosition = START_FISH_POSITION,
		fishRising = true,
		fishDestination = PLACEHOLDER_FISH_DESTINATION,
		fishMoveTime = PLACEHOLDER_FISH_MOVE_TIME,

		--UI
		tensionBarUI = tensionBar,
		catchZoneUI = catchZone,
		fishIconUI = fishIcon,
		progressLabelUI = progressLabel,

		finishedFunc = finishedFunc,
	}
	setmetatable(self, TensionHandler)

	catchZone.Size = UDim2.fromScale(1, self.catchZoneSize)	

	self:_updateFishBehavior(self.fishPosition)
	self.connection = RunService.Heartbeat:Connect(function()
		self:_update()
	end)

	task.delay(FishingConfig.PENDING_BEFORE_TENSION, function() self.preventLose = false end)

	return self
end

-- When the player presses or releases the action button, it switches the catch rising direction up or down
function TensionHandler.switchCatchZone(self: TensClassType, rising: boolean)
	self.catchRising = rising
end

-- In this method we calculate the green zone position and fish icon position 
-- when the fish icon stays inside the green zone, we increase the percent 
-- otherwise the percent decreases 
function TensionHandler._update(self: TensClassType)
	local step = os.clock()
	self.catchPosition = self:_getCatchPosiiton(step)
	self.fishPosition = self:_getFishPosiiton(step)
	self.progress = self:_getProgress(step)

	self:_updateUI()
	self.prevStep = step

	if self.progress >= 100 then
		self:_clear()
		self.finishedFunc(true)
	end

	if self.progress <= 0 and not self.preventLose then
		self:_clear()
		self.finishedFunc(false)
	end
end

-- Here we calculate when the fish icon changes movement direction and speed
function TensionHandler._updateFishBehavior(self: TensClassType, fishPosition: number)
	local behavior =  FishingDescription.fishTypes[self.fishType].behavior

	-- calculate jerk probability
	local isJerk = math.random() * 100 <= behavior.jerkProbability and true or false
	if isJerk then
		self.fishMoveTime = behavior.jerkTime
	else
		self.fishMoveTime = behavior.maxMoveTime - math.random() * (behavior.maxMoveTime - behavior.minMoveTime)
	end

	-- calculate move distance
	local isRaiseDirection = math.random() >= 0.5 and true or false
	local moveDistance = behavior.maxMoveDistance - math.random() * (behavior.maxMoveDistance - behavior.minMoveDistance)

	if isJerk then
		moveDistance = moveDistance * behavior.jerkDistanceMult
	end

	local nextDestination: number
	if isRaiseDirection then
		nextDestination = fishPosition - moveDistance
		if nextDestination < 0 and fishPosition <= 50 then
			isRaiseDirection = false
		end
	end
	if not isRaiseDirection then
		nextDestination = fishPosition + moveDistance
	end

	self.fishRising = isRaiseDirection
	self.fishDestination = math.clamp(nextDestination, 0, 100)
end

-- calculation of the green zone
function TensionHandler._getCatchPosiiton(self: TensClassType, step: number): number
	local catchStep = (step - self.prevStep) * 100 / self.catchZoneSpeed

	local catchPercent = self.catchPosition
	if self.catchRising then
		catchPercent -= catchStep
	else
		catchPercent += catchStep
	end	
	return math.clamp(catchPercent, 0, 100)
end

-- calculate fish icon position
function TensionHandler._getFishPosiiton(self: TensClassType, step: number): number
	local fishStep = (step - self.prevStep) * 100 / self.fishMoveTime
	local fishPosition = self.fishPosition

	if self.fishRising then
		fishPosition -= fishStep
		if fishPosition <= self.fishDestination then
			self:_updateFishBehavior(fishPosition)
		end
	else
		fishPosition += fishStep
		if fishPosition >= self.fishDestination then
			self:_updateFishBehavior(fishPosition)
		end
	end

	return math.clamp(fishPosition, 0, 100)
end

-- calculate progress percent
function TensionHandler._getProgress(self: TensClassType, step: number): number
	local progressStep = (step - self.prevStep) * 100 / self.progressSpeed

	--75 (100% - catchSize(25)) Portion of the bar where the catch zone can move
	local availableBarPercent = 100 - self.catchZoneSize * 100 -- Could be moved to self

	-- from 0 to 75 (currentPercent / 100 * 75) catch position scaled to the available movement range
	local catchPositionInAvailableRange = self.catchPosition / 100 * availableBarPercent 

	-- 12.5 (catchSize(25) / 2) Offset required to center the catch zone (half of its size)
	local catchZoneHalfOffsetPercent = self.catchZoneSize * 100 / 2 -- Could be moved to self

	-- from 12.5 to 87.5 Final calculated position of the catch zone on the bar
	local finalCatchPosition = catchZoneHalfOffsetPercent + catchPositionInAvailableRange

	local catchMinBorder = finalCatchPosition - catchZoneHalfOffsetPercent
	local catchMaxBorder = finalCatchPosition + catchZoneHalfOffsetPercent
	local fishPosition = self.fishPosition
	--local fishPosition = 90
	local progress = self.progress

	if fishPosition >= catchMinBorder and fishPosition <= catchMaxBorder then
		progress += progressStep
	else
		progress -= progressStep
	end

	return math.clamp(progress, 0, 100)
end

-- here we update the screen GUI for the player, we just change parameters of the fish icon and green zone
function TensionHandler._updateUI(self: TensClassType)
	local catchZonePosition = (1 - self.catchZoneSize) * (self.catchPosition / 100) + self.catchZoneSize

	self.catchZoneUI.Position = UDim2.fromScale(0, catchZonePosition)

	local fishIconPosition = self.fishPosition / 100
	self.fishIconUI.Position = UDim2.fromScale(0.5, fishIconPosition)

	local progress = math.floor(self.progress)
	self.progressLabelUI.Text = `{progress} %`
end

function TensionHandler._clear(self: TensClassType)
	self.connection:Disconnect()
	self.tensionBarUI:Destroy()
end

-- We create this singleton class once when the player joins the game
function FishingSystem.new(): ClassType
	local self = {
		fishingState = FishingConfig.FishingStates.WaitForFishing,
		castTime = 0,
		connections = {},
	}

	setmetatable(self, FishingSystem)
	return self :: ClassType
end

-- this function just shows a reward to the player
function FishingSystem._showReward(self:ClassType, releaseFunc: () -> ())
	local rewardFrame = rewardFrameTemplate:Clone()
	local rewardText = rewardFrame.RewardText
	local fishImage = rewardFrame.FishImage
	local acceptButton = rewardFrame.AcceptButton
	local infoFrame = rewardFrame.InfoFrame
	local rarityLabel = infoFrame.RarityLabel
	local weightLabel = infoFrame.WeightLabel

	local fishName = FishingDescription.fishTypes[self.fishType].name
	local fishRarityLevel = math.ceil(FishingDescription.fishTypes[self.fishType].rarity / 10)
	local fishWeight = math.floor(self.fishWeight * 1000) / 1000

	fishImage.Image = FishingDescription.fishTypes[self.fishType].icon
	rewardText.Text = `{TEXT_REWARD_TEXT} {fishName}`
	rarityLabel.Text = `{TEXT_RARITY_TEXT} {fishRarityLevel}`
	weightLabel.Text = `{TEXT_WEIGHT_TEXT} {fishWeight}`

	acceptButton.Activated:Once(function()
		releaseFunc()
	end)

	rewardFrame.Parent = self.screenGui
end

function FishingSystem._showMessage(self: ClassType, message: string)
	local messageLabel = messageLabelTemplate:Clone()
	messageLabel.Text = message
	messageLabel.Parent = self.screenGui

	task.delay(FishingConfig.POPUP_MESSAGE_TIME, function()
		messageLabel:Destroy()
	end)
end

-- at the end, when the player has thrown the fishing rod and handled the bite timing
-- we create the fishing mini-game on the player's screen
function FishingSystem.catchingFishAsync(
	self: ClassType, 
	onCatch: (boolean, string?) -> (), 
	actionEvent: Signal.ClassType, 
	releaseEvent: Signal.ClassType, 
	audioSignal: Signal.ClassType
)	
	-- in this function we show a congratulation screen to the player
	-- or cancel fishing with failure
	-- and when the player presses the button we call the callback after completing the catch
	-- send a signal for validation to the server and give the reward to the player
	local function onFinished(success)
		if success then
			audioSignal:Fire()
			self:_showReward(function()
				self.fishingState = FishingConfig.FishingStates.WaitForFishing
				onCatch(true, self.fishType)
			end)
		else
			self:_showMessage(TEXT_FISH_BROKE)
			self.fishingState = FishingConfig.FishingStates.WaitForFishing
			onCatch(false)
		end
	end

	-- in TensionHandler there is all the logic of the fishing mini-game. It creates a moving fish icon and manages the green zone
	-- when the green zone reaches the fish icon and the progress increases to 100 percent, we successfully finish fishing onFishing(true)
	-- otherwise onFishing(false)
	self.tensionHandler = TensionHandler.new(self.fishType, self.fishWeight, self.activeRod, onFinished)
	self.tensionHandler.tensionBarUI.Parent = self.screenGui

	self.connections.actionConnection = actionEvent:Connect(function() self.tensionHandler:switchCatchZone(true) end)
	self.connections.releaseConnection = releaseEvent:Connect(function() self.tensionHandler:switchCatchZone(false) end)
end

-- When the player has thrown the fishing rod, the server already provides the fish type and waiting time
-- if the player misses the fish and does nothing after the bite, the server calls this function again without replacing trigger events
function FishingSystem.waitForFishAsync(
	self: ClassType, 
	fishType: string, 
	fishWeight: number, 
	waitingTime: number,  
	onBite: (boolean, boolean) -> (), 
	actionEvent: Signal.ClassType
)
	local biteDuration = FishingDescription.fishTypes[fishType].biteTime

	self.fishType = fishType
	self.fishWeight = fishWeight

	-- this function is called after the bite expires or when the player triggers the action event
	local function onWaitFinished(success: boolean, missedFish: boolean)
		local isMissedFish = false
		if success then
			self:_clearAllConnections()
			-- only if the player reacts in time by pressing the button, the system changes state 
			self.fishingState = FishingConfig.FishingStates.CatchingFish
		end

		if missedFish then
			self:_showMessage(TEXT_FISH_MISSED)
			isMissedFish = true
		end

		-- this callback changes the state
		onBite(success, isMissedFish)
	end

	if not self.connections.actionConnection then
		-- if the player hasn't thrown the fishing rod earlier, we start the bite cooldown 
		self.biteIndicator = BiteIndicator.new(waitingTime, biteDuration, onWaitFinished)
		self.biteIndicator.biteLabelUI.Parent = self.screenGui
	end

	if self.fishingState == FishingConfig.FishingStates.InitFishing then
		-- also if the player hasn't thrown the fishing rod earlier, we create a connection to the action trigger 
		self.connections.actionConnection = actionEvent:Connect(function()
			self.biteIndicator:react()
		end)
	else
		self.biteIndicator:reloadTime(waitingTime, biteDuration)
	end

	self.fishingState = FishingConfig.FishingStates.WaitForFish
end

-- When the player triggers the active button, it calls powerHandleAsync.
-- This method shows the power bar on the player's screenGui
-- and returns the power percent when the player triggers the release button
function FishingSystem.powerHandleAsync(
	self: ClassType, 
	rodType: string, 
	onCast: (boolean, number?) -> (), 
	releaseEvent: Signal.ClassType, 
	cancelEvent: Signal.ClassType
)
	self.fishingState = FishingConfig.FishingStates.InitFishing
	self.activeRod = rodType

	local screenGui = fishingGuiTemplate:Clone() :: ScreenGui
	screenGui.Parent = playerGui
	self.screenGui = screenGui

	local function onFinished(success: boolean, powerProgress: number?)
		self:_clearAllConnections()
		-- this returns the result of the player casting the fishing rod
		onCast(success, powerProgress)
	end 

	-- Inside PowerHandler there is the rest of the logic for getting the power percent
	local powerHandler = PowerHandler.new(rodType, onFinished)
	powerHandler.powerBarUI.Parent = self.screenGui

	-- when the player triggers the cancel button it will abort powerHandler
	self.connections.cancelConnection = cancelEvent:Connect(function()
		powerHandler:cancel()
	end)
	-- when the player triggers the release button it will call onFinished function
	self.connections.releaseConnection = releaseEvent:Connect(function()
		powerHandler:returnProgress()
	end)
end

-- when the player changes state, we should clear trigger button connections to avoid unpredictable behavior
function FishingSystem._clearAllConnections(self: ClassType)
	for name, connection in pairs(self.connections) do
		if connection then
			(connection :: any):Disconnect()
			self.connections[name] = nil
		end
	end
end

-- This method cancels the fishing process, clears events and restores state
function FishingSystem.cancel(self: ClassType)
	self.fishingState = FishingConfig.FishingStates.WaitForFishing
	self:_clearAllConnections()

	if self.screenGui then
		self.screenGui:Destroy()
	end
	if self.tensionHandler then
		self.tensionHandler.connection:Disconnect()
	end
	if self.biteIndicator then
		self.biteIndicator.connection:Disconnect()
	end
end

return FishingSystem
