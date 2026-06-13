local GameScripts = {

    [93978595733734] = "https://raw.githubusercontent.com/Dhammmm11/violence-district/main/main.lua",
    [85050171250159] = "https://raw.githubusercontent.com/Dhammmm11/poop-a-big-poop-script/main/source.lua"
    [122446657157717] = "https://raw.githubusercontent.com/Dhammmm11/sniperarena/refs/heads/main/main.lua"
}

local PlaceId = game.PlaceId
local scriptUrl = GameScripts[PlaceId]

print("-------------------------------------")
print("Place ID Saat Ini: " .. PlaceId) 

if scriptUrl then
    print("✅ Game Terdaftar! Memuat Script...")    
    local success, err = pcall(function()
        loadstring(game:HttpGet(scriptUrl))()
    end)

    if not success then
        warn("⚠️ Gagal memuat script! Link mungkin mati atau salah.")
        print("Error: " .. tostring(err))
    end
else
    print("⚠️ Game tidak terdaftar di list.")
    print("Memuat Universal Script (Infinite Yield)...")
    loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
end
