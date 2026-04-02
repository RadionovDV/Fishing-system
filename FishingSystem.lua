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
local TensionHandler = require(script.TensionHandler)
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
	tensionHandler: TensionHandler.ClassType,
	screenGui: ScreenGui,
	connections: { [string]: Signal.SignalConnection },
}, FishingSystem))

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
