local GameScripts = {
    [93978595733734] = "https://raw.githubusercontent.com/Dhammmm11/violence-district/main/main.lua",
    [85050171250159] = "https://raw.githubusercontent.com/Dhammmm11/poop-a-big-poop-script/main/source.lua",
    [122446657157717,119661268047775] = "https://raw.githubusercontent.com/Dhammmm11/sniperarena/main/main.lua",
}

local PlaceId = game.PlaceId
local scriptUrl = GameScripts[PlaceId]

print("-------------------------------------")
print("Place ID Saat Ini: " .. tostring(PlaceId))
print("Resolved scriptUrl: " .. tostring(scriptUrl))

if scriptUrl and type(scriptUrl) == "string" and scriptUrl ~= "" then
    print("✅ Game Terdaftar! Memuat Script...")    
    local ok, err = pcall(function()
        -- pastikan HttpGet berhasil dan isi tidak kosong
        local success, body = pcall(function() return game:HttpGet(scriptUrl) end)
        if not success or not body or body == "" then
            error("HttpGet gagal atau body kosong untuk URL: " .. tostring(scriptUrl))
        end

        -- pastikan loadstring berhasil
        local fn, loadErr = loadstring(body)
        if not fn then
            error("loadstring gagal: " .. tostring(loadErr))
        end

        -- jalankan fungsi yang dimuat
        fn()
    end)

    if not ok then
        warn("⚠️ Gagal memuat script! " .. tostring(err))
    end
else
    print("⚠️ Game tidak terdaftar di list.")
    print("Memuat Universal Script (Infinite Yield)...")
    local ok, err = pcall(function()
        local body = game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source")
        local fn = loadstring(body)
        if not fn then error("loadstring InfiniteYield gagal") end
        fn()
    end)
    if not ok then warn("Gagal memuat universal script: " .. tostring(err)) end
end
