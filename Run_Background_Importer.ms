-- Physicl Background Importer Installer
-- Automatic installation of Background Importer script

(
    -- Define installation paths
    local userMacroDir = getDir #userMacros
    local sourceDir = getFilenamePath (getThisScriptFilename())
    local version = "v2.0"
    
    -- Function to copy files (similar to Bulb Fixer)
    fn installFile sourcePath targetPath = 
    (
        if doesFileExist sourcePath then
        (
            -- If target file exists, we need to remove it
            if doesFileExist targetPath then
            (
                -- 1. Try to delete
                local deleteResult = deleteFile targetPath
                
                if deleteResult then (
                    format "Old file deleted: %\n" targetPath
                ) else (
                    -- 2. If delete failed (locked), try to rename
                    format "Could not delete file (file may be in use), attempting to rename: %\n" targetPath
                    
                    -- Generate unique backup name
                    local timeStr = substituteString ((getLocalTime()) as string) ":" "-"
                    timeStr = substituteString timeStr " " "_"
                    timeStr = substituteString timeStr "." "_"
                    local backupPath = targetPath + ".old_" + timeStr
                    
                    if renameFile targetPath backupPath then (
                        format "File successfully renamed to: %\n" backupPath
                    ) else (
                        format "CRITICAL ERROR: Unable to overwrite file: %\n" targetPath
                        return false
                    )
                )
            )
            
            -- Copy new file
            if copyFile sourcePath targetPath then
            (
                format "Installed: %\n" targetPath
                return true
            )
            else
            (
                format "ERROR: Failed to copy %\n" (filenameFromPath sourcePath)
                return false
            )
        )
        else
        (
            format "ERROR: Source file not found: %\n" sourcePath
            return false
        )
    )
    
    -- Start installation
    format "\n=== PHYSICL BACKGROUND IMPORTER % INSTALLER ===\n" version
    format "Starting installation...\n\n"
    
    local installSuccess = true
    local installedCount = 0
    
    -- 1. Install the script and the Knowledge Hub client.
    -- Backgrounds, previews and textures now come from the Knowledge Hub at runtime.
    local mainFiles = #(
        "Background_Importer.mcr",
        "KH_Client.ms",
        "Backrounder_UI.ms"
    )
    
    for fName in mainFiles do (
        if installFile (sourceDir + fName) (userMacroDir + "\\" + fName) then 
            installedCount += 1
        else
            installSuccess = false
    )
    
    -- Completion
    if installSuccess then
    (
        format "\nReloading macros...\n"
        
        -- Attempt to load macro
        try (
            macros.load (userMacroDir + "\\Background_Importer.mcr")
        ) catch (
            format "Error loading macro. Please restart 3ds Max.\n"
        )
        
        format "\n=== INSTALLATION COMPLETED SUCCESSFULLY ===\n"
        format "Total files installed: %\n" installedCount
        
        messageBox ("Physicl Background Importer " + version + " successfully installed!\n\n" + \
                   "Script available in:\n" + \
                   "Customize → Customize User Interface → Toolbars\n" + \
                   "Category: Physicl\n\n" + \
                   "All resources copied to: " + userMacroDir) \
                   title:"Installation and Setup" beep:false
    )
    else
    (
        format "\n=== INSTALLATION ERROR ===\n"
        messageBox ("Error installing Physicl Background Importer " + version + "\n\n" + \
                   "Check MAXScript Listener (F11) for details.") \
                   title:"Installation Error" beep:true
    )
)
