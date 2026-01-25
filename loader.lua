local PlaceId = game.PlaceId 
local Game_ViolenceDistrict = 93978595733734 
local Game_PoopAbigPoop = 85050171250159      

print("Terdeteksi Place ID: " .. PlaceId)

if PlaceId == Game_ViolenceDistrict then
    print("Loading Script Violence District...")
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Dhammmm11/violence-district/main/main.lua"))()

elseif PlaceId == Game_PoopAbigPoop then
    print("Loading Script Poop Game...")
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Dhammmm11/poop-a-big-poop-script/main/source.lua"))()

else
    print("Game tidak terdaftar di Hub. Memuat Universal Script...")
    loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
end
