-- Nfinite Background Importer Installer
-- Automatic installation of Background Importer script

(
    -- Define installation paths
    local userMacroDir = getDir #userMacros
    local sourceDir = getFilenamePath (getThisScriptFilename())
    local version = "v1.0"
    
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
    format "\n=== NFINITE BACKGROUND IMPORTER % INSTALLER ===\n" version
    format "Starting installation...\n\n"
    
    local installSuccess = true
    local installedCount = 0
    
    -- 1. Install main files (script and library)
    local mainFiles = #(
        "Background_Importer.mcr",
        "Background_example.max"
    )
    
    for fName in mainFiles do (
        if installFile (sourceDir + fName) (userMacroDir + "\\" + fName) then 
            installedCount += 1
        else
            installSuccess = false
    )
    
    -- 2. Install textures (all Background_*.png files in root)
    -- We look for Background_*.png pattern to capture _D, _A, _N etc.
    local textureFiles = getFiles (sourceDir + "Background_*.png")
    
    format "Textures found for installation: %\n" textureFiles.count
    
    for fPath in textureFiles do (
        local fName = filenameFromPath fPath
        -- Skip previews if they accidentally matched the mask (though they are usually in Previews folder)
        if installFile fPath (userMacroDir + "\\" + fName) then
            installedCount += 1
        else
            installSuccess = false
    )
    
    -- 3. Install Preview images (Previews folder)
    local previewDirSrc = sourceDir + "Previews\\"
    local previewDirDst = userMacroDir + "\\Previews\\"
    
    if doesDirectoryExist previewDirSrc then (
        -- Create target directory if it doesn't exist
        if not doesDirectoryExist previewDirDst do makeDir previewDirDst
        
        local previewFiles = getFiles (previewDirSrc + "*.png")
        local jpgPreviews = getFiles (previewDirSrc + "*.jpg")
        join previewFiles jpgPreviews -- Merge lists (just in case jpgs exist)
        
        format "Previews found for installation: %\n" previewFiles.count
        
        for fPath in previewFiles do (
            local fName = filenameFromPath fPath
            if installFile fPath (previewDirDst + fName) then
                installedCount += 1
            else
                installSuccess = false
        )
    ) else (
        format "WARNING: Previews folder not found in %\n" sourceDir
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
        
        messageBox ("Nfinite Background Importer " + version + " successfully installed!\n\n" + \
                   "Script available in:\n" + \
                   "Customize → Customize User Interface → Toolbars\n" + \
                   "Category: Nfinite\n\n" + \
                   "All resources copied to: " + userMacroDir) \
                   title:"Installation and Setup" beep:false
    )
    else
    (
        format "\n=== INSTALLATION ERROR ===\n"
        messageBox ("Error installing Nfinite Background Importer " + version + "\n\n" + \
                   "Check MAXScript Listener (F11) for details.") \
                   title:"Installation Error" beep:true
    )
)
