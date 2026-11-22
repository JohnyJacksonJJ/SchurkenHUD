-- SchurkenHUD v1.1
-- 1) Leben des Ziels (Zahl + Prozent) über dessen Namensplakette, 50% durchsichtig
-- 2) Combopunkte darüber, 50% durchsichtig
-- 3) Eigener Lebensbalken über dem Charakter, nur im Kampf
--
-- Befehle: /shud unlock | lock | reset | test

local TARGET_ALPHA = 0.5
local MAX_COMBO    = 5

local defaults = { point = "CENTER", x = 0, y = 35, plateOffset = 20, v = 2 }
local db = defaults

local isSecret = issecretvalue or function() return false end
local GetNamePlateForUnit = C_NamePlate and C_NamePlate.GetNamePlateForUnit

local function Msg(text)
    print("|cffffd200SchurkenHUD:|r " .. tostring(text))
end

-- Fehler einmalig im Chat melden statt still zu scheitern
local reported = {}
local function Safe(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported[name] then
        reported[name] = true
        Msg("|cffff4040Fehler in " .. name .. ":|r " .. tostring(err))
    end
end

local function HealthColor(pct)
    if pct > 0.5 then return (1 - pct) * 2, 1, 0 end
    return 1, pct * 2, 0
end

local function GetCombo()
    local cp
    if GetComboPoints then cp = GetComboPoints("player", "target") end
    if (cp == nil or (not isSecret(cp) and cp == 0)) and Enum and Enum.PowerType and Enum.PowerType.ComboPoints then
        cp = UnitPower("player", Enum.PowerType.ComboPoints)
    end
    return cp or 0
end

------------------------------------------------------------
-- Ziel-Anzeige
------------------------------------------------------------
local tf = CreateFrame("Frame", "SchurkenHUDTarget", UIParent)
tf:SetSize(160, 34)
tf:SetAlpha(TARGET_ALPHA)
tf:SetFrameStrata("MEDIUM")
tf:Hide()

-- Lebenszahlen sitzen IN der Lebensleiste der Namensplakette
-- eigener Frame an UIParent, damit die Zahlen NICHT durchsichtig sind
local hpf = CreateFrame("Frame", "SchurkenHUDTargetHP", UIParent)
hpf:SetFrameStrata("MEDIUM")
hpf:SetSize(1, 1)
hpf:SetAlpha(1)
hpf:Hide()
tf:SetScript("OnShow", function() hpf:Show() end)
tf:SetScript("OnHide", function() hpf:Hide() end)
tf.hp = hpf:CreateFontString(nil, "OVERLAY")
tf.hp:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
tf.hp:SetPoint("CENTER", hpf, "CENTER", 0, 0)
tf.hp:SetTextColor(1, 1, 1)

local function FindHealthBar(plate)
    local uf = plate.UnitFrame
    if not uf then return nil end
    if uf.healthBar then return uf.healthBar end
    if uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar then return uf.HealthBarsContainer.healthBar end
    if uf.HealthBar then return uf.HealthBar end
    return nil
end

-- Runde Combopunkte im Blizzard-Stil (nimmt die Grafik, die dein Client hat)
local function AtlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local ATLAS_PAIRS = {
    { on = "uf-roguecp-icon-red",     off = "uf-roguecp-bg" },
    { on = "UF-RogueCP-Icon-Red",     off = "UF-RogueCP-BG" },
    { on = "ClassOverlay-ComboPoint", off = "ClassOverlay-ComboPoint-Off" },
    { on = "ComboPoints-ComboPoint",  off = "ComboPoints-PointBg" },
}
local atlasOn, atlasOff
for _, pair in ipairs(ATLAS_PAIRS) do
    if AtlasExists(pair.on) then
        atlasOn = pair.on
        atlasOff = AtlasExists(pair.off) and pair.off or nil
        break
    end
end

tf.pips = {}
local PIP, GAP = 18, 2
local rowWidth = MAX_COMBO * PIP + (MAX_COMBO - 1) * GAP
for i = 1, MAX_COMBO do
    local holder = CreateFrame("Frame", nil, tf)
    holder:SetSize(PIP, PIP)
    holder:SetPoint("BOTTOMLEFT", tf, "BOTTOM", -rowWidth / 2 + (i - 1) * (PIP + GAP), 0)

    local off = holder:CreateTexture(nil, "BORDER")
    off:SetAllPoints()
    local on = holder:CreateTexture(nil, "ARTWORK")
    on:SetAllPoints()

    if atlasOn then
        on:SetAtlas(atlasOn)
        if atlasOff then
            off:SetAtlas(atlasOff)
        else
            off:SetAtlas(atlasOn)
            off:SetDesaturated(true)
            off:SetVertexColor(0.35, 0.35, 0.35)
        end
    else
        -- Ersatz: runde Kugeln (rot glänzend / dunkel)
        off:SetColorTexture(0.12, 0.12, 0.12)
        on:SetColorTexture(1, 0.2, 0.1)
        local mask = holder:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints()
        off:AddMaskTexture(mask)
        on:AddMaskTexture(mask)
    end

    holder.on = on
    holder:Hide()
    tf.pips[i] = holder
end

local function UpdateCombo()
    local cp = GetCombo()
    if isSecret(cp) then cp = 0 end
    for i = 1, MAX_COMBO do
        local p = tf.pips[i]
        if cp == 0 then
            p:Hide()
        else
            p:Show()
            p.on:SetShown(i <= cp)
        end
    end
end

local function UpdateTargetHealth()
    local cur, max = UnitHealth("target"), UnitHealthMax("target")
    if isSecret(cur) or isSecret(max) then
        -- Neuere Clients geben geschützte Werte zurück: nur anzeigen, nicht rechnen
        local pct = UnitHealthPercent and UnitHealthPercent("target", true, CurveConstants and CurveConstants.ScaleTo100)
        if pct ~= nil then
            tf.hp:SetText(string.format("%s / %s  (%.0f%%)", cur, max, pct))
        else
            tf.hp:SetText(string.format("%s / %s", cur, max))
        end
        tf.hp:SetTextColor(1, 1, 1)
        return
    end
    if not max or max <= 0 then tf.hp:SetText("") return end
    local pct = cur / max
    tf.hp:SetText(string.format("%d / %d  (%d%%)", cur, max, math.floor(pct * 100 + 0.5)))
    tf.hp:SetTextColor(HealthColor(pct))
end

------------------------------------------------------------
-- Eigene Energieleiste (über dem Namen des Gegners)
------------------------------------------------------------
-- an hpf gehängt (nicht an tf), damit die Energieleiste 100% Deckkraft hat
local eb = CreateFrame("StatusBar", "SchurkenHUDEnergy", hpf)
eb:SetSize(100, 9)
eb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
eb:SetStatusBarColor(1, 0.85, 0.1)
eb:SetMinMaxValues(0, 100)
eb:SetValue(100)

eb.bg = eb:CreateTexture(nil, "BACKGROUND")
eb.bg:SetPoint("TOPLEFT", -1, 1)
eb.bg:SetPoint("BOTTOMRIGHT", 1, -1)
eb.bg:SetColorTexture(0, 0, 0, 0.7)

eb.text = eb:CreateFontString(nil, "OVERLAY")
eb.text:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
eb.text:SetPoint("CENTER", 0, 0)

local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

local function UpdateEnergy()
    local cur, max = UnitPower("player", ENERGY), UnitPowerMax("player", ENERGY)
    eb:SetMinMaxValues(0, max)
    eb:SetValue(cur)
    eb.text:SetText(string.format("%s", cur))
end

-- Ganze Gegner-Plakette (Name, Leben + unsere Anzeigen) näher ans NPC schieben
local function OffsetPlate(plate)
    local uf = plate and plate.UnitFrame
    if not uf then return end
    local off = db.plateOffset or 0
    pcall(function()
        uf:ClearAllPoints()
        uf:SetPoint("TOPLEFT", plate, "TOPLEFT", 0, -off)
        uf:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", 0, -off)
    end)
end

local function OffsetUnitPlate(unit)
    if unit and UnitCanAttack("player", unit) and GetNamePlateForUnit then
        OffsetPlate(GetNamePlateForUnit(unit))
    end
end

local currentPlate

local function AnchorTarget()
    if not UnitExists("target") or UnitIsDeadOrGhost("target") or not UnitCanAttack("player", "target") then
        currentPlate = nil
        tf:Hide()
        return
    end
    local plate = GetNamePlateForUnit and GetNamePlateForUnit("target")
    if not plate then
        currentPlate = nil
        tf:Hide()
        return
    end
    currentPlate = plate
    OffsetPlate(plate)
    tf:ClearAllPoints()
    -- Combopunkte direkt über der Energieleiste
    tf:SetPoint("BOTTOM", eb, "TOP", 0, 1)

    -- Energieleiste zwischen Name und Combopunkten
    local uf = plate.UnitFrame
    local nameText = uf and (uf.name or uf.Name)
    local hasName = false
    if nameText and nameText:IsShown() then
        local t = nameText:GetText()
        hasName = isSecret(t) or (t ~= nil and t ~= "")
    end
    local hb = FindHealthBar(plate)
    local w = hb and hb:GetWidth() or 0
    if isSecret(w) or w < 40 then w = 100 end
    eb:SetWidth(w)
    eb:ClearAllPoints()
    if hasName then
        eb:SetPoint("BOTTOM", nameText, "TOP", 0, 2)
    elseif hb then
        eb:SetPoint("BOTTOM", hb, "TOP", 0, 14)
    else
        eb:SetPoint("BOTTOM", plate, "TOP", 0, -8)
    end
    Safe("Energie", UpdateEnergy)
    local bar = FindHealthBar(plate)
    hpf:ClearAllPoints()
    if bar then
        hpf:SetPoint("CENTER", bar, "CENTER", 0, 0)
    else
        hpf:SetPoint("CENTER", plate, "CENTER", 0, 0)
    end
    tf:Show()
    Safe("Gegner-Leben", UpdateTargetHealth)
    Safe("Combopunkte", UpdateCombo)
end

------------------------------------------------------------
-- Eigener Lebensbalken
------------------------------------------------------------
local pb = CreateFrame("StatusBar", "SchurkenHUDPlayer", UIParent)
pb:SetSize(110, 11)
pb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
pb:SetStatusBarColor(0.1, 0.9, 0.1)
pb:SetMinMaxValues(0, 1)
pb:SetValue(1)
pb:SetFrameStrata("MEDIUM")
pb:SetMovable(true)
pb:SetClampedToScreen(true)
pb:EnableMouse(false)
pb:RegisterForDrag("LeftButton")
pb:Hide()

pb.bg = pb:CreateTexture(nil, "BACKGROUND")
pb.bg:SetPoint("TOPLEFT", -1, 1)
pb.bg:SetPoint("BOTTOMRIGHT", 1, -1)
pb.bg:SetColorTexture(0, 0, 0, 0.6)

pb.text = pb:CreateFontString(nil, "OVERLAY")
pb.text:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
pb.text:SetPoint("CENTER")

local unlocked = false

local function UpdatePlayer()
    local cur, max = UnitHealth("player"), UnitHealthMax("player")
    pb:SetMinMaxValues(0, max)
    pb:SetValue(cur)
    pb.text:SetText(string.format("%s / %s", cur, max))
    if not isSecret(cur) and not isSecret(max) and max > 0 then
        pb:SetStatusBarColor(HealthColor(cur / max))
    end
end

local function UpdatePlayerVisibility()
    if unlocked or UnitAffectingCombat("player") then
        Safe("Spieler-Leben", UpdatePlayer)
        pb:Show()
    else
        pb:Hide()
    end
end

local function ApplyPosition()
    pb:ClearAllPoints()
    pb:SetPoint(db.point, UIParent, db.point, db.x, db.y)
end
ApplyPosition()

pb:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
pb:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    db.point, db.x, db.y = point, x, y
end)

------------------------------------------------------------
-- Regelmäßige Aktualisierung (Absicherung, falls Events fehlen)
------------------------------------------------------------
local elapsedTotal = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < 0.1 then return end
    elapsedTotal = 0
    local plate = UnitExists("target") and GetNamePlateForUnit and GetNamePlateForUnit("target")
    if plate ~= currentPlate or (plate and not tf:IsShown()) then
        Safe("Anzeige", AnchorTarget)
    elseif tf:IsShown() then
        Safe("Gegner-Leben", UpdateTargetHealth)
        Safe("Combopunkte", UpdateCombo)
        Safe("Energie", UpdateEnergy)
    end
    if pb:IsShown() then Safe("Spieler-Leben", UpdatePlayer) end
end)

------------------------------------------------------------
-- Events
------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_TARGET_CHANGED",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}) do pcall(ev.RegisterEvent, ev, e) end

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "SchurkenHUD" then
            SchurkenHUDDB = SchurkenHUDDB or {}
            db = SchurkenHUDDB
            -- alte Standardposition (y=70) auf die neue, tiefere umstellen
            if not db.v then
                if db.point == "CENTER" and db.x == 0 and db.y == 70 then db.y = defaults.y end
                db.v = 2
            end
            for k, v in pairs(defaults) do if db[k] == nil then db[k] = v end end
            ApplyPosition()
        end
    elseif event == "PLAYER_LOGIN" then
        Msg("geladen. /shud test zeigt den Lebensbalken zum Ausrichten.")
        UpdatePlayerVisibility()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        UpdatePlayerVisibility()
    else
        if event == "NAME_PLATE_UNIT_ADDED" then OffsetUnitPlate(arg1) end
        Safe("Anzeige", AnchorTarget)
    end
end)

------------------------------------------------------------
-- Slash-Befehle
------------------------------------------------------------
SLASH_SCHURKENHUD1 = "/shud"
SlashCmdList.SCHURKENHUD = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "unlock" or msg == "test" then
        unlocked = true
        pb:EnableMouse(true)
        Msg("Lebensbalken sichtbar – mit linker Maustaste ziehen. /shud lock zum Fixieren.")
        local plate = UnitExists("target") and GetNamePlateForUnit and GetNamePlateForUnit("target")
        Msg("Combopunkt-Grafik: " .. (atlasOn or "Ersatz-Kugeln"))
        Msg("Ziel: " .. (UnitExists("target") and "ja" or "nein") .. ", Namensplakette gefunden: " .. (plate and "ja" or "NEIN (Taste V drücken)"))
    elseif msg == "lock" then
        unlocked = false
        pb:EnableMouse(false)
        Msg("Lebensbalken fixiert.")
    elseif msg:match("^nah") then
        local n = tonumber(msg:match("(%-?%d+)"))
        if n then
            db.plateOffset = n
            Msg("Gegner-Anzeige " .. n .. " Pixel nach unten verschoben (näher ans NPC). Bei neuen Gegnern sofort aktiv.")
            Safe("Anzeige", AnchorTarget)
        else
            Msg("Aktuell: " .. (db.plateOffset or 0) .. " Pixel. Beispiel: /shud nah 30")
        end
    elseif msg == "reset" then
        db.point, db.x, db.y = defaults.point, defaults.x, defaults.y
        ApplyPosition()
        Msg("Position zurückgesetzt.")
    else
        Msg("/shud unlock | lock | reset | test | nah <Pixel>")
    end
    UpdatePlayerVisibility()
end
