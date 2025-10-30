-- 17mov_WindowCleaning - Client (Refactored Pass 1)
-- Mục tiêu: Giữ nguyên hành vi, đổi tên biến/hàm dễ hiểu, gom nhóm logic.
-- Ghi chú: Giữ nguyên event name, NUI message payload, và Config.

-- =========================
-- Trạng thái & Biến toàn cục
-- =========================

local playerData = nil
local myServerId = GetPlayerServerId(PlayerId())

local scriptReady = false         -- thay cho L12_1
local nuiDriverLoaded = false     -- thay cho L19_1
local nuiUiLoaded = false         -- thay cho L20_1
local uiOpen = false              -- thay cho L17_1
local hasInitPayload = false      -- thay cho L10_1

local onDuty = false              -- OnDuty (global trong bản gốc)
local jobVehicleNetId = nil       -- JobVehicleNetId (global trong bản gốc)

-- Callback tạm giữ (thay cho L13_1/L14_1)
local pendingCallbacks = {}
local callbackCounter = 0

-- Blip mục tiêu job (thay cho L21_1)
local targetBlip = -1
local CurrentAction, CurrentActionMsg, CurrentActionStation = nil, nil, nil

-- =========================
-- Tiện ích
-- =========================

local function debugLog(...)
  if Config and Config.Debug ~= nil then
    print(...)
  end
end

local function notify(msg)
  if Notify ~= nil then
    Notify(msg)
  else
    print("[Notify]", msg)
  end
end

-- =========================
-- Cơ chế TriggerServerCallback (giữ nguyên event shape)
-- =========================

function TriggerServerCallback(name, cb, ...)
  callbackCounter = callbackCounter + 1
  pendingCallbacks[name] = pendingCallbacks[name] or {}
  pendingCallbacks[name][callbackCounter] = cb
  debugLog("SENDING REQUEST:", name, callbackCounter)

  local evt = "17mov_Callbacks:GetResponse" .. GetCurrentResourceName()
  TriggerServerEvent(evt, name, callbackCounter, ...)
end

RegisterNetEvent("17mov_Callbacks:receiveData" .. GetCurrentResourceName())
AddEventHandler("17mov_Callbacks:receiveData" .. GetCurrentResourceName(), function(name, id, ...)
  debugLog("ROOT RESPONSE FROM:", name, id)
  if pendingCallbacks[name] and pendingCallbacks[name][id] then
    local cb = pendingCallbacks[name][id]
    cb(...)
    pendingCallbacks[name][id] = nil
    if next(pendingCallbacks[name]) == nil then
      pendingCallbacks[name] = nil
    end
  end
end)

-- =========================
-- NUI: driverLoaded / nuiLoaded / tutorialClosed / menuClosed / dontShowTutorialAgain
-- =========================

RegisterNUICallback("driverLoaded", function()
  nuiDriverLoaded = true
end)

RegisterNUICallback("nuiLoaded", function()
  nuiUiLoaded = true
end)

RegisterNUICallback("tutorialClosed", function()
  SetNuiFocus(false, false)
end)

RegisterNUICallback("menuClosed", function()
  uiOpen = false
  SetNuiFocus(false, false)
end)

RegisterNUICallback("dontShowTutorialAgain", function(data, cb)
  local key = "17mov_Tutorials:Cleaner:" .. (data and (data.key or "") or "")
  SetResourceKvpInt(key, 1)
  if cb then cb(true) end
end)

-- =========================
-- Khởi chạy NUI UI + cấu hình
-- =========================

CreateThread(function()
  -- Chờ driver NUI
  while not nuiDriverLoaded do Citizen.Wait(100) end

  if Config.useModernUI then
    SendNUIMessage({ ui = "new" })
  else
    SendNUIMessage({ ui = "old" })
    nuiUiLoaded = true
    Citizen.Wait(500)
  end

  -- Chờ UI load nếu dùng modern
  while not nuiUiLoaded do Citizen.Wait(100) end

  SendNUIMessage({
    action = "setProgressBarAlign",
    align = Config.ProgressBarAlign,
    offset = Config.ProgressBarOffset,
  })

  if not Config.EnableCloakroom then
    SendNUIMessage({ action = "hideCloakroom" })
  end
end)

-- =========================
-- Blips
-- =========================

local blipsMade = false

local function makeBlips()
  if blipsMade then return end
  blipsMade = true
  for _, def in pairs(Config.Blips) do
    local blip = AddBlipForCoord(def.Pos.x, def.Pos.y, def.Pos.z)
    def.blip = blip
    SetBlipSprite(blip, def.Sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, def.Scale)
    SetBlipColour(blip, def.Color)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(def.Label)
    EndTextCommandSetBlipName(blip)
  end
end

local function deleteBlips()
  blipsMade = false
  for _, def in pairs(Config.Blips) do
    if def.blip then
      RemoveBlip(def.blip)
      def.blip = nil
    end
  end
end

-- =========================
-- Init script + tích hợp ESX/QBCore (giữ event y như cũ)
-- =========================

local function sendInitToUI()
  TriggerServerCallback("17mov_Cleaner:init", function(payload)
    SendNUIMessage({ action = "Init", name = payload.name, myId = payload.source })
    hasInitPayload = true
  end)
end

local function initializeScript(skipDelay)
  -- Chờ NUI sẵn sàng nếu dùng modern
  if Config.useModernUI then
    while not nuiUiLoaded do Citizen.Wait(100) end
  else
    Citizen.Wait(5500)
  end

  -- Lấy playerData ban đầu
  playerData = GetPlayerData and GetPlayerData() or playerData

  if not skipDelay then
    Citizen.Wait(5500)
  end

  scriptReady = true

  -- Blip: theo cấu hình yêu cầu nghề
  local restrict = (Config.RequiredJob ~= "none" and Config.RestrictBlipToRequiredJob)
  if restrict then
    -- Giữ nguyên logic gốc: chờ có job rồi mới quyết định tạo blip
    while not (playerData and playerData.job and playerData.job.name) do
      playerData = GetPlayerData and GetPlayerData() or playerData
      Citizen.Wait(100)
    end
    if playerData.job.name == Config.RequiredJob then
      makeBlips()
    end
  else
    makeBlips()
  end

  sendInitToUI()
end

InitalizeScript = initializeScript -- giữ tên công khai tương thích

-- ESX/QBCore load events
RegisterNetEvent("QBCore:Client:OnPlayerLoaded")
AddEventHandler("QBCore:Client:OnPlayerLoaded", function()
  initializeScript()
end)

RegisterNetEvent("esx:playerLoaded")
AddEventHandler("esx:playerLoaded", function()
  initializeScript()
end)

-- Fallback: tự khởi tạo khi resource start nếu framework event không bắn
AddEventHandler('onClientResourceStart', function(res)
  if res == GetCurrentResourceName() and not scriptReady then
    CreateThread(function()
      Citizen.Wait(500)
      initializeScript(true)
    end)
  end
end)

-- QBCore Job Update
RegisterNetEvent("QBCore:Client:OnJobUpdate")
AddEventHandler("QBCore:Client:OnJobUpdate", function(job)
  playerData = GetPlayerData and GetPlayerData() or playerData

  local shouldRestrict = (Config.RequiredJob ~= "none" and Config.RestrictBlipToRequiredJob)
  if shouldRestrict then
    if playerData and playerData.job and playerData.job.name == Config.RequiredJob then
      makeBlips()
    else
      deleteBlips()
    end
  else
    makeBlips()
  end
end)

-- ESX job set
RegisterNetEvent("esx:setJob")
AddEventHandler("esx:setJob", function(job)
  -- đảm bảo playerData tồn tại
  while not (playerData and playerData.job) do
    playerData = GetPlayerData and GetPlayerData() or playerData
    Citizen.Wait(1000)
  end
  playerData.job = job

  local shouldRestrict = (Config.RequiredJob ~= "none" and Config.RestrictBlipToRequiredJob)
  if shouldRestrict then
    if playerData and playerData.job and playerData.job.name == Config.RequiredJob then
      makeBlips()
    else
      deleteBlips()
    end
  else
    makeBlips()
  end
end)

-- =========================
-- Menu làm việc (OpenDutyMenu)
-- =========================

local function openDutyMenu_modern()
  if not scriptReady then
    print("SCRIPT NOT READY - WAIT UNTIL SCRIPT PROPERLY LOAD")
    initializeScript(true)
    return
  end
  if not hasInitPayload then
    sendInitToUI()
    print("SCRIPT NOT READY - WAIT UNTIL SCRIPT PROPERLY LOAD")
    return
  end

  SendNUIMessage({ action = "OpenWorkMenu" })
  SetNuiFocus(true, true)
  uiOpen = true

  -- Tab người chơi gần (giữ nguyên ý tưởng, tối giản lần 1)
  CreateThread(function()
    while uiOpen do
      local active = GetActivePlayers()
      local myPos = GetEntityCoords(PlayerPedId())
      local nearbyIds = {}

      for _, pid in pairs(active) do
        if pid ~= PlayerId() then
          local ped = GetPlayerPed(pid)
          local p = GetEntityCoords(ped)
          if #(myPos - p) < 10.0 then
            table.insert(nearbyIds, GetPlayerServerId(pid))
          end
        end
      end

      if #nearbyIds > 0 then
        TriggerServerCallback("17mov_Cleaner:GetPlayersNames", function(list)
          -- Hiển thị tab khi có người
          SendNUIMessage({ action = "showNearbyPlayersTab" })
          -- Thêm từng người (đơn giản hóa, UI sẽ tự xử lý add/delete theo hành vi hiện tại)
          for _, it in pairs(list or {}) do
            SendNUIMessage({ action = "addNewNearbyPlayer", id = it.id, name = it.name })
          end
        end, nearbyIds)
      else
        -- Ẩn nếu không có ai
        SendNUIMessage({ action = "hideNearbyPlayersTab" })
      end

      Citizen.Wait(2500)
    end
  end)
end

local function openDutyMenu_classic()
  if not scriptReady then
    initializeScript(true)
    print("SCRIPT NOT READY - WAIT UNTIL SCRIPT PROPERLY LOAD")
    return
  end
  if not hasInitPayload then
    sendInitToUI()
    print("SCRIPT NOT READY - WAIT UNTIL SCRIPT PROPERLY LOAD")
    return
  end

  TriggerServerCallback("17mov_Cleaner:IfPlayerIsHost", function(isHost)
    SendNUIMessage({ action = "HostStatusUpdate", status = isHost })
    SendNUIMessage({ action = "OpenWorkMenu" })
    SetNuiFocus(true, true)
  end)
end

function OpenDutyMenu()
  if Config.useModernUI then
    openDutyMenu_modern()
  else
    openDutyMenu_classic()
  end
end

-- =========================
-- Keybind: mở/đóng tương tác marker (giữ tên lệnh như bản gốc)
-- =========================

RegisterCommand("+WindowCleanerStartMarkerAction", function() end, false)
RegisterCommand("-WindowCleanerStartMarkerAction", function()
  if CurrentAction ~= nil then
    if CurrentAction == "open_dutyToggle" then
      OpenDutyMenu()
    elseif CurrentAction == "finish_job" then
      TriggerServerCallback("17mov_Cleaner:IfPlayerIsHost", function(isHost)
        if isHost then
          if EndJob then EndJob() end
        else
          notify(Config.Lang.no_permission)
        end
      end)
    end
  end
end, false)

TriggerEvent("chat:removeSuggestion", "/+WindowCleanerStartMarkerAction")
TriggerEvent("chat:removeSuggestion", "/-WindowCleanerStartMarkerAction")
RegisterKeyMapping("+WindowCleanerStartMarkerAction", Config.Lang.keybind, "keyboard", "E")

-- =========================
-- Blip mục tiêu nhiệm vụ (CreateTargetBlip) – giữ event/payload
-- =========================

function CreateTargetBlip(x, y, z)
  if DoesBlipExist(targetBlip) then
    RemoveBlip(targetBlip)
  end
  targetBlip = AddBlipForCoord(x, y, z or 0.0)
  SetBlipSprite(targetBlip, 1)
  SetBlipDisplay(targetBlip, 6)
  SetBlipScale(targetBlip, 1.0)
  SetBlipColour(targetBlip, 83)
  SetBlipAsShortRange(targetBlip, true)
  BeginTextCommandSetBlipName("STRING")
  AddTextComponentString((Config.Lang and Config.Lang.targetLocation) or "Target Location")
  EndTextCommandSetBlipName(targetBlip)
end

-- =========================
-- Pass 2: Vòng đời Job, Spawn xe, Teleport, một phần lobby và cleaning tối thiểu
-- =========================

-- Trạng thái Job/Session
local currentJobIndex = -1      -- thay cho L2_1
local currentWindowIndex = -1   -- thay cho L8_1

-- UI counter
local function uiShowCounter()
  SendNUIMessage({ action = "showCounter" })
end

local function uiHideCounter()
  SendNUIMessage({ action = "hideCounter" })
  SendNUIMessage({ action = "updateCounter", value = 0 })
end

-- Event: cập nhật % host chia thưởng
RegisterNetEvent("17mov_Cleaner:UpdateHostPercentages")
AddEventHandler("17mov_Cleaner:UpdateHostPercentages", function(val)
  SendNUIMessage({ action = "updateHostRewards", value = val })
end)

-- Event: cập nhật reward của tôi
RegisterNetEvent("17mov_Cleaner:SetMyReward")
AddEventHandler("17mov_Cleaner:SetMyReward", function(reward)
  SendNUIMessage({ action = "updateMyReward", reward = reward })
end)

-- Clear lobby: nhận Init payload lại
RegisterNetEvent("17mov_Cleaner:clearMyLobby")
AddEventHandler("17mov_Cleaner:clearMyLobby", function()
  TriggerServerCallback("17mov_Cleaner:init", function(payload)
    SendNUIMessage({ action = "Init", name = payload.name, myId = payload.source })
    hasInitPayload = true
  end)
end)

-- =========================
-- NUI: thay đồ (tối giản – phụ thuộc hàm ChangeClothes của core nếu có)
-- =========================

local wearingWorkClothes = false

RegisterNUICallback("changeClothes", function(data)
  if not data or not data.type then return end
  if data.type == "work" then
    wearingWorkClothes = true
    if ChangeClothes then ChangeClothes("work") end
  else
    wearingWorkClothes = false
    if ChangeClothes then ChangeClothes("citizen") end
  end
end)

-- =========================
-- NUI: lấy người chơi gần, gửi request, kick khỏi lobby
-- =========================

RegisterNUICallback("GetClosestPlayers", function(data, cb)
  local active = GetActivePlayers()
  local myPos = GetEntityCoords(PlayerPedId())
  local nearbyIds = {}
  for _, pid in pairs(active) do
    if pid ~= PlayerId() then
      local ped = GetPlayerPed(pid)
      local p = GetEntityCoords(ped)
      if #(myPos - p) < 20.0 then
        table.insert(nearbyIds, GetPlayerServerId(pid))
      end
    end
  end

  TriggerServerCallback("17mov_Cleaner:IfPlayerIsHost", function(isHost)
    if isHost then
      TriggerServerCallback("17mov_Cleaner:GetPlayersNames", function(list)
        if cb then cb(list) end
        if (list and #list == 0) then
          notify(Config.Lang.nobodyNearby)
        end
      end, nearbyIds)
    else
      notify(Config.Lang.no_permission)
    end
  end)
end)

RegisterNUICallback("requestReacted", function(data)
  local ok = data and data.boolean or false
  TriggerServerEvent("17mov_Cleaner:ClientReactRequest", ok)
  SetNuiFocus(false, false)
end)

if Config.useModernUI then
  RegisterNUICallback("sendRequest", function(data)
    if onDuty then
      notify(Config.Lang.cantInvite)
      return
    end
    local id = tonumber(data and data.id)
    if id then
      TriggerServerEvent("17mov_Cleaner:SendRequestToClient_sv", id)
    end
  end)

  RegisterNUICallback("kickPlayerFromLobby", function(data)
    local id = tonumber(data and data.id)
    if not id then return end
    if data and data.name then
      notify(string.format(Config.Lang.kicked, data.name))
    elseif Config.Lang.kicked_generic then
      notify(string.format(Config.Lang.kicked_generic, tostring(id)))
    else
      notify("Kicked " .. tostring(id))
    end
    TriggerServerEvent("17mov_Cleaner:KickPlayerFromLobby", id, true)
  end)
else
  RegisterNUICallback("sendRequest", function(data)
    if onDuty then
      notify(Config.Lang.cantInvite)
      return
    end
    TriggerServerEvent("17mov_Cleaner:SendRequestToClient_sv", data.id)
  end)

  RegisterNUICallback("kickPlayerFromLobby", function(data)
    notify(string.format(Config.Lang.kicked, data.name))
    TriggerServerEvent("17mov_Cleaner:KickPlayerFromLobby", data.id, true)
  end)
end

RegisterNUICallback("focusOff", function()
  SetNuiFocus(false, false)
end)

RegisterNUICallback("notify", function(data)
  if data and data.msg then notify(data.msg) end
end)

RegisterNetEvent("17mov_Cleaner:SendRequestToClient_cl")
AddEventHandler("17mov_Cleaner:SendRequestToClient_cl", function(name)
  SendNUIMessage({ action = "ShowInviteBox", name = name })
  SetNuiFocus(true, true)
end)

-- =========================
-- SpawnPoint clear check
-- =========================

function IsSpawnPointClear()
  local sp = vec3(Config.SpawnPoint.x, Config.SpawnPoint.y, Config.SpawnPoint.z)
  local list = GetGamePool("CVehicle")
  if type(list) ~= "table" then
    debugLog("FAILED TO FETCH GAMEPOOL - Returning CLEAR")
    return true
  end
  for _, veh in pairs(list) do
    local d = #(GetEntityCoords(veh) - sp)
    if d < 6.0 then return false end
  end
  return true
end

-- =========================
-- Bắt đầu công việc (NUI)
-- =========================

RegisterNUICallback("startJob", function()
  if not onDuty then
    if IsSpawnPointClear() then
      TriggerServerEvent("17mov_Cleaner:StartJob_sv")
    else
      notify(Config.Lang.spawnpointOccupied)
    end
  else
    notify(Config.Lang.alreadyWorking)
  end
end)

-- Rời lobby
RegisterNUICallback("leaveLobby", function(data)
  if onDuty then
    notify(Config.Lang.cantLeaveLobby)
    return
  end
  local id = tonumber(data and data.id)
  local me = GetPlayerServerId(PlayerId())
  TriggerServerEvent("17mov_Cleaner:KickPlayerFromLobby", id, false, me)
  notify(Config.Lang.quit)
end)

-- =========================
-- Spawn xe Job
-- =========================

local function setVehicleForPlayer(veh)
  if SetVehicle then
    SetVehicle(veh)
  end
end

function SpawnVehicle(modelHash, at)
  local tries = 100
  RequestModel(modelHash)
  while not HasModelLoaded(modelHash) and tries > 0 do
    Citizen.Wait(100)
    tries = tries - 1
    RequestModel(modelHash)
  end
  local veh = CreateVehicle(modelHash, at.x, at.y, at.z, at.w or 0.0, true, false)
  SetEntityAsMissionEntity(veh, true, true)
  SetVehicleNeedsToBeHotwired(veh, false)
  SetVehRadioStation(veh, "OFF")
  SetVehicleFuelLevel(veh, 100.0)
  if Config.EnableVehicleTeleporting then
    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
  end
  setVehicleForPlayer(veh)
  return veh
end

-- =========================
-- Bắt đầu Job (client event từ server)
-- =========================

RegisterNetEvent("17mov_Cleaner:StartJob_cl")
AddEventHandler("17mov_Cleaner:StartJob_cl", function(hostId, myId, lobbyHasVehicle, isJoining)
  local sp = Config.SpawnPoint
  onDuty = true

  -- Tự động mặc đồ nếu yêu cầu và chưa mặc
  if Config.RequireWorkClothes and not wearingWorkClothes and ChangeClothes then
    wearingWorkClothes = true
    ChangeClothes("work")
  end

  if hostId == myId then
    -- Chủ lobby tạo xe nếu chưa có
    if Config.EnableVehicleTeleporting and not isJoining then
      DoScreenFadeOut(300)
      Citizen.Wait(1000)
    end
    if not isJoining then
      local veh = SpawnVehicle(Config.JobVehicleModel, sp)
      Citizen.Wait(500)
      DoScreenFadeIn(300)
      jobVehicleNetId = VehToNet(veh)
      TriggerServerEvent("17mov_Cleaner:UploadVehicleNetId", jobVehicleNetId)
    end
  else
    -- Thành viên: tìm net id từ server
    if isJoining then
      local resolved = false
      while not resolved do
        Citizen.Wait(300)
        TriggerServerCallback("17mov_Cleaner:GetLobbyVehicleId", function(net)
          if net and net ~= 0 then
            local v = NetToVeh(net)
            if v and v ~= 0 and DoesEntityExist(v) then
              jobVehicleNetId = net
              resolved = true
            end
          end
        end, hostId)
      end
    end
  end

  uiShowCounter()
end)

-- =========================
-- Nhận job mục tiêu (điểm bắt đầu tại enterCoords)
-- =========================

RegisterNetEvent("17mov_Cleaner:takeNewJob")
AddEventHandler("17mov_Cleaner:takeNewJob", function(jobIndex)
  currentJobIndex = jobIndex
  local enter = Config.JobLocations[jobIndex].enterCoords
  SetNewWaypoint(enter.x, enter.y)
  CreateTargetBlip(enter.x, enter.y, enter.z)

  CreateThread(function()
    while onDuty and currentJobIndex == jobIndex do
      Citizen.Wait(0)
      local pos = GetEntityCoords(PlayerPedId())
      local dist = #(pos - enter)
      if dist <= 15.0 then
        if DrawText3Ds then
          DrawText3Ds(enter.x, enter.y, enter.z, "~r~[E] | ~s~" .. Config.Lang.enterPlatform)
        end
        if dist <= 1.5 and IsControlJustReleased(0, 38) then
          TriggerServerCallback("17mov_Cleaner:IfPlayerIsHost", function(isHost)
            if isHost then
              debugLog("starting:", jobIndex)
              TriggerServerEvent("17mov_Cleaner:StartSession", jobIndex)
            else
              notify(Config.Lang.no_permission)
            end
          end)
        end
      else
        Citizen.Wait(500)
      end
    end
  end)
end)

-- =========================
-- Teleport tới platform (điểm làm việc trên cao) – rút gọn lần 1
-- =========================

RegisterNetEvent("17mov_Cleaner:TeleportToPlatform")
AddEventHandler("17mov_Cleaner:TeleportToPlatform", function(a, b, jobIndex)
  -- a,b là tham số sync gốc (hostId/myId), không dùng ở bản rút gọn này
  local enter = Config.JobLocations[jobIndex].enterCoords
  local mePos = GetEntityCoords(PlayerPedId())
  if #(mePos - enter) > 100.0 then return end

  DoScreenFadeOut(250)
  -- Teleport tới exitCoords (điểm trên cao) và đảm bảo hamper spawn
  local exit = Config.JobLocations[jobIndex].exitCoords
  -- Spawn hamper trước khi hiện
  local isHost = (a == b)
  SpawnHamper(Config.JobLocations[jobIndex], a, isHost)
  SetEntityCoords(PlayerPedId(), exit.x, exit.y, exit.z, false, false, false, false)
  FreezeEntityPosition(PlayerPedId(), true)
  Citizen.Wait(2500)
  DoScreenFadeIn(250)
  FreezeEntityPosition(PlayerPedId(), false)

  -- Hiển thị tutorial 2 nếu cần (rút gọn)
  local tKey = "17mov_Tutorials:Cleaner:cleanerSecondTutorial"
  local seen = GetResourceKvpInt(tKey)
  if seen == 0 then
    SendNUIMessage({ action = "show2Tutorial" })
    SendNUIMessage({ action = "showTutorial", customText = Config.Lang.tutorial2 })
    SetNuiFocus(true, true)
  end

  -- Bắt đầu quét cửa sổ dơ để vệ sinh
  CreateThread(function()
    while onDuty and currentJobIndex == jobIndex do
      Citizen.Wait(0)
      local pos = GetEntityCoords(PlayerPedId())
      local nearest = { id = 0, dist = 9999.0 }
      local anyDirty = false
      for id, w in pairs(Config.JobLocations[jobIndex].windowsLocations or {}) do
        if w.dirty then
          anyDirty = true
          local d = #(pos - w.coords)
          if d < nearest.dist then
            nearest.id = id
            nearest.dist = d
          end
          local m = Config.WindowMarkerSetting
          if d < 30.0 and d > 1.0 then
            DrawMarker(m.type, w.coords.x, w.coords.y, w.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
              m.scale[1], m.scale[2], m.scale[3], m.unActiveColor[1], m.unActiveColor[2], m.unActiveColor[3], m.unActiveColor[4],
              false, true, 2, false, false, false, false)
          elseif d <= 1.0 then
            DrawMarker(m.type, w.coords.x, w.coords.y, w.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
              m.scale[1], m.scale[2], m.scale[3], m.acviteColor[1], m.acviteColor[2], m.acviteColor[3], m.acviteColor[4],
              false, true, 2, false, false, false, false)
            if ShowHelpNotification then
              ShowHelpNotification(Config.Lang.cleanWindowInfo)
            end
            if IsControlJustReleased(0, 38) then
              StartCleaning(id)
              Citizen.Wait(100)
            end
          end
        end
      end
      if not anyDirty then
        TriggerServerEvent("17mov_Cleaner:exitSession", jobIndex, false, false, true)
        break
      end
    end
  end)
end)

-- =========================
-- Cleaning: bắt đầu/đổi trạng thái cửa sổ
-- =========================

local lastCleaningRequestId = nil

function StartCleaning(windowId)
  if lastCleaningRequestId == windowId then
    debugLog("REJECTING")
    return
  end
  lastCleaningRequestId = windowId
  debugLog("STARTING CLEANING ID:", windowId)

  TriggerServerCallback("17mov_cleaner:isThisWindowisFree", function(ok)
    debugLog("CALLBACK RESPONSE:", ok)
    if ok then
      currentWindowIndex = windowId
      SendNUIMessage({ action = "startCleaning" })
      SetNuiFocus(true, true)
      TaskStartScenarioInPlace(PlayerPedId(), "WORLD_HUMAN_MAID_CLEAN", 0, true)

      -- Xóa bàn chải nếu tồn tại (679927467)
      local objs = GetGamePool("CObject")
      if type(objs) == "table" then
        for _, o in pairs(objs) do
          if o and GetEntityModel(o) == 679927467 then
            SetEntityAsMissionEntity(o, true, true)
            DeleteObject(o)
            DeleteEntity(o)
          end
        end
      end
    else
      notify(Config.Lang.someoneIsAlreadyCleaning)
    end
    Citizen.CreateThread(function()
      Citizen.Wait(1500)
      lastCleaningRequestId = nil
    end)
  end, windowId)
end

RegisterNUICallback("stopCleaning", function()
  TriggerServerEvent("17mov_Cleaner:enableThisWindow", currentWindowIndex)
  -- Dừng anim + dọn prop
  SetNuiFocus(false, false)
  ClearPedTasksImmediately(PlayerPedId())
  local objs = GetGamePool("CObject")
  if type(objs) == "table" then
    for _, o in pairs(objs) do
      if o and GetEntityModel(o) == 679927467 then
        SetEntityAsMissionEntity(o, true, true)
        DeleteObject(o)
        DeleteEntity(o)
      end
    end
  end
end)

RegisterNUICallback("endCleaning", function()
  -- Dừng anim
  SetNuiFocus(false, false)
  ClearPedTasksImmediately(PlayerPedId())
  TriggerServerEvent("17mov_cleaner:ThisWindowReady", currentJobIndex, currentWindowIndex)
  currentWindowIndex = -1
end)

RegisterNetEvent("17mov_Cleaner:disableWindow")
AddEventHandler("17mov_Cleaner:disableWindow", function(windowId, counterVal)
  SendNUIMessage({ action = "updateCounter", value = counterVal })
  -- Xóa bàn chải (nếu còn)
  local objs = GetGamePool("CObject")
  if type(objs) == "table" then
    for _, o in pairs(objs) do
      if o and GetEntityModel(o) == 679927467 then
        SetEntityAsMissionEntity(o, true, true)
        DeleteObject(o)
        DeleteEntity(o)
      end
    end
  end
end)

-- =========================
-- Rời platform và chuyển hướng về điểm kết thúc job
-- =========================

RegisterNetEvent("17mov_Cleaner:exitPlatform")
AddEventHandler("17mov_Cleaner:exitPlatform", function(a, hostId, jobIndexFrom, jobIndexTo)
  -- Rời platform -> về enterCoords của jobIndexTo và set blip FinishJob
  DoScreenFadeOut(50)
  Citizen.Wait(250)
  local enter = Config.JobLocations[jobIndexTo].enterCoords
  SetEntityCoords(PlayerPedId(), enter.x, enter.y, enter.z, false, false, false, false)
  FreezeEntityPosition(PlayerPedId(), true)
  Citizen.Wait(2500)
  DoScreenFadeIn(250)
  FreezeEntityPosition(PlayerPedId(), false)
  Citizen.Wait(250)

  local finish = Config.Locations.FinishJob.Coords[1]
  SetNewWaypoint(finish.x, finish.y)
  CreateTargetBlip(finish.x, finish.y, finish.z)
end)

-- =========================
-- Kết thúc Job (client) + xác nhận xóa xe
-- =========================

local endJobGuard = true

function EndJob()
  if not endJobGuard then return end
  endJobGuard = false

  local driver = GetPedInVehicleSeat(GetVehiclePedIsIn(PlayerPedId(), false), -1)
  if driver ~= PlayerPedId() then
    if IsPedInAnyVehicle(PlayerPedId(), false) then
      notify(Config.Lang.notADriver)
      endJobGuard = true
      return
    end
  end

  local veh = GetVehiclePedIsIn(PlayerPedId(), false)
  local mdl = GetEntityModel(veh)
  if mdl == GetHashKey(Config.JobVehicleModel) then
    if DeleteVehicleByCore then
      DeleteVehicleByCore(veh)
    else
      DeleteEntity(veh)
    end
    TriggerServerEvent("17mov_Cleaner:endJob_sv", true)
    endJobGuard = true
    return
  end

  -- Không đúng xe -> cảnh báo
  SetNuiFocus(true, true)
  SendNUIMessage({ action = "openWarning" })
  endJobGuard = true
end

RegisterNetEvent("17mov_Cleaner:endJob_cl")
AddEventHandler("17mov_Cleaner:endJob_cl", function()
  if RemoveKeys then RemoveKeys() end

  -- Nếu gần DutyToggle và enable teleport: dịch chuyển nhẹ cho mượt (rút gọn)
  local myPos = GetEntityCoords(PlayerPedId())
  local duty = Config.Locations.DutyToggle.Coords[1]
  if #(myPos - duty) < 40.0 and Config.EnableVehicleTeleporting then
    DoScreenFadeOut(250)
    Citizen.Wait(1000)
    SetEntityCoords(PlayerPedId(), duty.x, duty.y, duty.z, false, false, false, false)
  end

  if Config.RequireWorkClothes and not Config.EnableCloakroom and ChangeClothes then
    wearingWorkClothes = false
    ChangeClothes("citizen")
  end

  Citizen.Wait(1000)
  DoScreenFadeIn(300)
  uiHideCounter()

  -- Reset trạng thái
  if currentJobIndex ~= -1 then
    for _, w in pairs(Config.JobLocations[currentJobIndex].windowsLocations or {}) do
      w.dirty = true
    end
  end
  currentWindowIndex = -1
  currentJobIndex = -1
  onDuty = false

  if DoesBlipExist(targetBlip) then RemoveBlip(targetBlip) end
end)

RegisterNUICallback("acceptWarning", function()
  TriggerServerEvent("17mov_Cleaner:endJob_sv", false)
  if Config.DeleteVehicleWithPenalty then
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if DeleteVehicleByCore then
      DeleteVehicleByCore(veh)
    else
      DeleteEntity(veh)
    end
  end
end)

-- =========================
-- Pass 3: Markers (Duty/Finish) và Hamper (giàn treo + dây)
-- =========================

-- Hỗ trợ: show help nếu core không có
local function showHelp(msg)
  if ShowHelpNotification then
    ShowHelpNotification(msg)
  else
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, false, 1)
  end
end

-- Markers loop rút gọn theo Config.Locations
local markersRunning = false
local lastMarkerKey = nil

local function runMarkersLoop()
  if markersRunning then return end
  markersRunning = true
  CreateThread(function()
    while markersRunning do
      Citizen.Wait(0)
      local pos = GetEntityCoords(PlayerPedId())
      local slowDown = true
      for key, def in pairs(Config.Locations or {}) do
        for _, c in pairs(def.Coords or {}) do
          local d = #(pos - c)
          if d < 20.0 then
            slowDown = false
            local scale = def.scale
            local inside = (d < (scale and scale.x or 1.5))
            local clr = inside and Config.MarkerSettings.Active or Config.MarkerSettings.UnActive
            DrawMarker(6, c.x, c.y, c.z - 1.0, 0.0, 0.0, 0.0, -90.0, 0.0, 0.0,
              scale and scale.x or 1.5, scale and scale.y or 1.5, scale and scale.z or 1.0,
              clr.r, clr.g, clr.b, clr.a, false, false, 2, false, false, false, false)

            if inside then
              CurrentActionStation = key
              CurrentAction = def.CurrentAction
              CurrentActionMsg = def.CurrentActionMsg
              showHelp(CurrentActionMsg)
            elseif lastMarkerKey == key then
              CurrentActionStation = nil
              CurrentAction = nil
              CurrentActionMsg = nil
            end
            lastMarkerKey = key
          end
        end
      end
      if slowDown then Citizen.Wait(400) end
    end
  end)
end

-- Bắt đầu markers sau khi init
CreateThread(function()
  while not scriptReady do Citizen.Wait(250) end
  -- Xét ràng buộc nghề nếu có
  if Config.RequiredJob ~= "none" then
    if Config.RestrictBlipToRequiredJob then
      while not (playerData and playerData.job) do
        playerData = GetPlayerData and GetPlayerData() or playerData
        Citizen.Wait(250)
      end
      if playerData.job.name == Config.RequiredJob then
        runMarkersLoop()
      end
    else
      runMarkersLoop()
    end
  else
    runMarkersLoop()
  end
end)

-- Hamper state
local hamper = { active = false, handle = nil, platform = nil, ropes = {}, cfg = nil, moveUp = false, moveDown = false }

local function ropeLoad()
  if RopeLoadTextures then RopeLoadTextures() end
end

local function attachRopes()
  if not (hamper.handle and hamper.platform) then return end
  ropeLoad()
  -- Hai điểm gắn dây (theo bản gốc)
  local pairsOff = {
    { handle = vector3(4.84, 2.96, 3.42), hamper = vector3(4.87, 0.012, 1.4) },
    { handle = vector3(-4.84, 2.96, 3.42), hamper = vector3(-4.87, 0.012, 1.4) },
  }
  for i = 1, #pairsOff do
    local a = GetOffsetFromEntityInWorldCoords(hamper.handle, pairsOff[i].handle.x, pairsOff[i].handle.y, pairsOff[i].handle.z)
    local b = GetOffsetFromEntityInWorldCoords(hamper.platform, pairsOff[i].hamper.x, pairsOff[i].hamper.y, pairsOff[i].hamper.z)
    local rope = AddRope(b.x, b.y, b.z, 0.0, 0.0, 0.0, 0.3, 4, 0.5, 0.5, 100.0, false, false, false, 0.0, false)
    AttachEntitiesToRope(rope, hamper.handle, hamper.platform, a.x, a.y, a.z, b.x, b.y, b.z, 0.5, true, true, 0, 0)
    table.insert(hamper.ropes, rope)
  end
end

function DeleteHamper()
  if hamper.platform then DeleteObject(hamper.platform) hamper.platform = nil end
  if hamper.handle then DeleteObject(hamper.handle) hamper.handle = nil end
  for _, r in ipairs(hamper.ropes) do
    if r then DeleteRope(r) end
  end
  hamper.ropes = {}
  hamper.active = false
  hamper.moveUp = false
  hamper.moveDown = false
end

function SpawnHamper(jobCfg, hostId, isHost)
  hamper.cfg = jobCfg
  -- Load models
  while not HasModelLoaded(jobCfg.hamperModel) do RequestModel(jobCfg.hamperModel) Citizen.Wait(10) end
  while not HasModelLoaded(jobCfg.handleModel) do RequestModel(jobCfg.handleModel) Citizen.Wait(10) end

  -- Handle
  local h = CreateObject(jobCfg.handleModel, jobCfg.handleCoords.x, jobCfg.handleCoords.y, jobCfg.handleCoords.z, false, true, false)
  SetEntityRotation(h, jobCfg.handleRotation.x, jobCfg.handleRotation.y, jobCfg.handleRotation.z, 0, true)
  FreezeEntityPosition(h, true)

  -- Platform
  local fwd = GetEntityForwardVector(h) * (jobCfg.hamperForwardOffsetFromHandle or 0.0)
  local base = jobCfg.hamperMaxZ
  local px, py, pz = jobCfg.handleCoords.x + fwd.x, jobCfg.handleCoords.y + fwd.y, base
  local p = CreateObjectNoOffset(jobCfg.hamperModel, px, py, pz, false, true, false)
  SetEntityRotation(p, jobCfg.handleRotation.x, jobCfg.handleRotation.y, jobCfg.handleRotation.z, 0, true)
  FreezeEntityPosition(p, true)

  hamper.handle = h
  hamper.platform = p
  hamper.active = true

  attachRopes()

  -- Nếu host: khởi động điều khiển gửi sự kiện
  if isHost then
    TriggerEvent("17mov_Cleaner:StartHostPlatformCode")
  end
end

-- Chủ lobby: điều khiển hamper bằng phím, phát tán event server
RegisterNetEvent("17mov_Cleaner:StartHostPlatformCode")
AddEventHandler("17mov_Cleaner:StartHostPlatformCode", function()
  if not hamper.active then return end
  notify(Config.Lang.youCanControl)
  CreateThread(function()
    local lastTop, lastBot = 0, 0
    while hamper.active do
      Citizen.Wait(0)
      if IsControlPressed(0, Config.HamperGoUpControl) then
        local now = GetGameTimer()
        if now - lastTop > 150 then
          TriggerServerEvent("17mov_cleaner:StartHamperTop")
          lastTop = now
        end
      elseif hamper.moveUp then
        TriggerServerEvent("17mov_cleaner:StopHamperTop", GetEntityCoords(hamper.platform))
      end

      if IsControlPressed(0, Config.HamperGoDownControl) then
        local now = GetGameTimer()
        if now - lastBot > 150 then
          TriggerServerEvent("17mov_cleaner:StartHamperBottom")
          lastBot = now
        end
      elseif hamper.moveDown then
        TriggerServerEvent("17mov_cleaner:StopHamperBottom", GetEntityCoords(hamper.platform))
      end
    end
  end)
end)

-- Di chuyển hamper tại client (nhận broadcast)
local function moveHamperTick()
  CreateThread(function()
    while hamper.active and (hamper.moveUp or hamper.moveDown) do
      Citizen.Wait(0)
      if not hamper.platform or not hamper.cfg then break end
      local pos = GetEntityCoords(hamper.platform)
      local z = pos.z
      local step = 0.01
      if hamper.moveUp then
        local nz = z + step
        if nz < hamper.cfg.hamperMaxZ and nz > hamper.cfg.hamperMinZ then
          SetEntityCoords(hamper.platform, pos.x, pos.y, nz, false, false, false, false)
        end
      elseif hamper.moveDown then
        local nz = z - step
        if nz < hamper.cfg.hamperMaxZ and nz > hamper.cfg.hamperMinZ then
          SetEntityCoords(hamper.platform, pos.x, pos.y, nz, false, false, false, false)
        end
      end
    end
  end)
end

RegisterNetEvent("17mov_cleaner:startHamperTop")
AddEventHandler("17mov_cleaner:startHamperTop", function()
  if not hamper.active then return end
  hamper.moveUp = true
  hamper.moveDown = false
  moveHamperTick()
end)

RegisterNetEvent("17mov_cleaner:stopHamperTop")
AddEventHandler("17mov_cleaner:stopHamperTop", function(at)
  hamper.moveUp = false
  if hamper.platform and at and at.z then
    local pos = GetEntityCoords(hamper.platform)
    -- Mượt tới toạ độ cuối cùng
    while math.abs((at.z or pos.z) - pos.z) > 0.005 do
      Citizen.Wait(0)
      pos = GetEntityCoords(hamper.platform)
      local dir = (at.z > pos.z) and 0.01 or -0.01
      SetEntityCoords(hamper.platform, pos.x, pos.y, pos.z + dir, false, false, false, false)
    end
  end
end)

RegisterNetEvent("17mov_cleaner:startHamperBottom")
AddEventHandler("17mov_cleaner:startHamperBottom", function()
  if not hamper.active then return end
  hamper.moveDown = true
  hamper.moveUp = false
  moveHamperTick()
end)

RegisterNetEvent("17mov_cleaner:stopHamperBottom")
AddEventHandler("17mov_cleaner:stopHamperBottom", function(at)
  hamper.moveDown = false
  if hamper.platform and at and at.z then
    local pos = GetEntityCoords(hamper.platform)
    while math.abs((at.z or pos.z) - pos.z) > 0.005 do
      Citizen.Wait(0)
      pos = GetEntityCoords(hamper.platform)
      local dir = (at.z > pos.z) and 0.01 or -0.01
      SetEntityCoords(hamper.platform, pos.x, pos.y, pos.z + dir, false, false, false, false)
    end
  end
end)


-- =========================
