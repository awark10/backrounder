macroScript Backgrounder
category:"Nfinite"
tooltip:"Import Backgrounds"
buttontext:"BG Importer"
(
    -- ============================
    -- GLOBAL VARIABLES
    -- ============================
    local bgRollout
    
    -- ============================
    -- STRUCT: Background Manager
    -- ============================
    struct BackgroundManagerStruct (
        libraryPath = undefined,
        previewsPath = undefined,
        texturesPath = undefined,
        
        fn getLibraryPath = (
            local scriptPath = getSourceFileName()
            if scriptPath != undefined then (
                return (getFilenamePath scriptPath) + "Background_example.max"
            )
            return undefined
        ),
        
        fn getPreviewsPath = (
            local scriptPath = getSourceFileName()
            if scriptPath != undefined then (
                return (getFilenamePath scriptPath) + "Previews\\"
            )
            return undefined
        ),
        
        fn getTexturesPath = (
            -- Assuming textures are in the same folder as the script/library
            local scriptPath = getSourceFileName()
            if scriptPath != undefined then (
                return (getFilenamePath scriptPath)
            )
            return undefined
        ),
        
        fn getAvailableBackgrounds = (
            if libraryPath == undefined do libraryPath = getLibraryPath()
            
            if libraryPath != undefined and doesFileExist libraryPath then (
                local objNames = getMAXFileObjectNames libraryPath
                
                local filtered = #()
                for n in objNames do (
                    if matchPattern n pattern:"Background*" ignoreCase:true then (
                        append filtered n
                    )
                )
                sort filtered
                return filtered
            )
            return #()
        ),
        
        -- Function to copy and rename textures
        fn processTextures bgName obj = (
             if maxFilePath == "" then (
                 messageBox "Please save the scene first to establish a project folder." title:"Scene Not Saved"
                 return false
             )
             
             local srcPath = getTexturesPath()
             local dstDir = maxFilePath + "Textures\\"
             
             -- Ensure destination directory exists
             if not doesDirectoryExist dstDir do makeDir dstDir
             
             local sceneName = getFilenameFile maxFileName
             local newBaseName = sceneName + "-Background"
             
             -- List of suffixes to look for
             local suffixes = #("_D", "_A", "_N", "_M", "_R", "_O") -- Common suffixes
             local processed = 0
             
             -- To store map changes for material update
             local mapReplacements = #() 
             
             for suffix in suffixes do (
                 -- Try different extensions
                 local exts = #(".png", ".jpg", ".tif", ".tga")
                 local srcFile = undefined
                 local extFound = undefined
                 
                 for ext in exts do (
                     local testPath = srcPath + bgName + suffix + ext
                     if doesFileExist testPath then (
                         srcFile = testPath
                         extFound = ext
                         exit
                     )
                 )
                 
                 if srcFile != undefined then (
                     local newFileName = newBaseName + suffix + extFound
                     local dstFile = dstDir + newFileName
                     
                     -- Overwrite logic: delete if exists
                     if doesFileExist dstFile do (
                         try ( deleteFile dstFile ) catch ( format "WARNING: Could not delete existing file %\n" dstFile )
                     )
                     
                     try (
                         copyFile srcFile dstFile
                         format "Copied: % -> %\n" (filenameFromPath srcFile) newFileName
                         
                         append mapReplacements #(srcFile, dstFile)
                         processed += 1
                     ) catch (
                         format "Failed to copy: %\n" srcFile
                     )
                 )
             )
             
             -- Relink Material Textures
             if obj.material != undefined then (
                 local matsToCheck = #(obj.material)
                 
                 -- If it's a Multi/Sub-Object, add submaterials
                 if classOf obj.material == Multimaterial then (
                     for m in obj.material.materialList where m != undefined do append matsToCheck m
                 )
                 
                 for mat in matsToCheck do (
                     -- Scan all properties of the material for bitmaps
                     -- This is a simple generic scan. For specific material types (Arnold, V-Ray, Corona), 
                     -- direct property access might be safer, but `getClassInstances` on the material tree is robust.
                     
                     local maps = getClassInstances BitmapTexture target:mat
                     
                     for map in maps do (
                         local currentPath = map.filename
                         
                         -- Check if this map corresponds to one of our replacements
                         -- We check if the filename matches the SOURCE pattern (bgName + suffix)
                         
                         local fName = filenameFromPath currentPath
                         
                         if matchPattern fName pattern:(bgName + "*") ignoreCase:true then (
                             -- It matches the background name. Now find which specific suffix/file it maps to.
                             -- Since we already determined the destination file for each suffix, we can match logic.
                             
                             -- Find best match in our replacement list
                             for pair in mapReplacements do (
                                 -- pair[1] is source full path
                                 -- pair[2] is dest full path
                                 
                                 if (filenameFromPath pair[1]) == fName then (
                                     map.filename = pair[2]
                                     format "Relinked map: % -> %\n" fName (filenameFromPath pair[2])
                                 )
                             )
                         )
                     )
                     
                     -- Support for other map types (e.g., VRayBitmap, CoronaBitmap) if needed?
                     -- Standard Max BitmapTexture is usually sufficient for simple imports. 
                     -- If the asset uses other loaders, we'd need to add them here.
                 )
             )
             
             return true
        ),
        
        fn importBackground bgName = (
            if libraryPath == undefined do libraryPath = getLibraryPath()
            
            if libraryPath == undefined or not doesFileExist libraryPath then (
                messageBox "Library file not found!" title:"Error"
                return false
            )
            
            try (
                mergeMAXFile libraryPath #(bgName) #select #autoRenameDups
                
                if selection.count > 0 then (
                    local importedObj = selection[1]
                    
                    -- Process Textures
                    processTextures bgName importedObj
                    
                    -- Rename object to match scene convention if desired?
                    -- Requirement was mostly about textures, but let's keep object name as imported for now unless requested.
                    
                    return true
                )
            ) catch (
                messageBox ("Error importing background:\n" + getCurrentException()) title:"Error"
            )
            return false
        )
    )
    
    local bgManager = BackgroundManagerStruct()
    
    -- ============================
    -- ROLLOUT: Main UI
    -- ============================
    rollout bgRollout "Nfinite Backgrounder v1.0" width:680 height:550
    (
        -- Group box for visual structure
        group "Background Library" (
            dotNetControl lvBackgrounds "System.Windows.Forms.ListView" width:640 height:450 align:#center
        )
        
        button btnImport "IMPORT SELECTED" width:200 height:40 pos:[240, 500]
        
        -- ============================
        -- FUNCTIONS
        -- ============================
        
        fn initListView = (
            -- Setup ListView properties
            lvBackgrounds.View = (dotNetClass "System.Windows.Forms.View").LargeIcon
            lvBackgrounds.MultiSelect = false
            lvBackgrounds.CheckBoxes = false
            lvBackgrounds.FullRowSelect = false
            lvBackgrounds.HideSelection = false
            
            -- Dark Theme Styling
            local drawingColor = dotNetClass "System.Drawing.Color"
            lvBackgrounds.BackColor = drawingColor.FromArgb 40 40 40
            lvBackgrounds.ForeColor = drawingColor.FromArgb 220 220 220
            
            -- Initialize ImageList
            local imgList = dotNetObject "System.Windows.Forms.ImageList"
            imgList.ImageSize = dotNetObject "System.Drawing.Size" 160 90 -- 16:9 thumbnails
            imgList.ColorDepth = (dotNetClass "System.Windows.Forms.ColorDepth").Depth32Bit
            
            lvBackgrounds.LargeImageList = imgList
            
            -- Populate Data
            bgManager.libraryPath = bgManager.getLibraryPath()
            local bgs = bgManager.getAvailableBackgrounds()
            local pPath = bgManager.getPreviewsPath()
            
            -- Suppress updates for performance
            lvBackgrounds.BeginUpdate()
            
            for i = 1 to bgs.count do (
                local bgName = bgs[i]
                
                -- Load Image
                local imgFound = false
                local imgFile = undefined
                
                if pPath != undefined then (
                    local pngFile = pPath + bgName + ".png"
                    local jpgFile = pPath + bgName + ".jpg"
                    
                    if doesFileExist pngFile then imgFile = pngFile
                    else if doesFileExist jpgFile then imgFile = jpgFile
                )
                
                local imgIndex = i - 1
                
                -- Add image to list
                if imgFile != undefined then (
                    try (
                        local img = (dotNetClass "System.Drawing.Image").FromFile imgFile
                        imgList.Images.Add img
                        imgFound = true
                    ) catch (
                         format "Error loading image: %\n" imgFile
                    )
                )
                
                if not imgFound then (
                     local bmp = dotNetObject "System.Drawing.Bitmap" 160 90
                     local gfx = (dotNetClass "System.Drawing.Graphics").FromImage bmp
                     gfx.Clear (drawingColor.Gray)
                     imgList.Images.Add bmp
                )
                
                -- Create Item
                local item = dotNetObject "System.Windows.Forms.ListViewItem" bgName
                item.ImageIndex = imgIndex
                lvBackgrounds.Items.Add item
            )
            
            lvBackgrounds.EndUpdate()
        )
        
        -- ============================
        -- EVENTS
        -- ============================
        
        on bgRollout open do (
            initListView()
        )
        
        on btnImport pressed do (
            if lvBackgrounds.SelectedItems.Count > 0 then (
                 local selItem = lvBackgrounds.SelectedItems.Item[0]
                 local bgName = selItem.Text
                 
                 if bgManager.importBackground bgName then (
                     format "Imported: %\n" bgName
                 )
            ) else (
                messageBox "Please select a background first." title:"Info"
            )
        )
        
        on lvBackgrounds DoubleClick s a do (
            if lvBackgrounds.SelectedItems.Count > 0 then (
                 btnImport.pressed()
            )
        )
    )
    
    createDialog bgRollout
)
