-- Daftar Game dan Script-nya (Format Table seperti punya temanmu)
local GameScripts = {
    -- [ID GAME] = "LINK SCRIPT"
    
    -- Violence District
    [93978595733734] = "https://raw.githubusercontent.com/Dhammmm11/violence-district/main/main.lua",
    
    -- Poop a Big Poop
    [85050171250159] = "https://raw.githubusercontent.com/Dhammmm11/poop-a-big-poop-script/main/source.lua"
}

-- == JANGAN UBAH KODE DI BAWAH INI == --

local PlaceId = game.PlaceId
local scriptUrl = GameScripts[PlaceId]

print("-------------------------------------")
print("Place ID Saat Ini: " .. PlaceId) 

if scriptUrl then
    print("✅ Game Terdaftar! Memuat Script...")
    -- Fungsi pcall untuk menangkap error jika link mati
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
