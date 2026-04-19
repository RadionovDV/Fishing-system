--!strict
--[[	
	This example is part of a Fishing module system that you can implement in any Roblox experience.
	I split this code into two responsible blocks: FishingSystem and TensionHandler
	Below, I break down the basics of these two parts as clearly as possible, without going too deep into the details.
	You can also watch the entire coding process at this link.
	https://drive.google.com/file/d/17ik7v5JysyYROWfB6aXLWsTpcY2fp24l/view?usp=sharing
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Utils.Signal)
local TableUtils = require(ReplicatedStorage.Utils.TableUtils)
local FishingDescription = require(script.Parent.FishingDescription)
local FishingConfig = require(script.Parent.FishingConfig)
local TensionHandler = require(script.TensionHandler)
local PowerHandler = require(script.PowerHandler)
local BiteIndicator = require(script.BiteIndicator)

local fishingGuiTemplate = ReplicatedStorage.FishingManager.UI.Objects.FishingGui :: ScreenGui
local rewardFrameTemplate = ReplicatedStorage.FishingManager.UI.Objects.RewardFrame :: RewardFrame
local messageLabelTemplate = ReplicatedStorage.FishingManager.UI.Objects.MessageLabel :: TextLabel
local tensionBarTemplate = ReplicatedStorage.FishingManager.UI.Objects.TensionBar :: TensionBar

local player = Players.LocalPlayer :: Player
local playerGui = player.PlayerGui 

local TEXT_REWARD_TEXT = "You caught a"
local TEXT_RARITY_TEXT = "Rarity:"
local TEXT_WEIGHT_TEXT = "Weight:"
local TEXT_FISH_BROKE = "The fish broke"
local TEXT_FISH_MISSED = "The fish was missed"

local START_FISH_POSITION = 50
local PLACEHOLDER_FISH_DESTINATION = 80
local PLACEHOLDER_FISH_MOVE_TIME = 5

type RewardFrame = Frame & {
	AcceptButton: TextButton,
	RewardText: TextLabel,
	FishImage: ImageLabel,
	InfoFrame: Frame & {
		RarityLabel: TextLabel,
		WeightLabel: TextLabel,
	}
}

type TensionBar = Frame & {
	CatchZone: Frame,
	FishIcon: ImageLabel,
	ProgressLabel: TextLabel,
}

local TensionHandler = {}
TensionHandler.__index = TensionHandler

type FinishedFunc = (boolean) -> ()

export type ClassTypeTension = typeof(setmetatable({} :: {
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

--[[
	First Responsible Block
	TensionHandler - this class is responsible for the fishing mini-game logic. It is created each time when the player reacts to a bite
	
	How does it work?
	This module extracts the necessary information about fish behavior and fishing rod properties from the shared FishingDescription file.
	Each time, it updates the fish position and the catch zone position, and compares them to get a progress value and display the result on the GUI
	Each frame, it calculates the time step for smooth system behavier and to avoid dependency on FPS
	finishedFunc handles the completion of the class's work.
	After all calculation, it renders the result on the GUI
	
	What is required to initialize this class?
	- GUI elements
	- name descriptions (for calculations and simulating fishing behavior)
	
	User flow (simplified form)
	-> new
		-> RunService.Heartbeat
			-> _getCatchPosiiton
			-> _getFishPosiiton
			-> _getProgress
				-> progress > 100
					-> finishedFunc
]]
function TensionHandler.new(fishType: string, fishWeight: number, rodType: string, finishedFunc: FinishedFunc): ClassTypeTension
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

-- This public method is a single point for handling external actions in the system's workflow
function TensionHandler.switchCatchZone(self: ClassTypeTension, rising: boolean)
	self.catchRising = rising
end

-- This method runs on each frame and implements entire TensionHandler logic: calculation -> render GUI -> check condition -> callback.
function TensionHandler._update(self: ClassTypeTension)
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

-- This method responds to the question: which position does the fish aim for?
-- It extracts object descriptions by name from the FishingDescription file, using their properties to simulate the fish and the fishing rod
-- If the fish might go beyound the tension bar area, this method prevents that and flips the fish's movement direction.
function TensionHandler._updateFishBehavior(self: ClassTypeTension, fishPosition: number)
	local behavior =  FishingDescription.fishTypes[self.fishType].behavior

	-- calculate fish jurk probability
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
	
	-- caldulate move direction
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

-- This method updates catchPosition using the current direciton and movement step
function TensionHandler._getCatchPosiiton(self: ClassTypeTension, step: number): number
	local catchStep = (step - self.prevStep) * 100 / self.catchZoneSpeed

	local catchPercent = self.catchPosition
	if self.catchRising then
		catchPercent -= catchStep
	else
		catchPercent += catchStep
	end	
	return math.clamp(catchPercent, 0, 100)
end

-- This method updates fish's position based on its direction and speed
-- the system updates the fish's direction each time it reache its destination point
function TensionHandler._getFishPosiiton(self: ClassTypeTension, step: number): number
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

-- This method calcaulates the catchZone area boundaries, chacks whether the fish is within the catchZone and updates the fishing progress
function TensionHandler._getProgress(self: ClassTypeTension, step: number): number
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

-- This method updates the catch zone position, fish position, and fishing progress value
function TensionHandler._updateUI(self: ClassTypeTension)
	local catchZonePosition = (1 - self.catchZoneSize) * (self.catchPosition / 100) + self.catchZoneSize

	self.catchZoneUI.Position = UDim2.fromScale(0, catchZonePosition)

	local fishIconPosition = self.fishPosition / 100
	self.fishIconUI.Position = UDim2.fromScale(0.5, fishIconPosition)

	local progress = math.floor(self.progress)
	self.progressLabelUI.Text = `{progress} %`
end

-- This method completes the work of class, it clears signal connections and removes excess GUI objects 
function TensionHandler._clear(self: ClassTypeTension)
	self.connection:Disconnect()
	self.tensionBarUI:Destroy()
end

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
	tensionHandler: TensionHandler.ClassType,
	screenGui: ScreenGui,
	connections: { [string]: Signal.SignalConnection },
}, FishingSystem))

--[[	
	Second Responsible Block
	
	FishingSystem - a singlton that implements the entire fishing process, from casting the rod to granting the reward (catching the fish)
	Its primary responsibility is managing system state and handling external acitons.
	The class exposes three public methods, which serve as entry points for each stage of the fishing process
	
	How do these three public methods work?
	- Each publish methods receives a signal and a callback
	- Delegates execution of the core logic to an encapsulated script
	- Forwardes the signal to the coresponding public method of encapsulated script
	- The encapsulated script invokes the callback upon completion of execution
	
	User flow (simplified form)
	-> new
		-> powerHandleAsync
			-> PowerHandler
				-> onCast
		-> waitForFishAsync
			-> BiteIndicator
				-> onBite
		-> catchingFishAsync
			-> TensionHandler
				-> onCatch
]]
function FishingSystem.new(): ClassType
	local self = {
		fishingState = FishingConfig.FishingStates.WaitForFishing,
		castTime = 0,
		connections = {},
	}

	setmetatable(self, FishingSystem)
	return self :: ClassType
end

-- This method renders the reward for the player using fish descriptions.
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

-- This method displays received messages and hides them after a certain duration
function FishingSystem._showMessage(self: ClassType, message: string)
	local messageLabel = messageLabelTemplate:Clone()
	messageLabel.Text = message
	messageLabel.Parent = self.screenGui

	task.delay(FishingConfig.POPUP_MESSAGE_TIME, function()
		messageLabel:Destroy()
	end)
end

--[[
	Public method
	
	catchingFishAsync - uses TensionHandler to run the fishing mini-game.
	it forwards signals to TensionHandler to handle external control acitons.
	At the end of the mini-game, it results and displays the result.
]]
function FishingSystem.catchingFishAsync(
	self: ClassType, 
	onCatch: (boolean, string?) -> (), 
	actionEvent: Signal.ClassType, 
	releaseEvent: Signal.ClassType, 
	audioSignal: Signal.ClassType
)	
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

	self.tensionHandler = TensionHandler.new(self.fishType, self.fishWeight, self.activeRod, onFinished)
	self.tensionHandler.tensionBarUI.Parent = self.screenGui

	self.connections.actionConnection = actionEvent:Connect(function() self.tensionHandler:switchCatchZone(true) end)
	self.connections.releaseConnection = releaseEvent:Connect(function() self.tensionHandler:switchCatchZone(false) end)
end

--[[
	Public method
	
	waitForFishAsync - impements the fish waiting mechanic
	This method creates a bite window for the player and waits for input durring this period.
	if the time expires, waitForFishAsync is invoked again while preserving system state
	
	User flow
	-> waitForFishAsync()
		-> BiteIndicator.new()
			-> if no react()
				-> waitForFishAsync()
			-> if react() not in time
				-> cancel()
			-> if react() in time
				-> onBite()
					-> catchingFishAsync()
			
]]
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

	local function onWaitFinished(success: boolean, missedFish: boolean)
		local isMissedFish = false
		if success then
			self:_clearAllConnections()
			self.fishingState = FishingConfig.FishingStates.CatchingFish
		end

		if missedFish then
			self:_showMessage(TEXT_FISH_MISSED)
			isMissedFish = true
		end
		
		if (not success) and (not missedFish) then
			self:cancel()
		end

		onBite(success, isMissedFish)
	end

	if not self.connections.actionConnection then
		self.biteIndicator = BiteIndicator.new(waitingTime, biteDuration, onWaitFinished)
		self.biteIndicator.biteLabelUI.Parent = self.screenGui
	end

	if self.fishingState == FishingConfig.FishingStates.InitFishing then
		self.connections.actionConnection = actionEvent:Connect(function()
			self.biteIndicator:react()
		end)
	else
		self.biteIndicator:reloadTime(waitingTime, biteDuration)
	end

	self.fishingState = FishingConfig.FishingStates.WaitForFish
end


--[[
	Public method
	
	powerHandleAsync - responsible for the rod casting mechanic
	This method deligates the core logic to an encapsulating script ,
	forward signals for external control acitons,
	and returns the result through a callback
]]
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
		onCast(success, powerProgress)
	end 

	local powerHandler = PowerHandler.new(rodType, onFinished)
	powerHandler.powerBarUI.Parent = self.screenGui

	self.connections.cancelConnection = cancelEvent:Connect(function()
		powerHandler:cancel()
	end)
	
	self.connections.releaseConnection = releaseEvent:Connect(function()
		powerHandler:returnProgress()
	end)
end

-- Since the system operates with the external signals, it includes an additional method to clear up connections and free allocated memory 
function FishingSystem._clearAllConnections(self: ClassType)
	for name, connection in pairs(self.connections) do
		if connection then
			(connection :: any):Disconnect()
			self.connections[name] = nil
		end
	end
end

-- This public method cancels the fishing process. Resets the system to its default state, disconnects all signals and removes GUI elements
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
