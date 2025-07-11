#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode("Pixel", "Screen")


; GLOBAL VARIABLES
global isDigging := false, hasDig := false, isSelling := false, isMoving := false, isCalibrating := false
global isHoldingShovel := false, hasEnchantedHourglass := false, EnchanHrGlsSlot := "0"
global inventoryCount := 0, inventoryThreshold := 60, totalDug := 0, lastInventoryCount := 0, wasPaused := false
global squareDirections := ["w", "a", "s", "d"], laneDirections := ["w", "s"], movement := "lane", chosenMovement := ""
global moveIndex := 1, merchantLocation := 1, merchantSelling := true, hasSellInvGamepass := false, hasSold := false, autoSellEnabled := true
global DEFAULT_PIXEL_POS := [1520, 846], customPixelPos := [], isRarityCalibrated := false, lastRarityHex := ""
global DEFAULT_GAMEPASS_POS := [1260, 920], customGamePassSellPos := [], isSellCalibrated := false
global iniFile := A_ScriptDir "\iniFile", canReset := false

rarityColors := Map()
rarityColors["6D6D6D"] := { name: "Junk",      enabled: true }
rarityColors["356A39"] := { name: "Ordinary", enabled: true }
rarityColors["3D5D7A"] := { name: "Rare",     enabled: true }
rarityColors["423871"] := { name: "Epic",     enabled: true }
rarityColors["7A633C"] := { name: "Legendary",enabled: true }
rarityColors["7A3C3C"] := { name: "Mythical", enabled: true }
rarityColors["7A0A7A"] := { name: "Special",  enabled: true }

; CALIBRATION FUNCTIONS
CalibratePixels(type) {
    global customPixelPos, DEFAULT_PIXEL_POS
    global customGamePassSellPos, DEFAULT_GAMEPASS_POS
    global isRarityCalibrated, isSellCalibrated

    ToolTip()
    if type = "rarity" {
        ToolTip("🛠 Click the digging bar pixel (Right-click to cancel)...")
        result := WaitForMouseClick()
        if result {
            customPixelPos := result
            isRarityCalibrated := true
            ToolTip("✅ Saved rarity pixel: " customPixelPos[1] ", " customPixelPos[2])
        } else {
            customPixelPos := DEFAULT_PIXEL_POS
            isRarityCalibrated := false
            ToolTip("❌ Canceled! Reverting to default rarity pixel: " DEFAULT_PIXEL_POS[1] ", " DEFAULT_PIXEL_POS[2])
        }
    }
    else if type = "sell" {
        ToolTip("🛠 Click the Sell Inventory button (Right-click to cancel)...")
        result := WaitForMouseClick()
        if result {
            customGamePassSellPos := result
            isSellCalibrated := true
            ToolTip("✅ Saved sell button: " customGamePassSellPos[1] ", " customGamePassSellPos[2])
        } else {
            customGamePassSellPos := DEFAULT_GAMEPASS_POS
            isSellCalibrated := false
            ToolTip("❌ Canceled! Reverting to default sell button: " DEFAULT_GAMEPASS_POS[1] ", " DEFAULT_GAMEPASS_POS[2])
        }
    }
    else {
        ToolTip("⚠️ Unknown calibration type: " type)
    }
    Sleep(1200)
    ToolTip()
}

WaitForMouseClick() {
    Loop {
        Sleep(10)
        if GetKeyState("RButton", "P")
            return false
        if GetKeyState("LButton", "P")
            break
    }
    MouseGetPos(&x, &y)
    Loop {
        Sleep(10)
        if !GetKeyState("LButton", "P")
            break
    }
    return [x, y]
}

; SHOVEL TOGGLE + DETECTION
~1:: {
    global isHoldingShovel, isDigging, digFirstTimeRun
    if digFirstTimeRun
        return
    isHoldingShovel := !isHoldingShovel
    ToolTip("Shovel toggled manually: " (isHoldingShovel ? "Equipped" : "Unequipped"))
    if (isDigging && !isHoldingShovel) {
        ToggleDigging()
        ToolTip("Digging stopped because shovel was unequipped manually")
    }
    SetTimer(() => ToolTip(), -1500)
}

ToggleShovel(state) {
    global isHoldingShovel
    if (state = "equip" && !isHoldingShovel) {
        Send("1")
        isHoldingShovel := true
        return isHoldingShovel
    } else if (state = "unequip" && isHoldingShovel) {
        Send("1")
        isHoldingShovel := false
        return isHoldingShovel
    }
}

; DIGGING LOGIC
ToggleDigging() {
    global isDigging, wasPaused
    isDigging := !isDigging
    if isDigging {
        ToggleShovel("equip")
        SetTimer(MonitorDigState, 100)
        Sleep(250)
        SetTimer(Dig, 50)
        Sleep(250)
        SetTimer(CheckInventoryStall, 2000)
        ToolTip("Started digging")
    } else {
        ToggleShovel("unequip")
        ToolTip("Digging stopped")
        SetTimer(Dig, 0)
        SetTimer(MonitorDigState, 0)
        SetTimer(CheckInventoryStall, 0)
        wasPaused := true
    }
    SetTimer(() => ToolTip(), -1000)
}

CanDig() {
    global isMoving, isSelling, isCalibrating
    return !isMoving && !isSelling && !isCalibrating
}

Dig(*) {
    if !CanDig() {
        ToolTip("Can't dig")
        Click("up", "left")
        return
    }
    Click("down", "left")
    Sleep(35)
    Click("up", "left")
}

MonitorDigState() {
    global rarityColors, lastRarityHex, hasDig
    global inventoryCount, inventoryThreshold, totalDug

    currentHex := GetCurrentPixelHex()
    isKnown := rarityColors.Has(currentHex)
    wasKnown := rarityColors.Has(lastRarityHex)

    if isKnown && (!wasKnown || currentHex != lastRarityHex) {
        if rarityColors[currentHex].enabled {
            hasDig := true
            ToolTip("🟢 New dig started: " rarityColors[currentHex].name)
        } else {
            hasDig := false
            ToolTip("⛔️ Skipping disabled rarity: " rarityColors[currentHex].name)
            AutoMove()
        }
    }
    else if hasDig && (!isKnown && wasKnown) {
        hasDig := false
        inventoryCount += 1
        totalDug += 1
        ToolTip("⚪️ Dig finished: " inventoryCount "/" inventoryThreshold)
        if inventoryCount >= inventoryThreshold
            SellInventory()
    }
    lastRarityHex := currentHex
}

CheckInventoryStall() {
    global inventoryCount, lastInventoryCount, inventoryCheckTime, isSelling, isMoving, wasPaused

    if wasPaused {
        inventoryCheckTime := A_TickCount
        wasPaused := false
        return
    }
    if isSelling || isMoving
        return
    if !IsSet(inventoryCheckTime)
        inventoryCheckTime := A_TickCount
    if inventoryCount != lastInventoryCount {
        lastInventoryCount := inventoryCount
        inventoryCheckTime := A_TickCount
        return
    }
    if (A_TickCount - inventoryCheckTime > 10000) {
        ToolTip("🕒 Inventory stalled — backup triggered")
        SellInventory()
        ToggleShovel("equip")
        inventoryCheckTime := A_TickCount
        SetTimer(() => ToolTip(), -1000)
    }
}

GetCurrentPixelHex() {
    global customPixelPos, DEFAULT_PIXEL_POS, isRarityCalibrated
    pos := isRarityCalibrated ? customPixelPos : DEFAULT_PIXEL_POS
    color := PixelGetColor(pos[1], pos[2], "RGB") & 0xFFFFFF
    return Format("{:06X}", color)
}

; MOVEMENT & SELLING
AutoMove() {
    global moveIndex, isMoving, movement, laneDirections, squareDirections

    ToggleDigging()
    if isMoving
        return
    isMoving := true
    movementDirections := (movement = "lane") ? laneDirections : squareDirections
    dirKey := movementDirections[moveIndex]
    ToolTip("🚶 Moving: " dirKey)
    Send("{" dirKey " down}")
    Sleep(1000)
    Send("{" dirKey " up}")
    moveIndex := (moveIndex < movementDirections.Length) ? moveIndex + 1 : 1
    SetTimer(() => ToolTip(), -500)
    isMoving := false
    Sleep(1000)
    ToggleDigging()
}


SellInventory() {
    global isSelling, isDigging, hasDig, hasSold
    global inventoryCount, inventoryThreshold
    global merchantSelling, hasSellInvGamepass, autoSellEnabled
    global merchantLocation, moveIndex
    global isSellCalibrated, customGamePassSellPos, DEFAULT_GAMEPASS_POS
    global hasEnchantedHourglass, EnchanHrGlsSlot

    
    if !autoSellEnabled
        return
    hasSold := false
    if isSelling
        return
    isSelling := true
    ToolTip("💰 Selling initiated...")
    Loop {
        if !hasDig
            break
        Sleep(100)
    }
    if isDigging
        ToggleDigging()
    if hasSellInvGamepass {
        ToolTip("⚡ Gamepass sell triggered")
        MouseGetPos(&oldX, &oldY)
        pos := customGamePassSellPos.Length ? customGamePassSellPos : DEFAULT_GAMEPASS_POS
        MouseMove(pos[1], pos[2])
        Sleep(500)
        offsetX := Floor(Random(-3, 4))
        offsetY := Floor(Random(-3, 4))

        MouseMove(pos[1] + offsetX, pos[2] + offsetY)
        Sleep(150)
        Click()
        Sleep(100)
        MouseMove(oldX, oldY)
        hasSold := true
    }


    if (hasEnchantedHourglass && EnchanHrGlsSlot != "0") {
        ToolTip("Using Enchanted Hourglass to Sell")
        Sleep(1000)
        Send(EnchanHrGlsSlot)
        ToolTip("Teleporting")
        Sleep(500)
        Click()
        Sleep(500)
        moveIndex := 1
        Send("{e}")
        Sleep(1500)
        Send("1")
        Click(3)
        Sleep(300)
        AutoMove()
        hasSold := true
    } 
    if (hasSold = false) {
        ToolTip("🛒 Walking to merchant...")
        Loop {
            if moveIndex = merchantLocation
                break
            AutoMove()
            Sleep(300)
        }
        ToggleShovel("unequip")
        Send("{e}")
        Sleep(1500)
        Send("1")
        Sleep(300)
        AutoMove()
        hasSold := true
    }
    inventoryCount := 0
    ToolTip("✅ Selling complete — back to digging!")
    Sleep(1000)
    ToggleDigging()
    SetTimer(() => ToolTip(), -1000)
    isSelling := false
    hasSold := false
}

; GUI CREATION & SETTINGS
resetUi() {
    for cb in checkboxes {
        hex := cb.Tag
        cb.Value := rarityColors[hex].enabled ? 1 : 0
    }
    invGamepassCb.Value := hasSellInvGamepass ? 1 : 0
    HourglassCb.Value := hasEnchantedHourglass ? 1 : 0
    hourglassSlotEdit.Text := EnchanHrGlsSlot
    shovelEquippedCb.Value := isHoldingShovel ? 1 : 0
    autoSellCb.Value := autoSellEnabled ? 1 : 0
    sellThresholdEdit.Text := inventoryThreshold
    btnMovementLane.Value := (movement = "lane") ? 1 : 0
    btnMovementSquare.Value := (movement = "square") ? 1 : 0
}

ResetSettings(*) {
    global rarityColors, inventoryThreshold, movement
    global hasSellInvGamepass, hasEnchantedHourglass, EnchanHrGlsSlot
    global isHoldingShovel, autoSellEnabled
    global MyGui, canReset
    global checkboxes, invGamepassCb, HourglassCb, hourglassSlotEdit
    global shovelEquippedCb, autoSellCb, sellThresholdEdit
    global btnMovementLane, btnMovementSquare

    if (!canReset) {
        resetUi
        return
    }


    FileDelete(iniFile)

    ; Reset variables to defaults
    inventoryThreshold := 60
    movement := "lane"
    hasSellInvGamepass := false
    hasEnchantedHourglass := false
    EnchanHrGlsSlot := 1
    isHoldingShovel := false
    autoSellEnabled := true

    ; Reset rarity colors enabled flags
    for hex, _ in rarityColors
        rarityColors[hex].enabled := true

  

    Tooltip("Settings reset to defaults!")
    SetTimer(() => ToolTip(), -1000)
    resetUi
    ; Show the GUI to reflect changes
    if IsSet(MyGui) {
        MyGui.Show()
    }

    canReset := false
}


CreateGui() {
    global rarityColors, checkboxes, MyGui
    global hasSellInvGamepass, invGamepassCb
    global sellThresholdEdit, inventoryThreshold, autoSellCb
    global movement, btnMovementLane, btnMovementSquare, shovelEquippedCb
    global hasEnchantedHourglass, HourglassCb, hourglassSlotEdit

    if IsSet(MyGui) {
        MyGui.Show()
        sellThresholdEdit.Text := inventoryThreshold
        return
    }

    MyGui := Gui()
    MyGui.Text := "Dig Rarity Config"

    checkboxes := []
    yPos := 10
    xPos := 20

    order := ["6D6D6D", "356A39", "3D5D7A", "423871", "7A633C", "7A3C3C", "7A0A7A"]
    for _, hex in order {
        data := rarityColors[hex]
        cb := MyGui.Add("Checkbox", "", "")
        cb.Move(xPos, yPos, 100, 20)
        cb.Text := data.name
        cb.Value := data.enabled ? 1 : 0
        cb.Tag := hex
        checkboxes.Push(cb)
        yPos += 30
    }

    xPos := 150
    yPos := 10
    btnSetPixelsRarity := MyGui.Add("Button", "", "")
    btnSetPixelsRarity.Move(xPos, yPos, 180, 25)
    btnSetPixelsRarity.Text := "Set Rarity Position"
    btnSetPixelsRarity.OnEvent("Click", (*) => CalibratePixels("rarity"))
    yPos += 30

    btnSetPixelsSellInv := MyGui.Add("Button", "", "")
    btnSetPixelsSellInv.Move(xPos, yPos, 180, 25)
    btnSetPixelsSellInv.Text := "Set Sell Inventory Position"
    btnSetPixelsSellInv.OnEvent("Click", (*) => CalibratePixels("sell"))
    yPos += 30

    btnMovementSquare := MyGui.Add("Radio", "", "Square")
    btnMovementLane := MyGui.Add("Radio", "", "Lane")
    btnMovementSquare.Move(xPos + 90, yPos, 90, 25)
    btnMovementLane.Move(xPos, yPos, 90, 25)
    btnMovementLane.Value := (movement = "lane")
    btnMovementSquare.Value := (movement = "square")
    yPos += 30

    invGamepassCb := MyGui.Add("Checkbox", "", "")
    invGamepassCb.Move(xPos, yPos, 260, 20)
    invGamepassCb.Text := "Sell Inventory Gamepass"
    invGamepassCb.Value := hasSellInvGamepass ? 1 : 0
    yPos += 20

    HourglassCb := MyGui.Add("Checkbox", "", "")
    HourglassCb.Move(xPos, yPos, 260, 20)
    HourglassCb.Text := "Use Secret Enchanted Hourglass"
    HourglassCb.Value := (hasEnchantedHourglass ? 1 : 0)
    yPos += 25

    MyGui.Add("Text", "", "Enchanted Hourglass Slot:").Move(xPos, yPos, 130, 20)
    hourglassSlotEdit := MyGui.Add("Edit", "", "")
    hourglassSlotEdit.Move(xPos + 135, yPos - 4, 30, 22)
    hourglassSlotEdit.Text := EnchanHrGlsSlot
    yPos += 35

    shovelEquippedCb := MyGui.Add("Checkbox", "", "")
    shovelEquippedCb.Move(xPos, yPos, 260, 20)
    shovelEquippedCb.Text := "I'm holding the shovel"
    shovelEquippedCb.Value := isHoldingShovel ? 1 : 0
    yPos += 25

    MyGui.Add("Text", "", "Sell Threshold (slots):").Move(xPos, yPos, 110, 20)
    sellThresholdEdit := MyGui.Add("Edit", "", "")
    sellThresholdEdit.Move(xPos + 105, yPos - 4, 50, 22)
    sellThresholdEdit.Text := inventoryThreshold
    yPos += 25
    autoSellCb := MyGui.Add("Checkbox", "", "Enable Auto-Selling")
    autoSellCb.Value := autoSellEnabled ? 1 : 0
    autoSellCb.Move(xPos, yPos, 200, 20)

    yPos += 60

    guiWidth := 350
    btnWidth := 200
    btnX := (guiWidth - btnWidth) // 2
    btnSave := MyGui.Add("Button", "", "")
    btnSave.Move(btnX, yPos, btnWidth, 25)
    btnSave.Text := "Save (REQUIRED ON CHANGES)"
    btnSave.OnEvent("Click", SaveSettings)
    yPos += 50

    creditText := "Made by mrbanjo. (makmatoe)"
    textWidth := 150
    textX := (guiWidth - textWidth) // 2
    txtCredit := MyGui.Add("Text", "", creditText)
    txtCredit.Move(textX, yPos, textWidth, 20)
    yPos += 20
    
    btnReset := MyGui.Add("Button", "", "Reset to Defaults")
    btnReset.Move(btnX, yPos, btnWidth, 25)
    btnReset.OnEvent("Click", ResetSettings)


    totalHeight := yPos 
    MyGui.Opt("+Resize +MinSize350x" . totalHeight)
    MyGui.Size := [guiWidth, totalHeight]
}

LoadSettings() {
    global rarityColors, inventoryThreshold, movement
    global hasSellInvGamepass, hasEnchantedHourglass, EnchanHrGlsSlot
    global isHoldingShovel, autoSellEnabled
    global canReset
    if !FileExist("iniFile")
        return  ; No file yet, use defaults

    inventoryThreshold := IniRead("iniFile", "Settings", "InventoryThreshold", "60")
    movement := IniRead("iniFile", "Settings", "Movement", "lane")
    hasSellInvGamepass := IniRead("iniFile", "Settings", "HasSellInvGamepass", "0")
    hasEnchantedHourglass := IniRead("iniFile", "Settings", "HasEnchantedHourglass", "0")
    EnchanHrGlsSlot := IniRead("iniFile", "Settings", "EnchantedHourglassSlot", "1")
    isHoldingShovel := IniRead("iniFile", "Settings", "IsHoldingShovel", "0")
    autoSellEnabled := IniRead("iniFile", "Settings", "AutoSellEnabled", "1")

    rarityStr := IniRead("iniFile", "Settings", "RarityColors")

    if (rarityStr) {
        pairs := StrSplit(rarityStr, ";")
        for pair in pairs {
            if (pair = "")
                continue
            kv := StrSplit(pair, "=")
            hex := kv[1]
            val := kv[2]
            if rarityColors.Has(hex)
                rarityColors[hex].enabled := (val = 1)
        }
    }
    canReset := true
}

SaveSettings(*) {
    global rarityColors, checkboxes
    global hasSellInvGamepass, invGamepassCb
    global inventoryThreshold, sellThresholdEdit
    global movement, btnMovementLane, btnMovementSquare
    global HourglassCb, hasEnchantedHourglass
    global hourglassSlotEdit, EnchanHrGlsSlot
    global isHoldingShovel, shovelEquippedCb
    global autoSellEnabled, autoSellCb
    global canReset

    for cb in checkboxes {
        hex := cb.Tag
        rarityColors[hex].enabled := (cb.Value = 1)
    }

    hasSellInvGamepass := (invGamepassCb.Value = 1)
    hasEnchantedHourglass := (HourglassCb.Value = 1)
    isHoldingShovel := (shovelEquippedCb.Value = 1)
    movement := btnMovementLane.Value ? "lane" : "square"
    newThreshold := sellThresholdEdit.Text
    EnchanHrGlsSlot := hourglassSlotEdit.Text

    if !(newThreshold ~= "^\d+$" && newThreshold > 0 && newThreshold <= 99) {
        Tooltip("Invalid Sell Threshold! Must be 1-99.")
        SetTimer(() => ToolTip(), -1000)
        return
    }
    if (HourglassCb.Value == 1) {
        if !(EnchanHrGlsSlot ~= "^\d+$" && EnchanHrGlsSlot > 0 && EnchanHrGlsSlot < 10) {
            Tooltip("Invalid Hourglass Slot! Must be 1-9.")
            SetTimer(() => ToolTip(), -1000)
            return
        }
    }


    inventoryThreshold := newThreshold + 0

    ; Save main settings
    IniWrite(inventoryThreshold, "iniFile", "Settings", "InventoryThreshold")
    IniWrite(movement, "iniFile", "Settings", "Movement")
    IniWrite(hasSellInvGamepass, "iniFile", "Settings", "HasSellInvGamepass")
    IniWrite(hasEnchantedHourglass, "iniFile", "Settings", "HasEnchantedHourglass")
    IniWrite(EnchanHrGlsSlot, "iniFile", "Settings", "EnchantedHourglassSlot")
    IniWrite(isHoldingShovel, "iniFile", "Settings", "IsHoldingShovel")
    IniWrite(autoSellEnabled, "iniFile", "Settings", "AutoSellEnabled")

    rarityStr := ""
    for hex, data in rarityColors {
        rarityStr .= hex "=" (data.enabled ? 1 : 0) ";"
    }
    IniWrite(rarityStr, "iniFile", "Settings", "RarityColors")

    Tooltip("Settings saved!")
    SetTimer(() => ToolTip(), -1000)
    MyGui.Hide()
    canReset := true
}

ShowHelpGui() {
    global helpGui

    if IsSet(helpGui) {
        helpGui.Show()
        return
    }

    helpText := 
    "📋 Makmakro Help 📋`n`n"
    . "🛠️ Controls:`n"
    . "  • F1 — Start/Stop digging`n"
    . "  • F2 — Open macro settings menu`n"
    . "  • F3 — Show/close this help menu`n"
    . "  • ESC — Close macro`n`n"
    . "⚙️ Features:`n"
    . "  • Calibrate digging & sell pixels`n"
    . "  • Customize inventory threshold & movement (Lane/Square)`n"
    . "  • Enable/disable auto-selling & enchanted hourglass`n`n"
    . "🚶 Movement:`n"
    . "  • Lane: forward/back — safer, may get stuck briefly`n"
    . "  • Square: forward, left, back, right — avoids short loops`n`n"
    . "⚙️ Calibration:`n"
    . "  • For rarity pixel, start digging in-game, then click 'Set Rarity' in settings and select the colored bar.`n"
    . "  • For sell button (gamepass), click 'Set Sell' and select the sell button.`n"
    . "  • Set your shovel holding state properly in settings before starting.`n`n"
    . "💡 Tips:`n"
    . "  • Don't try to bug the macro :)`n"
    . "  • Face the merchant for autoselling, use top-down camera facing your movement direction.`n"
    . "  • Recalibrate if digging indicator acts up.`n"
    . "  • Contact mrbanjo on Discord for support.`n`n"
    . "❗ Press Close or F3 to exit this help menu.`n`n"
    . "Give Wdrk his 2x XP pots!"


    helpGui := Gui("+AlwaysOnTop")
    helpGui.Title := "Help - Makmakro"
    helpGui.SetFont("s10")
    helpGui.AddEdit("w380 h280 ReadOnly VScroll", helpText)
    btnClose := helpGui.AddButton("w80 h30", "Close")

    btnClose.OnEvent("Click", (*) => helpGui.Hide())
    helpGui.OnEvent("Escape", (*) => helpGui.Hide())

    helpGui.Show("Center")
}





; HOTKEY BINDS
global digFirstTimeRun := true
global uiFirstTimeRun := true
F1::{
    global digFirstTimeRun
    if digFirstTimeRun {
        if (!hasSellInvGamepass && hasEnchantedHourglass && EnchanHrGlsSlot != "0") {
            Send(EnchanHrGlsSlot)
            Sleep(1000)
            Click(3)
            Sleep(100)
            Send(EnchanHrGlsSlot)
        }
        if (hasSellInvGamepass && !isSellCalibrated) {
            MsgBox("⚠️ Warning: Sell Inventory button has not been calibrated, if you're not using the resolution 1920x1080, please calibrate")
            CalibratePixels("sell")
        }
        if (isHoldingShovel = false) {
            MsgBox("⚠️ Warning: Make sure you're not holding your shovel!") 
        }   else {
            MsgBox("⚠️ Warning: Make sure you're holding your shovel!")

        }
        ToolTip("Shovel equipped: " (isHoldingShovel ? "Yes" : "No"))
        Sleep(1000)
        ToolTip()
    }
    ToggleDigging
    digFirstTimeRun := false
}



F2:: {
    Tooltip()
    global uiFirstTimeRun, MyGui, hasDig, isDigging

    if uiFirstTimeRun {
        CreateGui()
        uiFirstTimeRun := false
    }

    if (isDigging) {
        ToolTip("Waited for Dig to Finish, opening Menu")
        ToggleDigging()
        Sleep(300)
    }


    if IsSet(MyGui) && WinExist("ahk_id " MyGui.Hwnd) {
        MyGui.Hide()
    } else {
        MyGui.Show("Center")
    }
}



F3:: {
    Tooltip()
    global helpGui

    if !IsSet(helpGui) {
        ShowHelpGui()
        return
    }

    if WinExist("ahk_id " helpGui.Hwnd) {
        helpGui.Hide()
    } else {
        helpGui.Show("Center")
    }
}

ToolTip("Press F3 to get started :)")

LoadSettings
; Made with love for the game Dig It on roblox, by makmatoe


Esc:: {
    ToolTip("Made with love by makmatoe")
    unusable := true
    Sleep(1500)
    ExitApp
}



