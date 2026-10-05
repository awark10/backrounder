-- Knowledge Hub (kh-physicl.com) client for Backrounder
-- Login, background list, preview/package download with local cache.
-- Defines the global structs BackrounderJSON and BackrounderKHClient; the macroScript creates one client.
-- Works on .NET Framework (3ds Max 2022-2024) and .NET 8 (3ds Max 2025+).

(
    for asm in #("System.Net.Http", "System.Security", "System.Security.Cryptography.ProtectedData", \
                 "System.IO.Compression", "System.IO.Compression.FileSystem", "System.Web.Extensions") do
        try (dotNet.loadAssembly asm) catch ()
)

-- ============================
-- Minimal JSON reader/writer
-- objects -> Dictionary #string, arrays -> Array, null -> undefined
-- ============================
struct BackrounderJSON (
    src = "",
    pos = 1,

    fn skipWs = (
        while pos <= src.count and (findString " \t\r\n" src[pos]) != undefined do pos += 1
    ),

    fn parseString = (
        pos += 1 -- opening quote
        local ss = stringStream ""
        while pos <= src.count and src[pos] != "\"" do (
            local ch = src[pos]
            if ch == "\\" then (
                pos += 1
                local e = src[pos]
                case e of (
                    "n": format "\n" to:ss
                    "r": format "\r" to:ss
                    "t": format "\t" to:ss
                    "b": format "%" (bit.intAsChar 8) to:ss
                    "f": format "%" (bit.intAsChar 12) to:ss
                    "u": (
                        local code = bit.hexAsInt (substring src (pos + 1) 4)
                        format "%" ((dotNetClass "System.Convert").ToChar code) to:ss
                        pos += 4
                    )
                    default: format "%" e to:ss -- \" \\ \/
                )
            ) else format "%" ch to:ss
            pos += 1
        )
        pos += 1 -- closing quote
        ss as string
    ),

    fn parseNumber = (
        local start = pos
        while pos <= src.count and (findString "+-0123456789.eE" src[pos]) != undefined do pos += 1
        local s = substring src start (pos - start)
        if (findString s ".") != undefined or (findString s "e") != undefined or (findString s "E") != undefined \
            then s as float else s as integer
    ),

    fn parseArray = (
        pos += 1
        local arr = #()
        skipWs()
        if src[pos] == "]" then (pos += 1; return arr)
        while true do (
            append arr (this.parseValue())
            skipWs()
            if src[pos] == "," then pos += 1 else (pos += 1; exit)
        )
        arr
    ),

    fn parseObject = (
        pos += 1
        local d = Dictionary #string
        skipWs()
        if src[pos] == "}" then (pos += 1; return d)
        while true do (
            skipWs()
            local k = parseString()
            skipWs()
            pos += 1 -- colon
            d[k] = this.parseValue()
            skipWs()
            if src[pos] == "," then pos += 1 else (pos += 1; exit)
        )
        d
    ),

    fn parseValue = (
        skipWs()
        local ch = src[pos]
        case of (
            (ch == "{"): parseObject()
            (ch == "["): parseArray()
            (ch == "\""): parseString()
            (ch == "t"): (pos += 4; true)
            (ch == "f"): (pos += 5; false)
            (ch == "n"): (pos += 4; undefined)
            default: parseNumber()
        )
    ),

    fn parse text = (
        src = text
        pos = 1
        parseValue()
    ),

    fn get d key = (
        if classOf d == Dictionary and hasDictValue d key then d[key] else undefined
    ),

    fn quote s = (
        local r = substituteString s "\\" "\\\\"
        r = substituteString r "\"" "\\\""
        r = substituteString r "\n" "\\n"
        r = substituteString r "\r" "\\r"
        r = substituteString r "\t" "\\t"
        "\"" + r + "\""
    )
)

struct BackrounderKHClient (
    baseUrl = "https://www.kh-physicl.com",
    -- Knowledge Hub folders shown in the gallery: #(label, folderId)
    libraries = #(
        #("Backplates", "3d1e8a52-c530-4db5-b1af-7306c9a820d7"), -- Library > Backplates > Exterior scene Backplates
        #("Decals", "20f6b229-9912-4f83-b55f-55c30aef8a92")       -- Library > Decals
    ),
    cacheDir = (getDir #userMacros) + "\\Backrounder_cache\\",

    cookies = undefined,
    client = undefined,
    json = BackrounderJSON(),
    lastError = "",

    -- ============================
    -- SETUP
    -- ============================

    fn init = (
        -- .NET Framework in 3ds Max 2022 may default to TLS 1.0; the site and Google Drive require TLS 1.2
        try (
            local spm = dotNetClass "System.Net.ServicePointManager"
            spm.SecurityProtocol = (dotNetClass "System.Net.SecurityProtocolType").Tls12
        ) catch ()

        cookies = dotNetObject "System.Net.CookieContainer"
        local handler = dotNetObject "System.Net.Http.HttpClientHandler"
        handler.CookieContainer = cookies
        handler.UseCookies = true
        -- Unauthenticated requests are answered with a redirect to /login; we want to see it, not follow it
        handler.AllowAutoRedirect = false
        client = dotNetObject "System.Net.Http.HttpClient" handler
        client.Timeout = dotNetObject "System.TimeSpan" 0 5 0
        client.DefaultRequestHeaders.Add "User-Agent" "Backrounder-3dsMax/2.0"

        makeDir (cacheDir + "thumbs") all:true
        makeDir (cacheDir + "packages") all:true
        ok
    ),

    fn statusOf resp = (
        (dotNetClass "System.Convert").ToInt32 resp.StatusCode
    ),

    fn readBody resp = (
        (resp.Content.ReadAsStringAsync()).Result
    ),

    fn isLoginRedirect resp = (
        local code = statusOf resp
        if code == 401 do return true
        if code >= 300 and code < 400 and resp.Headers.Location != undefined do
            return matchPattern (resp.Headers.Location.ToString()) pattern:"*login*"
        false
    ),

    -- ============================
    -- SESSION (cookie kept per Windows user, encrypted with DPAPI)
    -- ============================

    fn sessionFile = cacheDir + "session.dat",

    fn canPersist = (
        try ((dotNetClass "System.Security.Cryptography.ProtectedData") != undefined) catch (false)
    ),

    fn saveSession = (
        if not (canPersist()) do return false
        local uri = dotNetObject "System.Uri" baseUrl
        local col = cookies.GetCookies uri
        local ss = stringStream ""
        for i = 0 to col.Count - 1 do (
            local c = col.Item[i]
            format "%\t%\n" c.Name c.Value to:ss
        )
        local enc = (dotNetClass "System.Text.Encoding").UTF8
        local scope = (dotNetClass "System.Security.Cryptography.DataProtectionScope").CurrentUser
        local data = (dotNetClass "System.Security.Cryptography.ProtectedData").Protect (enc.GetBytes (ss as string)) undefined scope
        (dotNetClass "System.IO.File").WriteAllBytes (sessionFile()) data
        true
    ),

    fn loadSession = (
        local f = sessionFile()
        if not doesFileExist f or not (canPersist()) do return false
        try (
            local enc = (dotNetClass "System.Text.Encoding").UTF8
            local scope = (dotNetClass "System.Security.Cryptography.DataProtectionScope").CurrentUser
            local raw = (dotNetClass "System.Security.Cryptography.ProtectedData").Unprotect ((dotNetClass "System.IO.File").ReadAllBytes f) undefined scope
            local uri = dotNetObject "System.Uri" baseUrl
            for l in (filterString (enc.GetString raw) "\n") do (
                local parts = filterString l "\t"
                if parts.count == 2 do
                    cookies.Add uri (dotNetObject "System.Net.Cookie" parts[1] parts[2])
            )
            true
        ) catch (
            format "Backrounder: could not read saved session: %\n" (getCurrentException())
            false
        )
    ),

    fn clearSession = (
        if doesFileExist (sessionFile()) do deleteFile (sessionFile())
        init()
    ),

    -- ============================
    -- AUTH
    -- ============================

    -- Returns true on success; on failure lastError holds the message for the user
    fn login email password remember:true = (
        lastError = ""
        try (
            local body = "{\"email\":" + (json.quote email) + ",\"password\":" + (json.quote password) + "}"
            local content = dotNetObject "System.Net.Http.StringContent" body \
                (dotNetClass "System.Text.Encoding").UTF8 "application/json"
            local resp = (client.PostAsync (baseUrl + "/api/auth/login") content).Result
            local text = readBody resp
            if resp.IsSuccessStatusCode then (
                if remember then saveSession() else (
                    if doesFileExist (sessionFile()) do deleteFile (sessionFile())
                )
                true
            ) else (
                local msg = try (json.get (json.parse text) "error") catch (undefined)
                lastError = if msg != undefined then msg else ("Login failed (HTTP " + (statusOf resp) as string + ")")
                false
            )
        ) catch (
            lastError = "Network error: " + (getCurrentException())
            false
        )
    ),

    fn logout = (
        try ((client.PostAsync (baseUrl + "/api/auth/logout") (dotNetObject "System.Net.Http.StringContent" "")).Result) catch ()
        clearSession()
    ),

    -- ============================
    -- LIBRARY
    -- ============================

    -- Google Drive share link -> file id
    fn driveId url = (
        if url == undefined do return undefined
        local m = (dotNetClass "System.Text.RegularExpressions.Regex").Match url "(?:/d/|[?&]id=)([A-Za-z0-9_-]{10,})"
        if m.Success then (m.Groups.Item[1]).Value else undefined
    ),

    fn byTitle a b = stricmp a[1] b[1],

    -- /api/library/cards JSON -> sorted array of #(title, previewFileId, packageFileId)
    -- .NET parser (System.Web.Extensions, always present with .NET Framework 4.8 in Max 2022).
    -- The MAXScript reader is quadratic on long strings: ~1 min for the 105 decal cards.
    fn parseCardsNet text = (
        local js = dotNetObject "System.Web.Script.Serialization.JavaScriptSerializer"
        js.MaxJsonLength = 2147483647
        local root = js.DeserializeObject text
        local items = #()
        if not (root.ContainsKey "cards") do return items
        fn field c key = (if c.ContainsKey key then c.Item[key] else undefined)
        local raw = root.Item["cards"]
        -- MAXScript may hand back a converted Array or the .NET object[] itself
        local cards = if classOf raw == Array then raw else (for i = 0 to raw.Length - 1 collect raw.GetValue i)
        for c in cards do (
            if (field c "status") == "published" do (
                local title = field c "title"
                local dId = driveId (field c "downloadUrl")
                if title != undefined and dId != undefined do
                    append items #(title, driveId (field c "previewImageUrl"), dId)
            )
        )
        qsort items byTitle
        items
    ),

    fn parseCards text = (
        local fast = try (parseCardsNet text) catch (
            format "Backrounder: .NET JSON parser unavailable, using the slow one: %
" (getCurrentException())
            undefined
        )
        if fast != undefined do return fast
        local items = #()
        local cards = json.get (json.parse text) "cards"
        if cards != undefined do for c in cards do (
            if (json.get c "status") == "published" do (
                local title = json.get c "title"
                local dId = driveId (json.get c "downloadUrl")
                if title != undefined and dId != undefined do
                    append items #(title, driveId (json.get c "previewImageUrl"), dId)
            )
        )
        qsort items byTitle
        items
    ),

    -- Returns #(#ok, items) | #(#unauthorized, #()) | #(#error, #())
    fn fetchCards folderId = (
        lastError = ""
        try (
            local resp = (client.GetAsync (baseUrl + "/api/library/cards?folderId=" + folderId)).Result
            if isLoginRedirect resp do return #(#unauthorized, #())
            local text = readBody resp
            if not resp.IsSuccessStatusCode do (
                lastError = "HTTP " + (statusOf resp) as string
                return #(#error, #())
            )
            -- The server may refresh the token on any request; keep the newest cookie
            if doesFileExist (sessionFile()) do saveSession()
            #(#ok, parseCards text)
        ) catch (
            lastError = "Network error: " + (getCurrentException())
            #(#error, #())
        )
    ),

    -- ============================
    -- DOWNLOADS (Google Drive, public links)
    -- ============================

    fn downloadDrive fileId dstPath = (
        this.downloadUrl ("https://drive.usercontent.google.com/download?id=" + fileId + "&export=download&confirm=t") dstPath
    ),

    fn downloadUrl url dstPath = (
        if doesFileExist dstPath do return true
        local tmp = dstPath + ".part"
        try (
            -- Separate client that follows Drive's redirects and keeps no Hub cookies
            local dl = dotNetObject "System.Net.Http.HttpClient"
            dl.Timeout = dotNetObject "System.TimeSpan" 0 10 0
            dl.DefaultRequestHeaders.Add "User-Agent" "Backrounder-3dsMax/2.0"
            local resp = (dl.GetAsync url).Result
            if not resp.IsSuccessStatusCode do (
                lastError = "Download failed (HTTP " + (statusOf resp) as string + ")"
                dl.Dispose()
                return false
            )
            local mediaType = if resp.Content.Headers.ContentType != undefined then resp.Content.Headers.ContentType.MediaType else ""
            -- An HTML page instead of a file means the link is not public or the quota is exceeded
            if matchPattern mediaType pattern:"text/html*" do (
                lastError = "Google Drive returned a web page instead of the file (link not public or download quota exceeded)."
                dl.Dispose()
                return false
            )
            local bytes = (resp.Content.ReadAsByteArrayAsync()).Result
            (dotNetClass "System.IO.File").WriteAllBytes tmp bytes
            dl.Dispose()
            if doesFileExist dstPath do deleteFile dstPath
            renameFile tmp dstPath
        ) catch (
            if doesFileExist tmp do deleteFile tmp
            lastError = "Download failed: " + (getCurrentException())
            false
        )
    ),

    -- Cache names include the Drive id, so a file replaced on the Hub is fetched again
    -- Gallery thumbnail: Drive renders a ~320px copy server side, so a 100 MB preview costs ~60 KB.
    -- Cached once per Drive id; later openings read only the local file.
    fn getPreview title fileId = (
        if fileId == undefined do return undefined
        local p = cacheDir + "thumbs\\" + title + "_" + fileId + ".png"
        if downloadUrl ("https://drive.google.com/thumbnail?id=" + fileId + "&sz=w320") p then p else undefined
    ),

    -- Downloads and unpacks the background package; returns the folder or undefined
    fn getPackage title fileId = (
        local base = cacheDir + "packages\\" + title + "_" + fileId
        local zip = base + ".zip"
        local dir = base + "\\"
        if doesDirectoryExist dir do return dir
        if not (downloadDrive fileId zip) do return undefined
        try (
            (dotNetClass "System.IO.Compression.ZipFile").ExtractToDirectory zip dir
            deleteFile zip
            dir
        ) catch (
            lastError = "Could not unpack " + (filenameFromPath zip) + ": " + (getCurrentException())
            try ((dotNetClass "System.IO.Directory").Delete dir true) catch ()
            undefined
        )
    ),

    fn findFiles dir pattern = (
        local opt = (dotNetClass "System.IO.SearchOption").AllDirectories
        (dotNetClass "System.IO.Directory").GetFiles dir pattern opt
    )
)
