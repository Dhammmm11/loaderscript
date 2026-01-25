local PlaceId = game.PlaceId
local Game_ViolenceDistrict = 93978595733734 
local Game_PoopABigPoop = 85050171250159      

print("-------------------------------------")
print("Place ID Saat Ini: " .. PlaceId) 
print("-------------------------------------")

if PlaceId == Game_ViolenceDistrict then
    print("✅ Loading Script Violence District...")
    
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Dhammmm11/violence-district/main/main.lua"))()

elseif PlaceId == Game_PoopABigPoop then
    print("✅ Loading Script Poop a Big Poop...")
  
    loadstring(game:HttpGet("https://raw.githubusercontent.com/Dhammmm11/poop-a-big-poop-script/main/source.lua"))()

else
    print("⚠️ Game tidak terdaftar (ID: " .. PlaceId .. ")")
    print("Memuat Universal Script (Infinite Yield)...")
    
    loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
end
