macroScript Backgrounder
category:"Physicl"
tooltip:"Physicl Asset Browser: backplates and decals from the Knowledge Hub"
buttontext:"Asset Browser"
(
    -- KH_Client.ms and Backrounder_UI.ms are installed next to this macro in userMacros
    local dir = (getDir #userMacros) + "\\"
    if not doesFileExist (dir + "Backrounder_UI.ms") do (
        local here = getSourceFileName()
        if here != undefined do dir = getFilenamePath here
    )
    if doesFileExist (dir + "KH_Client.ms") and doesFileExist (dir + "Backrounder_UI.ms") then (
        fileIn (dir + "KH_Client.ms")
        fileIn (dir + "Backrounder_UI.ms")
        ::BR_open()
    ) else (
        messageBox "Backrounder files not found.\nReinstall Backrounder (Run_Background_Importer.ms)." title:"Backrounder"
    )
)
