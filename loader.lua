local GameScripts = {
    [93978595733734] = "https://raw.githubusercontent.com/Dhammmm11/violence-district/main/main.lua",
    [85050171250159] = "https://raw.githubusercontent.com/Dhammmm11/poop-a-big-poop-script/main/source.lua",
    [122446657157717] = "https://raw.githubusercontent.com/Dhammmm11/sniperarena/main/main.lua",
    [119661268047775] = "https://raw.githubusercontent.com/Dhammmm11/sniperarena/main/main.lua",
    [126042865144779] = "https://raw.githubusercontent.com/Dhammmm11/sniperarena/main/main.lua",
}

local PlaceId = game.PlaceId
local scriptUrl = GameScripts[PlaceId]

print("-------------------------------------")
print("Place ID Saat Ini: " .. tostring(PlaceId))
print("Resolved scriptUrl: " .. tostring(scriptUrl))

-- Fungsi untuk validasi dan load script
local function loadScriptFromUrl(url)
    if not url or url == "" then
        return false, "URL kosong"
    end
    
    -- Fetch script content
    local success, body = pcall(function() 
        return game:HttpGet(url, true) -- true = no cache
    end)
    
    if not success then
        return false, "HttpGet error: " .. tostring(body)
    end
    
    if not body or body == "" then
        return false, "Script body kosong dari URL: " .. url
    end
    
    -- Check jika response adalah HTML error (bukan Lua script)
    if body:match("<!DOCTYPE") or body:match("<html") or body:match("404") then
        return false, "URL mengembalikan HTML/error page, bukan Lua script. Check URL: " .. url
    end
    
    print("📥 Script body length: " .. #body .. " bytes")
    
    -- Attempt loadstring
    local fn, loadErr = loadstring(body)
    if not fn then
        return false, "loadstring gagal: " .. tostring(loadErr)
    end
    
    print("✅ loadstring berhasil, menjalankan script...")
    
    -- Execute script
    local execOk, execErr = pcall(fn)
    if not execOk then
        return false, "Script execution error: " .. tostring(execErr)
    end
    
    return true, "Script loaded successfully"
end

if scriptUrl and type(scriptUrl) == "string" and scriptUrl ~= "" then
    print("✅ Game Terdaftar! Memuat Script...")    
    local ok, msg = loadScriptFromUrl(scriptUrl)
    
    if not ok then
        warn("⚠️ Gagal memuat script! " .. tostring(msg))
    end
else
    print("⚠️ Game tidak terdaftar di list.")
    print("Memuat Universal Script (Infinite Yield)...")
    
    local ok, msg = loadScriptFromUrl("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source")
    if not ok then 
        warn("Gagal memuat universal script: " .. tostring(msg)) 
    end
end
