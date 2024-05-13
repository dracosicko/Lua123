local OrionLib = loadstring(game:HttpGet(('https://raw.githubusercontent.com/shlexware/Orion/main/source')))()
local Window = OrionLib:MakeWindow({Name = "menatality.xyz (script hub), HidePremium = false, SaveConfig = true, ConfigFolder = "OrionTest"})

local Tab = Window:MakeTab({
	Name = "Arsenal",
	Icon = "rbxassetid://4483345998",
	PremiumOnly = false
})

local Section = Tab:AddSection({
	Name = "Arsenal scripts"
})

Tab:AddButton({
	Name = "Leg Hub",
	Callback = function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/cris123452/my/main/cas",true))()
  	end    
})

Tab:AddButton({
	Name = "Leg Hub",
	Callback = function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/cris123452/my/main/cas",true))()
  	end    
})
