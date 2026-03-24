--!strict
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
	threadPending: thread,
}, FishingSystem))

function FishingSystem.new(): ClassType
	local self = {
		fishingState = FishingConfig.FishingStates.WaitForFishing,
		castTime = 0,
		connections = {},
	}
	
	setmetatable(self, FishingSystem)
	return self :: ClassType
end

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

function FishingSystem.catchingFishAsync(self: ClassType, actionEvent: Signal.ClassType, releaseEvent: Signal.ClassType, audioSignal: Signal.ClassType): (boolean, string?)
	self.threadPending = coroutine.running()
	
	local function onFinished(success)
		
		if success then
			audioSignal:Fire()
			self:_showReward(function()
				self.fishingState = FishingConfig.FishingStates.WaitForFishing
				task.spawn(self.threadPending, true, self.fishType)
			end)
		else
			self:_showMessage(TEXT_FISH_BROKE)
			self.fishingState = FishingConfig.FishingStates.WaitForFishing
			task.spawn(self.threadPending, false)
		end
	end
	
	self.tensionHandler = TensionHandler.new(self.fishType, self.fishWeight, self.activeRod, onFinished)
	self.tensionHandler.tensionBarUI.Parent = self.screenGui
	
	self.connections.actionConnection = actionEvent:Connect(function() 	self.tensionHandler:switchCatchZone(true) end)
	self.connections.releaseConnection = releaseEvent:Connect(function() 	self.tensionHandler:switchCatchZone(false) end)
	
	return coroutine.yield()
end

function FishingSystem.waitForFishAsync(self: ClassType, fishType: string, fishWeight: number, waitingTime: number,  actionEvent: Signal.ClassType)
	local biteDuration = FishingDescription.fishTypes[fishType].biteTime
	
	self.fishType = fishType
	self.fishWeight = fishWeight
	self.threadPending = coroutine.running()
	
	local function onWaitFinished(success: boolean, missedFish: boolean)
		if success then
			self:_clearAllConnections()
			self.fishingState = FishingConfig.FishingStates.CatchingFish
			task.spawn(self.threadPending, true, false)
			return
		end

		if missedFish then
			self:_showMessage(TEXT_FISH_MISSED)
			task.spawn(self.threadPending, false, true)
			return
		end

		task.spawn(self.threadPending, false, false)
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
	
	return coroutine.yield()
end

function FishingSystem.powerHandleAsync(self: ClassType, rodType: string, releaseEvent: Signal.ClassType, cancelEvent: Signal.ClassType): (boolean, number?)
	self.fishingState = FishingConfig.FishingStates.InitFishing
	self.threadPending = coroutine.running()
	
	local screenGui = fishingGuiTemplate:Clone() :: ScreenGui
	screenGui.Parent = playerGui
	self.screenGui = screenGui

	local function onFinished(success: boolean, powerProgress: number?)
		if success then
			task.spawn(self.threadPending, true, powerProgress)
			self.activeRod = rodType
			self:_clearAllConnections()
		else
			task.spawn(self.threadPending, false)
		end
	end 
	
	local powerHandler = PowerHandler.new(rodType, onFinished)
	powerHandler.powerBarUI.Parent = self.screenGui

	
	self.connections.cancelConnection = cancelEvent:Connect(function()
		powerHandler:cancel()
	end)
	self.connections.releaseConnection = releaseEvent:Connect(function()
		powerHandler:returnProgress()
	end)
	
	return coroutine.yield()
end

function FishingSystem._clearAllConnections(self: ClassType)
	for name, connection in pairs(self.connections) do
		if connection then
			(connection :: any):Disconnect()
			self.connections[name] = nil
		end
	end
end

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
	
	if self.threadPending then
		if coroutine.status(self.threadPending) == "suspended" then
			task.spawn(self.threadPending, false)
		end
	end
end

return FishingSystem
