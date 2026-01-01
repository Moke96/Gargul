local L = Gargul_L;
local _, GL = ...;

local AceGUI = GL.AceGUI;
local ScrollingTable = GL.ScrollingTable;

---@class RollObserverUI
local RollObserverUI = {
    Window = nil,
    Table = nil,
    HistoryScroll = nil,
    filterSR = false,
    history = {},
};
GL.RollObserverUI = RollObserverUI;

function RollObserverUI:_init()
    GL.Events:register("RollObserverUI_Start", "GL.ROLLOFF_STARTED", function()
        self:addCurrentRollToHistory();
        self:show();
        self:update();
    end);
    
    GL.Events:register("RollObserverUI_Roll", "GL.ROLLOFF_ROLL_ACCEPTED", function()
        self:update();
    end);
end

function RollObserverUI:addCurrentRollToHistory()
    local current = GL.RollOff.CurrentRollOff;
    if (not current or not current.itemLink) then return; end
    
    -- Try to fetch info if missing (e.g. during announceStart)
    local name, link, quality, level, minLevel, type, subType, stackCount, equipLoc, icon = GetItemInfo(current.itemLink);
    local itemName = current.itemName or name;
    local itemIcon = current.itemIcon or icon;
    local itemID = current.itemID or (link and string.match(link, "item:(%d+)"));
    
    -- Check for duplicate/update
    if (#self.history > 0) then
        local last = self.history[1];
        local lastID = last.itemLink and string.match(last.itemLink, "item:(%d+)");
        local currentID = itemID or (current.itemLink and string.match(current.itemLink, "item:(%d+)"));
        
        -- Match by Link or ID. 
        -- We use a 10s window because announceStart and start happen close together.
        if ((last.itemLink == current.itemLink or (lastID and currentID and lastID == currentID)) 
            and last.timestamp > GetTime() - 10) then
            
            -- Update info if we have better info now
            if (itemName and (not last.itemName or last.itemName == "Unknown")) then last.itemName = itemName; end
            if (itemIcon and not last.itemIcon) then last.itemIcon = itemIcon; end
            
            -- Update rolls reference (crucial if the table was recreated)
            last.rolls = current.Rolls; 
            
            self:updateHistoryList();
            return;
        end
    end

    local entry = {
        itemLink = current.itemLink,
        itemIcon = itemIcon,
        itemName = itemName,
        rolls = current.Rolls, -- Reference to the table being filled
        timestamp = GetTime(),
    };
    
    table.insert(self.history, 1, entry);
    self:updateHistoryList();
end

function RollObserverUI:show()
    if (not self.Window) then
        self:draw();
    end
    self.Window:Show();
end

function RollObserverUI:hide()
    if (self.Window) then
        self.Window:Hide();
    end
end

function RollObserverUI:draw()
    local Window = AceGUI:Create("Frame");
    Window:SetTitle("Gargul Roll Observer");
    Window:SetLayout("Flow");
    Window:SetWidth(600); -- Wider to accommodate history
    Window:SetHeight(400);
    Window:SetCallback("OnClose", function()
        self.Window = nil;
        self.Table = nil;
        self.HistoryScroll = nil;
        self.ItemIcon = nil;
    end);
    self.Window = Window;

    -- Main Container (Horizontal Split)
    local MainGroup = AceGUI:Create("SimpleGroup");
    MainGroup:SetLayout("Flow");
    MainGroup:SetFullWidth(true);
    MainGroup:SetFullHeight(true);
    Window:AddChild(MainGroup);

    -- Left Side: History List (25% width)
    local HistoryGroup = AceGUI:Create("SimpleGroup");
    HistoryGroup:SetLayout("Fill");
    HistoryGroup:SetWidth(140);
    HistoryGroup:SetHeight(330);
    MainGroup:AddChild(HistoryGroup);

    local HistoryScroll = AceGUI:Create("ScrollFrame");
    HistoryScroll:SetLayout("List");
    HistoryGroup:AddChild(HistoryScroll);
    self.HistoryScroll = HistoryScroll;

    -- Right Side: Current Roll (75% width)
    local CurrentRollGroup = AceGUI:Create("SimpleGroup");
    CurrentRollGroup:SetLayout("Flow");
    CurrentRollGroup:SetWidth(420);
    CurrentRollGroup:SetHeight(330);
    MainGroup:AddChild(CurrentRollGroup);

    -- Header for Current Roll
    local Header = AceGUI:Create("SimpleGroup");
    Header:SetLayout("Flow");
    Header:SetFullWidth(true);
    Header:SetHeight(60); -- Increased height for icon + label
    CurrentRollGroup:AddChild(Header);

    -- Item Icon
    local ItemIcon = AceGUI:Create("Icon");
    ItemIcon:SetImageSize(30, 30);
    ItemIcon:SetWidth(200); -- Wider for text
    ItemIcon:SetImage("Interface/Icons/INV_Misc_QuestionMark");
    ItemIcon:SetLabel("Waiting for roll...");
    
    ItemIcon:SetCallback("OnEnter", function()
        local itemLink = GL.RollOff.CurrentRollOff.itemLink;
        if (itemLink) then
            GameTooltip:SetOwner(ItemIcon.frame, "ANCHOR_TOP");
            GameTooltip:SetHyperlink(itemLink);
            GameTooltip:Show();
        end
    end);
    ItemIcon:SetCallback("OnLeave", function()
        GameTooltip:Hide();
    end);
    ItemIcon:SetCallback("OnClick", function()
        local itemLink = GL.RollOff.CurrentRollOff.itemLink;
        if (itemLink) then
             HandleModifiedItemClick(itemLink);
        end
    end);

    Header:AddChild(ItemIcon);
    self.ItemIcon = ItemIcon;

    -- Filter Checkbox
    local FilterSR = AceGUI:Create("CheckBox");
    FilterSR:SetLabel("Filter SR");
    FilterSR:SetWidth(100);
    FilterSR:SetValue(self.filterSR);
    FilterSR:SetCallback("OnValueChanged", function(_, _, value)
        self.filterSR = value;
        self:update();
    end);
    Header:AddChild(FilterSR);
    
    -- ScrollingTable for Current Roll
    local columns = {
        { name = "Player", width = 120 },
        { name = "Roll", width = 50, sort = GL.Data.Constants.ScrollingTable.descending },
        { name = "SR", width = 50 },
    };
    
    -- We need a container for the ST because it needs an absolute frame parent usually, 
    -- or we attach it to the CurrentRollGroup's content
    local TableContainer = AceGUI:Create("SimpleGroup");
    TableContainer:SetLayout("Fill");
    TableContainer:SetFullWidth(true);
    TableContainer:SetHeight(280);
    CurrentRollGroup:AddChild(TableContainer);

    local Table = ScrollingTable:CreateST(columns, 12, 20, nil, TableContainer.frame);
    Table.frame:SetPoint("TOPLEFT", TableContainer.frame, "TOPLEFT", 0, 0);
    Table.frame:SetPoint("BOTTOMRIGHT", TableContainer.frame, "BOTTOMRIGHT", 0, 0);
    Table:EnableSelection(true);
    self.Table = Table;

    self:updateHistoryList();
    self:update();
end

function RollObserverUI:updateHistoryList()
    if (not self.HistoryScroll) then return; end
    self.HistoryScroll:ReleaseChildren();
    
    for _, entry in ipairs(self.history) do
        self:createHistoryRow(entry);
    end
end

function RollObserverUI:createHistoryRow(entry)
    local Group = AceGUI:Create("SimpleGroup");
    Group:SetLayout("Flow");
    Group:SetFullWidth(true);
    
    -- Icon
    local Icon = AceGUI:Create("Icon");
    Icon:SetImage(entry.itemIcon or "Interface/Icons/INV_Misc_QuestionMark");
    Icon:SetImageSize(20, 20);
    Icon:SetWidth(30);
    Group:AddChild(Icon);
    
    -- Label
    local Label = AceGUI:Create("Label");
    local name = entry.itemName or "Unknown";
    if (#name > 8) then
        name = string.sub(name, 1, 8) .. "..";
    end
    Label:SetText(name);
    Label:SetWidth(90);
    Group:AddChild(Label);
    
    -- Tooltip logic
    local onEnter = function(widget)
        GameTooltip:SetOwner(widget.frame or widget, "ANCHOR_RIGHT");
        GameTooltip:SetHyperlink(entry.itemLink);
        GameTooltip:AddLine(" ");
        GameTooltip:AddLine("Rolls:", 1, 1, 1);
        
        -- Sort and Filter rolls
        local sortedRolls = {};
        for _, roll in pairs(entry.rolls) do
            table.insert(sortedRolls, roll);
        end
        table.sort(sortedRolls, function(a, b) return (a.amount or 0) > (b.amount or 0) end);
        
        -- Get SR info
        local reservers = {};
        local reserverNames = GL.SoftRes:byItemLink(entry.itemLink) or {};
        for _, n in pairs(reserverNames) do
            reservers[n] = true;
            reservers[GL:stripRealm(n)] = true;
        end
        
        for _, roll in ipairs(sortedRolls) do
            local isSR = reservers[roll.player] or reservers[GL:stripRealm(roll.player)];
            if (not self.filterSR or isSR) then
                local text = string.format("%s: %d", roll.player, roll.amount);
                if (isSR) then text = text .. " |cFF00FF00(SR)|r"; end
                
                local isMe = (roll.player == GL.User.name) or (roll.player == GL.User.fqn) or (GL:stripRealm(roll.player) == GL.User.name);
                if (isMe) then
                    text = string.gsub(text, roll.player, "|cFF00FF00" .. roll.player .. "|r");
                end
                
                GameTooltip:AddLine(text);
            end
        end
        
        GameTooltip:Show();
    end
    
    local onLeave = function()
        GameTooltip:Hide();
    end
    
    Icon:SetCallback("OnEnter", onEnter);
    Icon:SetCallback("OnLeave", onLeave);
    
    -- For Label, we attach to the frame
    if (Label.frame) then
        Label.frame:SetScript("OnEnter", function() onEnter(Label) end);
        Label.frame:SetScript("OnLeave", onLeave);
        Label.frame:EnableMouse(true);
    end
    
    self.HistoryScroll:AddChild(Group);
end

function RollObserverUI:update()
    if (not self.Table) then return; end
    
    local rolls = GL.RollOff.CurrentRollOff.Rolls or {};
    local itemLink = GL.RollOff.CurrentRollOff.itemLink;
    
    -- Fetch info directly from link to ensure freshness (fixes stale icon issue)
    local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemLink or "");
    
    -- Fallback to CurrentRollOff properties if GetItemInfo fails (or link is nil)
    if (not itemIcon) then itemIcon = GL.RollOff.CurrentRollOff.itemIcon or "Interface/Icons/INV_Misc_QuestionMark"; end
    if (not itemName) then itemName = GL.RollOff.CurrentRollOff.itemName or "Unknown"; end

    if (self.ItemIcon) then
        self.ItemIcon:SetImage(itemIcon);
        self.ItemIcon:SetLabel(itemName);
    end

    -- Update history entry if it matches current roll (to fix stale info)
    if (#self.history > 0 and itemLink) then
        local latest = self.history[1];
        if (latest.itemLink == itemLink) then
             local changed = false;
             if (itemName and itemName ~= "Unknown" and latest.itemName ~= itemName) then
                 latest.itemName = itemName;
                 changed = true;
             end
             if (itemIcon and itemIcon ~= "Interface/Icons/INV_Misc_QuestionMark" and latest.itemIcon ~= itemIcon) then
                 latest.itemIcon = itemIcon;
                 changed = true;
             end
             
             if (changed) then
                 self:updateHistoryList();
             end
        end
    end
    
    local reservers = {};
    if (itemLink) then
        local reserverNames = GL.SoftRes:byItemLink(itemLink) or {};
        for _, name in pairs(reserverNames) do
            reservers[name] = true;
            reservers[GL:stripRealm(name)] = true;
        end
    end
    
    local data = {};
    for _, roll in pairs(rolls) do
        local player = roll.player;
        local amount = roll.amount;
        local isSR = reservers[player] or reservers[GL:stripRealm(player)];
        
        local isMe = (player == GL.User.name) or (player == GL.User.fqn) or (GL:stripRealm(player) == GL.User.name);
        local color = isMe and {r=0, g=1, b=0, a=1} or nil;

        if (not self.filterSR or isSR) then
            table.insert(data, {
                cols = {
                    { value = player, color = color },
                    { value = amount, color = color },
                    { value = isSR and "Yes" or "", color = color },
                }
            });
        end
    end
    
    self.Table:SetData(data);

    -- Ensure we have a default sort if none is selected
    local hasSort = false;
    for _, col in pairs(self.Table.cols) do
        if (col.sort) then
            hasSort = true;
            break;
        end
    end

    if (not hasSort) then
        self.Table.cols[2].sort = GL.Data.Constants.ScrollingTable.descending;
        self.Table:SortData();
    end
end
