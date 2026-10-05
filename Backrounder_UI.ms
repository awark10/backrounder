-- Backrounder UI: Knowledge Hub login, gallery and import.
-- Evaluated at global scope by the macroScript (Background_Importer.mcr); needs KH_Client.ms loaded first.

global BR_kh
global BR_items = #() -- #(title, previewFileId, packageFileId)
global BR_loginOk = false
global BR_library -- index into BR_kh.libraries; kept between openings
if BR_library == undefined do BR_library = 1
global BR_mainRollout
-- Per library: #(items, ImageList). Filled on first visit, reused on tab switches and reopenings,
-- rebuilt only by Refresh.
global BR_cache
if BR_cache == undefined do BR_cache = #()
global BR_loginRollout

-- ============================
-- IMPORT
-- ============================

-- Copies every bitmap the merged objects use into <scene folder>\textures\ as
-- <sceneName>-<original file name> and relinks the maps to the copies.
fn BR_localizeTextures objs packageDir = (
    local dstDir = maxFilePath + "textures\\"
    if not doesDirectoryExist dstDir do makeDir dstDir
    local sceneName = getFilenameFile maxFileName

    local packageFiles = BR_kh.findFiles packageDir "*.*"
    local copied = #() -- source file name (lowercase) -> destination
    local copiedDst = #()
    local missing = #()

    local mats = #()
    for o in objs where o.material != undefined do appendIfUnique mats o.material

    for mat in mats do (
        for map in (getClassInstances BitmapTexture target:mat) where map.filename != undefined and map.filename != "" do (
            local fName = filenameFromPath map.filename
            local key = toLower fName
            local idx = findItem copied key
            if idx == 0 do (
                -- Prefer the copy shipped in the package; fall back to the stored path
                local src = undefined
                for p in packageFiles while src == undefined do
                    if toLower (filenameFromPath p) == key do src = p
                if src == undefined and doesFileExist map.filename do src = map.filename

                if src == undefined then (
                    appendIfUnique missing fName
                ) else (
                    local dst = dstDir + sceneName + "-" + fName
                    if doesFileExist dst do deleteFile dst
                    if copyFile src dst then (
                        append copied key
                        append copiedDst dst
                        idx = copied.count
                    ) else (
                        format "Backrounder: failed to copy % -> %\n" src dst
                        appendIfUnique missing fName
                    )
                )
            )
            if idx > 0 do map.filename = copiedDst[idx]
        )
    )
    for d in copiedDst do format "Backrounder: texture %\n" d
    missing
)

fn BR_importBackground item = (
    local title = item[1]
    if maxFilePath == "" do (
        messageBox "Please save the scene first: textures are copied next to the .max file." title:"Scene Not Saved"
        return false
    )

    progressStart ("Downloading " + title + "...")
    local dir = BR_kh.getPackage title item[3]
    progressEnd()
    if dir == undefined do (
        messageBox ("Could not get " + title + ":\n" + BR_kh.lastError) title:"Backrounder"
        return false
    )

    local maxFiles = BR_kh.findFiles dir "*.max"
    if maxFiles.count == 0 do (
        messageBox ("The package for " + title + " has no .max file.") title:"Backrounder"
        return false
    )
    local maxFile = maxFiles[1]
    for f in maxFiles where matchPattern (getFilenameFile f) pattern:(title + "*") do (maxFile = f; exit)

    -- Merge the object(s) named after the background, or everything if none match
    local names = getMAXFileObjectNames maxFile
    local toMerge = for n in names where matchPattern n pattern:(title + "*") collect n
    if toMerge.count == 0 do toMerge = names

    try (
        mergeMAXFile maxFile toMerge #select #autoRenameDups
    ) catch (
        messageBox ("Error importing " + title + ":\n" +getCurrentException()) title:"Backrounder"
        return false
    )
    local objs = selection as array
    if objs.count == 0 do return false

    local missing = BR_localizeTextures objs dir
    if missing.count > 0 do (
        local msg = "Imported " + title + ", but these textures were not found:\n"
        for m in missing do msg += m + "\n"
        messageBox msg title:"Backrounder"
    )
    -- Leave the imported object(s) selected so they can be placed right away
    select (for o in objs where isValidNode o collect o)
    completeRedraw()
    format "Backrounder: imported % (% objects)\n" title objs.count
    true
)

-- ============================
-- ROLLOUT: Login
-- ============================
rollout BR_loginRollout "Knowledge Hub Login" width:300 height:190
(
    label lblInfo "Sign in with your kh-physicl.com account" pos:[15,12]
    label lblEmail "Email" pos:[15,40]
    dotNetControl tbEmail "System.Windows.Forms.TextBox" pos:[80,37] width:205 height:20
    label lblPass "Password" pos:[15,68]
    dotNetControl tbPass "System.Windows.Forms.TextBox" pos:[80,65] width:205 height:20
    checkbox chkRemember "Remember me on this computer" pos:[80,94] checked:true
    label lblError "" pos:[15,118] width:270 height:28
    button btnLogin "Sign in" pos:[80,150] width:100 height:26
    button btnCancel "Cancel" pos:[185,150] width:100 height:26

    fn doLogin = (
        local email = trimLeft (trimRight tbEmail.Text)
        if email == "" or tbPass.Text == "" do (lblError.text = "Enter email and password."; return false)
        lblError.text = "Signing in..."
        if BR_kh.login email tbPass.Text remember:chkRemember.checked then (
            BR_loginOk = true
            tbPass.Text = ""
            destroyDialog BR_loginRollout
        ) else (
            lblError.text = BR_kh.lastError
            tbPass.Text = ""
        )
    )

    on BR_loginRollout open do (
        tbPass.UseSystemPasswordChar = true
        tbEmail.Focus()
    )
    on tbPass KeyDown s e do (
        if e.KeyCode == (dotNetClass "System.Windows.Forms.Keys").Enter do doLogin()
    )
    on btnLogin pressed do doLogin()
    on btnCancel pressed do destroyDialog BR_loginRollout
)

-- Shows the login dialog until the user signs in or cancels
fn BR_ensureLogin = (
    BR_loginOk = false
    createDialog BR_loginRollout modal:true
    BR_loginOk
)

-- Loads the current library into BR_items, asking to sign in when the session is missing or expired.
-- Uses the in-memory copy unless force:true (Refresh).
fn BR_loadLibrary force:false = (
    local cached = BR_cache[BR_library]
    if not force and cached != undefined do (
        BR_items = cached[1]
        return true
    )
    local folderId = BR_kh.libraries[BR_library][2]
    local r = BR_kh.fetchCards folderId
    if r[1] == #unauthorized do (
        if not (BR_ensureLogin()) do return false
        r = BR_kh.fetchCards folderId
    )
    if r[1] != #ok do (
        messageBox ("Could not load the library:\n" + BR_kh.lastError) title:"Backrounder"
        return false
    )
    BR_items = r[2]
    BR_cache[BR_library] = #(BR_items, undefined) -- thumbnails are (re)built by fillList
    true
)

-- ============================
-- ROLLOUT: Main UI
-- ============================
rollout BR_mainRollout "Physicl Asset Browser v2.2" width:680 height:590
(
    -- Library tabs; one per entry in BR_kh.libraries
    checkbutton tabLib1 "BACKPLATES" pos:[20,6] width:100 height:26
    checkbutton tabLib2 "DECALS" pos:[122,6] width:100 height:26
    group "Knowledge Hub Library" (
        dotNetControl lvBackgrounds "System.Windows.Forms.ListView" width:640 height:450 align:#center
    )
    label lblStatus "" pos:[20,535] width:200
    button btnRefresh "Refresh" pos:[20,552] width:80 height:26
    button btnImport "IMPORT SELECTED" width:200 height:40 pos:[240,540]
    button btnLogout "Sign out" pos:[580,552] width:80 height:26

    fn makeThumb file = (
        -- Read through a stream so the cached file is not locked while the dialog is open.
        -- Fit inside 160x90 keeping the aspect ratio (decals are mostly square, backgrounds wide).
        local fs = (dotNetClass "System.IO.File").OpenRead file
        local img = (dotNetClass "System.Drawing.Image").FromStream fs
        local bmp = dotNetObject "System.Drawing.Bitmap" 160 90
        local gfx = (dotNetClass "System.Drawing.Graphics").FromImage bmp
        gfx.Clear ((dotNetClass "System.Drawing.Color").FromArgb 40 40 40)
        local s = amin (160.0 / img.Width) (90.0 / img.Height)
        local w = (img.Width * s) as integer
        local h = (img.Height * s) as integer
        gfx.DrawImage img ((160 - w) / 2) ((90 - h) / 2) w h
        gfx.Dispose()
        img.Dispose()
        fs.Close()
        bmp
    )

    fn grayThumb = (
        local bmp = dotNetObject "System.Drawing.Bitmap" 160 90
        local gfx = (dotNetClass "System.Drawing.Graphics").FromImage bmp
        gfx.Clear ((dotNetClass "System.Drawing.Color").Gray)
        gfx.Dispose()
        bmp
    )

    fn fillList = (
        lvBackgrounds.Items.Clear()
        local cached = BR_cache[BR_library]
        if cached != undefined and cached[2] != undefined do (
            -- Already built: just show it
            lvBackgrounds.BeginUpdate()
            lvBackgrounds.LargeImageList = cached[2]
            for i = 1 to BR_items.count do (
                local lvi = dotNetObject "System.Windows.Forms.ListViewItem" BR_items[i][1]
                lvi.ImageIndex = i - 1
                lvBackgrounds.Items.Add lvi
            )
            lvBackgrounds.EndUpdate()
            lblStatus.text = (BR_items.count as string) + " items"
            return ok
        )
        local imgList = dotNetObject "System.Windows.Forms.ImageList"
        imgList.ImageSize = dotNetObject "System.Drawing.Size" 160 90 -- 16:9 thumbnails
        imgList.ColorDepth = (dotNetClass "System.Windows.Forms.ColorDepth").Depth32Bit
        lvBackgrounds.LargeImageList = imgList

        progressStart ("Loading " + BR_kh.libraries[BR_library][1] + " from Knowledge Hub...")
        lvBackgrounds.BeginUpdate()
        for i = 1 to BR_items.count do (
            local item = BR_items[i]
            local file = BR_kh.getPreview item[1] item[2]
            local thumb = undefined
            if file != undefined do thumb = try (makeThumb file) catch (undefined)
            imgList.Images.Add (if thumb != undefined then thumb else grayThumb())

            local lvi = dotNetObject "System.Windows.Forms.ListViewItem" item[1]
            lvi.ImageIndex = i - 1
            lvBackgrounds.Items.Add lvi
            if not (progressUpdate (100.0 * i / BR_items.count)) do exit
        )
        lvBackgrounds.EndUpdate()
        progressEnd()
        -- Keep it only if every thumbnail was added (not cancelled)
        if cached != undefined and imgList.Images.Count == BR_items.count do cached[2] = imgList
        lblStatus.text = (BR_items.count as string) + " items"
    )

    fn showTab i = (
        tabLib1.checked = (i == 1)
        tabLib2.checked = (i == 2)
    )

    fn switchLibrary i = (
        showTab i -- clicking the active tab keeps it pressed
        if i == BR_library do return ok
        local prev = BR_library
        BR_library = i
        if BR_loadLibrary() then fillList() else (
            BR_library = prev
            showTab prev
        )
    )

    fn importSelected = (
        if lvBackgrounds.SelectedItems.Count == 0 do (
            messageBox "Please select an item first." title:"Info"
            return false
        )
        local idx = (lvBackgrounds.SelectedItems.Item[0]).Index + 1
        BR_importBackground BR_items[idx]
    )

    on BR_mainRollout open do (
        lvBackgrounds.View = (dotNetClass "System.Windows.Forms.View").LargeIcon
        lvBackgrounds.MultiSelect = false
        lvBackgrounds.HideSelection = false
        local drawingColor = dotNetClass "System.Drawing.Color"
        lvBackgrounds.BackColor = drawingColor.FromArgb 40 40 40
        lvBackgrounds.ForeColor = drawingColor.FromArgb 220 220 220

        showTab BR_library
        fillList()
    )

    on tabLib1 changed st do switchLibrary 1
    on tabLib2 changed st do switchLibrary 2
    on btnRefresh pressed do (if BR_loadLibrary force:true do fillList())
    on btnImport pressed do importSelected()
    on lvBackgrounds DoubleClick s a do importSelected()
    on btnLogout pressed do (
        BR_kh.logout()
        BR_items = #()
        BR_cache = #()
        destroyDialog BR_mainRollout
    )
)

fn BR_open = (
    -- A fresh client each time, so a reinstalled KH_Client.ms takes effect without restarting Max
    BR_kh = BackrounderKHClient()
    BR_kh.init()
    BR_kh.loadSession()
    if BR_library > BR_kh.libraries.count do BR_library = 1
    try (destroyDialog BR_mainRollout) catch ()
    if BR_loadLibrary() do createDialog BR_mainRollout
)
