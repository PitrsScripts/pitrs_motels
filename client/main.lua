local kvpname = GetCurrentServerEndpoint()..'_inshells'


RegisterNetEvent('pitrs_motels:invoice')
AddEventHandler('pitrs_motels:invoice', function(data)
	local motels = GlobalState.Motels
    local buy = lib.alertDialog({
		header = 'Faktura',
		content = '![motel](nui://pitrs_motels/data/image/'..data.motel..'.png) \n ## INFO \n **Popis:** '..data.description..'  \n  **Částka:** $ '..data.amount..'  \n **Způsob platby:** '..data.payment,
		centered = true,
		labels = {
			cancel = 'Zavřít',
			confirm = 'Zaplatit'
		},
		cancel = true
	})
	if buy ~= 'cancel' then
		local success = lib.callback.await('pitrs_motels:payinvoice',false,data)
		if success then
			Notify('Faktura byla úspěšně zaplacena','success')
		else
			Notify('Chyba při platbě faktury','error')
		end
	end
end)


DoesPlayerHaveAccess = function(data)
    for identifier, _ in pairs(data) do
        if identifier == PlayerData?.identifier then return true end
    end
    return false
end

DoesPlayerHaveKey = function(data,room)
	local items = GetInventoryItems('keys')
	if not items then return false end
	for k,v in pairs(items) do
		if v.metadata?.type == data.motel and v.metadata?.serial == data.index then
			return v.metadata?.owner and room?.players[v.metadata?.owner] or false
		end
	end
	return false
end

GetPlayerKeys = function(data,room)
	local items = GetInventoryItems('keys')
	if not items then return false end
	local keys = {}
	for k,v in pairs(items) do
		if v.metadata?.type == data.motel and v.metadata?.serial == data.index then
			local key = v.metadata?.owner and room?.players[v.metadata?.owner]
			if key then
				keys[v.metadata.owner] = key.name
			end
		end
	end
	return keys
end

SetDoorState = function(data)
	local motels = GlobalState.Motels or {}
	local doorindex = data.index + (joaat(data.motel))
	DoorSystemSetDoorState(doorindex, 1)
end

RegisterNetEvent('pitrs_motels:Door', function(data)
	if not data.Mlo then return end
	local doorindex = data.index + (joaat(data.motel))
	DoorSystemSetDoorState(doorindex, DoorSystemGetDoorState(doorindex) == 0 and 1 or 0, false, false)
end)


Door = function(data)
    local dist = #(data.coord - GetEntityCoords(cache.ped)) < 2
    if not dist then 
        return Notify('Jste příliš daleko pro interakci s dveřmi.', 'error') 
    end

    local motel = GlobalState.Motels[data.motel]
    local moteldoor = motel and motel.rooms[data.index]

    if not DoesPlayerHaveKey(data, moteldoor) then
        return Notify('Nemáte klíč pro odemčení těchto dveří.', 'error')
    end

    lib.RequestAnimDict('mp_doorbell')
    TaskPlayAnim(PlayerPedId(), "mp_doorbell", "open_door", 1.0, 1.0, 1000, 1, 1, 0, 0, 0)

    local doorState = moteldoor.lock
    moteldoor.lock = not doorState 

    if moteldoor.lock then
        CloseDoor(data) 
    end
    TriggerServerEvent('pitrs_motels:Door', {
        motel = data.motel,
        index = data.index,
        coord = data.coord,
        Mlo = data.Mlo,
        newState = moteldoor.lock 
    })
    local text = doorState and 'Odemkl jste dveře motelu' or 'Zamkl jste dveře motelu'
    Wait(1000)
    local soundData = {
        file = 'door',
        volume = 0.5
    }
    SendNUIMessage({
        type = "playsound",
        content = soundData
    })
    Notify(text, 'inform')
end

function CloseDoor(data)
    print("Zavírám dveře pro motel: " .. data.motel .. ", Pokoj: " .. data.index)
end



isRentExpired = function(data)
	local motels = GlobalState.Motels[data.motel]
	local room = motels?.rooms[data.index] or {}
	local player = room?.players[PlayerData.identifier] or {}
	return player?.duration and player?.duration < GlobalState.MotelTimer
end

RoomFunction = function(data,identifier)
    if isRentExpired(data) then
        return Notify('Vaše nájemné vypršelo. \n Pro přístup zaplaťte.')
    end
    if data.type == 'door' then
        return Door(data)
    elseif data.type == 'stash' then
        local stashid = identifier or data.uniquestash and PlayerData.identifier or 'room'
        return OpenStash(data,stashid)
    elseif data.type == 'wardrobe' then
        return config.wardrobes[config.wardrobe]()
    elseif config.extrafunction[data.type] then
        local stashid = identifier or data.uniquestash and PlayerData.identifier or 'room'
        return config.extrafunction[data.type](data,stashid)
    end
end


Notify = function(msg,type)
	lib.notify({
		description = msg,
		type = type or 'inform'
	})
end

MyRoomMenu = function(data)
    if not data then
        print("Chyba: data je nil")
        return
    end

    local motels = GlobalState.Motels
    if not motels[data.motel] then
        print("Chyba: Motel nenalezen v GlobalState")
        return
    end

    local rate = motels[data.motel].hour_rate or data.rate

    local options = {
        {
            title = 'Můj pokoj ['..data.index..'] - Zaplatit nájem',
            description = 'Zaplaťte svůj nájem včas '..data.index..' \n Délka nájmu: '..data.duration..' \n '..data.rental_period..' Cena: $ '..rate,
            icon = 'money-bill-wave-alt',
            onSelect = function()
                local input = lib.inputDialog('Zaplacení nebo vklad do motelu', {
                    {type = 'number', label = 'Částka k vkladu', description = '$ '..rate..' za '..data.rental_period..'  \n  Platební metoda: '..data.payment, icon = 'money', default = rate},
                })
                if not input then return end
                local success = lib.callback.await('pitrs_motels:payrent', false, {
                    payment = data.payment,
                    index = data.index,
                    motel = data.motel,
                    amount = input[1],
                    rate = rate,
                    rental_period = data.rental_period
                })
                if success then
                    Notify('Nájem byl úspěšně zaplacen', 'success')
                else
                    Notify('Chyba při placení nájmu', 'error')
                end
            end,
            arrow = true,
        },
        {
            title = 'Vytvořit klíčový předmět',
            description = 'Požádejte o klíč k dveřím',
            icon = 'key',
            onSelect = function()
                local success = lib.callback.await('pitrs_motels:motelkey', false, {
                    index = data.index,
                    motel = data.motel,
                })
                if success then
                    Notify('Úspěšně požádáno o sdílený klíč motelu', 'success')
                else
                    Notify('Chyba při generování klíče', 'error')
                end
            end,
            arrow = true,
        },
        {
            title = 'Konec nájmu',
            description = 'Ukončete svou pronájmovou dobu',
            icon = 'ban',
            onSelect = function()
                if isRentExpired(data) then
                    Notify('Nelze ukončit nájem pro pokoj '.. data.index..'  \n  Důvod: Máte dluh, který musíte zaplatit', 'error')
                    return
                end
                local End = lib.alertDialog({
                    header = '## Varování',
                    content = 'Nebudete mít přístup k dveřím a svým trezorům.',
                    centered = true,
                    labels = {
                        cancel = 'zavřít',
                        confirm = 'Ukončit',
                    },
                    cancel = true
                })
                if End == 'cancel' then return end
                local success = lib.callback.await('pitrs_motels:removeoccupant', false, data, data.index, PlayerData.identifier)
                if success then
                    Notify('Úspěšně ukončen nájem pro pokoj '..data.index, 'success')
                else
                    Notify('Úspěšně jsi vrátil motel '..data.index, 'success')
                end
            end,
            arrow = true,
        },
    }
    lib.registerContext({
        id = 'myroom',
        menu = 'roomlist',
        title = 'Možnosti mého motelového pokoje',
        options = options
    })
    lib.showContext('myroom')
end


CountOccupants = function(players)
	local count = 0
	for k,v in pairs(players or {}) do
		count += 1
	end
	return count
end




RoomList = function(data)
    local motels, time = lib.callback.await('pitrs_motels:getMotels', false)
    local rate = motels[data.motel].hour_rate or data.rate
    local options = {}

    for doorindex, v in ipairs(data.doors) do
        local playerroom = motels[data.motel].rooms[doorindex].players[PlayerData.identifier]
        local duration = playerroom?.duration
        local occupants = CountOccupants(motels[data.motel].rooms[doorindex].players)

        if occupants < data.maxoccupants and not duration then
            table.insert(options, {
                title = 'Pokoj motelu #'..doorindex,
                description = 'Vyberte pokoj #'..doorindex..' \n Obsazeno: '..occupants..'/'..data.maxoccupants,
                icon = 'door-closed',
                onSelect = function()
                    local input = lib.inputDialog('Délka pronájmu', {
                        {type = 'number', label = 'Zadej čas '..data.rental_period..'s', description = '$ '..rate..' za '..data.rental_period..'   \n   Platební metoda: '..data.payment, icon = 'clock', default = 1},
                    })
                    if not input then return end


                    if lib.progressCircle({
                        duration = 8000,
                        position = 'bottom',
                        useWhileDead = false,
                        canCancel = false,
                        disable = {
                            car = true,
                        },
                    }) then

                        local success = lib.callback.await('pitrs_motels:rentaroom', false, {
                            index = doorindex,
                            motel = data.motel,
                            duration = input[1],
                            rate = rate,
                            rental_period = data.rental_period,
                            payment = data.payment,
                            uniquestash = data.uniquestash
                        })
                        if success then
                            Notify('Pokoj byl úspěšně pronajat', 'success')
                        else
                            Notify('Nemůžeš si pronajmout další motel', 'error')
                        end
                    else

                        print('Do stuff when cancelled')  
                    end
                end,
                arrow = true,
            })
        elseif duration then
            local hour = math.floor((duration - time) / 3600)
            local duration_left = hour .. ' Hodiny : '..math.floor(((duration - time) / 60) - (60 * hour))..' Minuty'
            table.insert(options, {
                title = 'Možnosti pro pokoj #'..doorindex,
                description = 'Zaplaťte svůj nájem nebo požádejte o klíč k motelu',
                icon = 'cog',
                onSelect = function()
                    return MyRoomMenu({
                        payment = data.payment,
                        index = doorindex,
                        motel = data.motel,
                        duration = duration_left,
                        rate = rate,
                        rental_period = data.rental_period
                    })
                end,
                arrow = true,
            })
        end
    end

    lib.registerContext({
        id = 'roomlist',
        menu = 'rentmenu',
        title = 'Vyberte pokoj',
        options = options
    })
    lib.showContext('roomlist')
end




















IsOwnerOrEmployee = function(motel)
	local motels = GlobalState.Motels
	return motels[motel].owned == PlayerData.identifier or motels[motel].employees[PlayerData.identifier]
end

MotelRentalMenu = function(data)
    local motels = GlobalState.Motels
    local rate = motels[data.motel].hour_rate or data.rate
    local options = {}
    if not data.manual then
        table.insert(options, {
            title = 'Pronajmout nový pokoj motelu',
            description = '![pronájem](nui://pitrs_motels/data/image/'..data.motel..'.png) \n Vyberte pokoj k pronájmu \n '..data.rental_period..' Cena: $'..rate,
            icon = 'hotel',
            onSelect = function()
                return RoomList(data)
            end,
            arrow = true,
        })
    end
    if not motels[data.motel].owned and config.business or IsOwnerOrEmployee(data.motel) and config.business then
        local title = not motels[data.motel].owned and 'Koupit motelový podnik' or 'Motelová správa'
        local description = not motels[data.motel].owned and 'Cena: '..data.businessprice or 'Spravujte zaměstnance, nájemce a finance.'
        table.insert(options, {
            title = title,
            description = description,
            icon = 'hotel',
            onSelect = function()
                return MotelOwner(data)
            end,
            arrow = true,
        })
    end

    if #options == 0 then
        Notify('Tento motel přijímá nájemce pouze ručně \n  Kontaktujte majitele')
        Wait(1500)
        return SendMessageApi(data.motel)
    end

    lib.registerContext({
        id = 'rentmenu',
        title = data.label,
        options = options
    })
    lib.showContext('rentmenu')
end

SendMessageApi = function(motel)
    local message = lib.alertDialog({
        header = 'Chcete poslat zprávu majiteli?',
        content = '## Zpráva pro majitele motelu',
        centered = true,
        labels = {
            cancel = 'zavřít',
            confirm = 'Odeslat zprávu',
        },
        cancel = true
    })
    if message == 'cancel' then return end
    local input = lib.inputDialog('Zpráva', {
        {type = 'input', label = 'Název', description = 'název vaší zprávy', icon = 'hash', required = true},
        {type = 'textarea', label = 'Popis', description = 'vaše zpráva', icon = 'mail', required = true},
        {type = 'number', label = 'Kontaktní číslo', icon = 'phone', required = false},
    })
    
    config.messageApi({title = input[1], message = input[2], motel = motel})
end

Owner = {}
Owner.Rooms = {}
Owner.Rooms.Occupants = function(data,index)
    local motels , time = lib.callback.await('pitrs_motels:getMotels',false)
    local motel = motels[data.motel]
    local players = motel.rooms[index] and motel.rooms[index].players or {}
    local options = {}
    for player,char in pairs(players) do
        local hour = math.floor((char.duration - time) / 3600)
        local name = char.name or 'Bez jména'
        local duration_left = hour .. ' Hodin : '..math.floor(((char.duration - time) / 60) - (60 * hour))..' Minut'
        table.insert(options, {
            title = 'Nájemce '..name,
            description = 'Délka pronájmu: '..duration_left,
            icon = 'hotel',
            onSelect = function()
                local kick = lib.alertDialog({
                    header = 'Potvrzení',
                    content = '## Vykopnout nájemce \n  **Jméno:** '..name,
                    centered = true,
                    labels = {
                        cancel = 'zavřít',
                        confirm = 'Vykopnout',
                        waw = 'waw'
                    },
                    cancel = true
                })
                if kick == 'cancel' then return end
                local success = lib.callback.await('pitrs_motels:removeoccupant',false,data,index,player)
                if success then
                    Notify('Úspěšně vykopnut '..name..' z pokoje '..index,'success')
                else
                    Notify('Nepodařilo se vykopnout '..name..' z pokoje '..index,'error')
                end
            end,
            arrow = true,
        })
    end
    if data.maxoccupants > #options then
        for i = 1, data.maxoccupants-#options do
            table.insert(options,{
                title = 'Volné místo',
                icon = 'hotel',
                onSelect = function()
                    local input = lib.inputDialog('Nový nájemce', {
                        {type = 'number', label = 'ID občana', description = 'ID občana, kterého chcete přidat', icon = 'id-card', required = true},
                        {type = 'number', label = 'Zadej čas pronájmu '..data.rental_period..'s', description = 'kolik '..data.rental_period..'s', icon = 'clock', default = 1},
                    })
                    if not input then return end
                    local success = lib.callback.await('pitrs_motels:addoccupant',false,data,index,input)
                    if success == 'exist' then
                        Notify('Tento nájemce již existuje v pokoji '..index,'error')
                    elseif success then
                        Notify('Úspěšně přidán '..input[1]..' do pokoje '..index,'success')
                    else
                        Notify('Nepodařilo se přidat '..input[1]..' do pokoje '..index,'error')
                    end
                end,
                arrow = true,
            })
        end
    end
    lib.registerContext({
        menu = 'owner_rooms',
        id = 'occupants_lists',
        title = 'Nájemci pokoje #'..index,
        options = options
    })
    lib.showContext('occupants_lists')
end


Owner.Rooms.List = function(data)
    local motels = GlobalState.Motels
    local options = {}
    for doorindex,v in ipairs(data.doors) do
        local occupants = CountOccupants(motels[data.motel].rooms[doorindex].players)
        table.insert(options,{
            title = 'Pokoj #'..doorindex,
            description = 'Přidat nebo vykopnout nájemce z pokoje #'..doorindex..' \n ***Počet nájemců:*** '..occupants,
            icon = 'hotel',
            onSelect = function()
                return Owner.Rooms.Occupants(data,doorindex)
            end,
            arrow = true,
        })
    end
    lib.registerContext({
        menu = 'motelmenu',
        id = 'owner_rooms',
        title = data.label,
        options = options
    })
    lib.showContext('owner_rooms')
end

Owner.Employee = {}
Owner.Employee.Manage = function(data)
    local motel = GlobalState.Motels[data.motel]
    local options = {
        {
            title = 'Přidat zaměstnance',
            description = 'Přidejte místního občana mezi zaměstnance vašeho motelu',
            icon = 'hotel',
            onSelect = function()
                local input = lib.inputDialog('Přidat zaměstnance', {
                    {type = 'number', label = 'ID občana', description = 'ID občana, kterého chcete přidat', icon = 'id-card', required = true},
                })
                if not input then return end
                local success = lib.callback.await('pitrs_motels:addemployee',false,data.motel,input[1])
                if success then
                    Notify('Úspěšně přidáno do seznamu zaměstnanců','success')
                else
                    Notify('Nepodařilo se přidat do zaměstnanců','error')
                end
            end,
            arrow = true,
        }
    }
    if motel and motel.employees then
       for identifier,name in pairs(motel.employees) do
          table.insert(options,{
            title = name,
            description = 'Odstranit '..name..' ze seznamu vašich zaměstnanců',
            icon = 'hotel',
            onSelect = function()
                local success = lib.callback.await('pitrs_motels:removeemployee',false,data.motel,identifier)
                    if success then
                        Notify('Úspěšně odstraněno ze seznamu zaměstnanců','success')
                    else
                        Notify('Nepodařilo se odstranit ze zaměstnanců','error')
                    end
            end,
            arrow = true,
        })
       end
    end
    lib.registerContext({
        id = 'employee_manage',
        title = 'Správa zaměstnanců',
        options = options
    })
    lib.showContext('employee_manage')
end


MotelRentalPoints = function(data)
    local point = lib.points.new(data.rentcoord, 5, data)

    function point:onEnter() 
        lib.showTextUI('🏨[E] - Otevřít Motel Menu')
    end

    function point:onExit() 
        lib.hideTextUI()
    end

    function point:nearby()
        if self.currentDistance < 1 and IsControlJustReleased(0, 38) then
            MotelRentalMenu(data)
        end
    end
    return point
end



local inMotelZone = false
local npcModel = GetHashKey('a_m_m_business_01')  
local npc = nil 

MotelZone = function(data)
    local point = nil  

    function spawnNPC(coords)
        if npc then return end 

        RequestModel(npcModel)
        while not HasModelLoaded(npcModel) do
            Wait(500)
        end

        npc = CreatePed(4, npcModel, coords.x, coords.y, coords.z, 330.0, true, false)  
        SetEntityAsMissionEntity(npc, true, true)
        SetBlockingOfNonTemporaryEvents(npc, true)
        SetPedCanBeTargetted(npc, false)
        FreezeEntityPosition(npc, true)  
        TaskStandStill(npc, -1)  
    end

    function onEnter(self) 
        if inMotelZone then return end  

        inMotelZone = true
        print("Entering motel zone")  
        Citizen.CreateThreadNow(function()
            for index, doors in pairs(data.doors) do
                for type, coord in pairs(doors) do
                    MotelFunction({
                        payment = data.payment or 'money',
                        uniquestash = data.uniquestash, 
                        shell = data.shell, 
                        Mlo = data.Mlo, 
                        type = type, 
                        index = index, 
                        coord = coord, 
                        label = config.Text[type], 
                        motel = data.motel, 
                        door = data.door
                    })
                end
            end
            point = MotelRentalPoints(data) 
            spawnNPC(data.coord) 
        end)
    end

    function onExit(self)
        if not inMotelZone then return end  

        inMotelZone = false
        print("Exiting motel zone") 
        point:remove()
        if npc then
            DeleteEntity(npc)  
            npc = nil
        end
        for k,id in pairs(zones) do
            removeTargetZone(id)
        end
        for k,id in pairs(blips) do
            if DoesBlipExist(id) then
                RemoveBlip(id)
            end
        end
        zones = {}
    end

    local sphere = lib.zones.sphere({
        coords = data.coord,
        radius = data.radius,
        debug = false,
        inside = inside,
        onEnter = onEnter,
        onExit = onExit
    })
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        print("Resource is stopping, cleaning up...")
        if npc then
            DeleteEntity(npc) 
            npc = nil
        end
        if inMotelZone then
            inMotelZone = false
            if point then
                point:remove()  
            end
        end
    end
end)


--qb-interior func
local house
local inhouse = false
function Teleport(x, y, z, h ,exit)
    CreateThread(function()
        SetEntityCoords(cache.ped, x, y, z, 0, 0, 0, false)
        SetEntityHeading(cache.ped, h or 0.0)
        Wait(1001)
        DoScreenFadeIn(1000)
    end)
	if exit then
		inhouse = false
		TriggerEvent('qb-weathersync:client:EnableSync')
		for k,id in pairs(shelzones) do
			removeTargetZone(id)
		end
		DeleteEntity(house)
		lib.callback.await('pitrs_motels:SetRouting',false,data,'exit')
		shelzones = {}
		DeleteResourceKvp(kvpname)
		LocalPlayer.state:set('inshell',false,true)
	end
end

EnterShell = function(data,login)
    local motels = GlobalState.Motels
    if motels[data.motel].rooms[data.index].lock and not login then
        Notify('Dveře jsou zamčeny', 'error')
        return false
    end
    local shelldata = config.shells[data.shell or data.motel]
    if not shelldata then 
        warn('Shell není nakonfigurován')
        return 
    end
    lib.callback.await('pitrs_motels:SetRouting',false,data,'enter')
    inhouse = true
    Wait(1000)
    local spawn = vec3(data.coord.x,data.coord.y,data.coord.z)+vec3(0.0,0.0,1500.0)
    local offsets = shelldata.offsets
    local model = shelldata.shell
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do
        Wait(10)
    end
    inhouse = true
    TriggerEvent('qb-weathersync:client:DisableSync')
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(1000)
    end
    local lastloc = GetEntityCoords(cache.ped)
    house = CreateObject(model, spawn.x, spawn.y, spawn.z, false, false, false)
    FreezeEntityPosition(house, true)
    LocalPlayer.state:set('lastloc',data.lastloc or lastloc,false)
    data.lastloc = data.lastloc or lastloc
    if not login then
        SendNUIMessage({
            type = 'door'
        })
    end
    Teleport(spawn.x + offsets.exit.x, spawn.y + offsets.exit.y, spawn.z+0.1, offsets.exit.h)
    SetResourceKvp(kvpname,json.encode(data))

    Citizen.CreateThreadNow(function()
        ShellTargets(data,offsets,spawn,house)
        while inhouse do
            --SetRainLevel(0.0)
            SetWeatherTypePersist('CLEAR')
            SetWeatherTypeNow('CLEAR')
            SetWeatherTypeNowPersist('CLEAR')
            NetworkOverrideClockTime(18, 0, 0)
            Wait(1)
        end
    end)
    return house
end


function RotationToDirection(rotation)
	local adjustedRotation = 
	{ 
		x = (math.pi / 180) * rotation.x, 
		y = (math.pi / 180) * rotation.y, 
		z = (math.pi / 180) * rotation.z 
	}
	local direction = 
	{
		x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)), 
		y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)), 
		z = math.sin(adjustedRotation.x)
	}
	return direction
end

function RayCastGamePlayCamera(distance,flag)
    local cameraRotation = GetGameplayCamRot()
    local cameraCoord = GetGameplayCamCoord()
	local direction = RotationToDirection(cameraRotation)
	local destination =  vector3(cameraCoord.x + direction.x * distance, 
		cameraCoord.y + direction.y * distance, 
		cameraCoord.z + direction.z * distance 
    )
    if not flag then
        flag = 1
    end

	local a, b, c, d, e = GetShapeTestResultIncludingMaterial(StartShapeTestRay(cameraCoord.x, cameraCoord.y, cameraCoord.z, destination.x, destination.y, destination.z, flag, -1, 1))
	return b, c, e, destination
end

local lastweapon = nil
lib.onCache('weapon', function(weapon)
    if not inMotelZone then return end
    if not PlayerData.job then return end
    if not config.breakinJobs[PlayerData.job.name] then return end
    local motels = GlobalState.Motels
    lastweapon = weapon
    while weapon and weapon == lastweapon do
        Wait(33)
        if IsPedShooting(cache.ped) then
            local _, bullet, _ = RayCastGamePlayCamera(200.0,1)
            for k,data in pairs(config.motels) do
                for k,v in pairs(data.doors) do
                    if #(vec3(bullet.x,bullet.y,bullet.z) - vec3(v.door.x,v.door.y,v.door.z)) < 2 and motels[data.motel].rooms[k].lock then
                        TriggerServerEvent('pitrs_motels:Door', {
                            motel = data.motel,
                            index = k,
                            coord = v.door,
                            Mlo = data.Mlo,
                        })
                        local text
                        if data.Mlo then
                            local doorindex = k + (joaat(data.motel))
                            text = DoorSystemGetDoorState(doorindex) == 0 and 'Zničil(a) jsi dveře motelu'
                        else
                            text = 'Zničil(a) jsi dveře motelu'
                        end
                        Notify(text,'warning')
                    end
                end
                Wait(1000)
            end
        end
    end
end)


RegisterNetEvent('pitrs_motels:MessageOwner', function(data)
	AddTextEntry('esxAdvancedNotification', data.message)
    BeginTextCommandThefeedPost('esxAdvancedNotification')
	ThefeedSetNextPostBackgroundColor(1)
	AddTextComponentSubstringPlayerName(data.message)
    EndTextCommandThefeedPostMessagetext('CHAR_FACEBOOK', 'CHAR_FACEBOOK', false, 1, data.motel, data.title)
    EndTextCommandThefeedPostTicker(flash or false, true)
end)








RegisterNetEvent('pitrs_motels:removeKey', function(motel, index)
    local keyItem = 'keys'
    local metadata = {
        type = motel,
        serial = tonumber(index), 
        owner = PlayerData.identifier
    }

  --  print("Debug - Removing key on client with metadata:", json.encode(metadata))

    local success = exports.ox_inventory:RemoveItem(PlayerId(), keyItem, 1, metadata)
    if success then
        Notify('Klíč byl úspěšně odstraněn z vašeho inventáře.', 'success')
    else
        Notify('Nepodařilo se odstranit klíč. Kontaktujte administrátora.', 'error')
       -- print("Error: RemoveItem failed on client.")
    end
end)
