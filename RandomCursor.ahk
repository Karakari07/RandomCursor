; =============================================================
;  Random Cursor v5.3
;  Windows 鼠标指针主题自动轮换
;  需要 AutoHotkey v1.1.33+（不支持 v2）
;  本文件请保存为 UTF-8 with BOM，否则中文会乱码
; =============================================================
;@Ahk2Exe-SetName Random Cursor
;@Ahk2Exe-SetDescription Random Cursor
;@Ahk2Exe-SetVersion 5.3

#Requires AutoHotkey v1.1.33+
#NoEnv
#SingleInstance Force
#Persistent
SetWorkingDir %A_ScriptDir%

global version     := "5.3"
global themesDir   := A_ScriptDir "\themes"
global configFile  := A_ScriptDir "\config.ini"
global logFile     := A_ScriptDir "\cursor_log.txt"
global backupFile  := A_ScriptDir "\backup.ini"
global runKey      := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"

; Windows 的全部 17 种指针（顺序与 install.inf 里 Schemes 行的顺序一致）
global cursorTypes := ["Arrow", "Help", "AppStarting", "Wait", "Crosshair", "IBeam", "NWPen", "No"
    , "SizeNS", "SizeWE", "SizeNWSE", "SizeNESW", "SizeAll", "UpArrow", "Hand", "Pin", "Person"]

global themes       := []
global themeCount   := 0
global bag          := []
global currentTheme := ""
global paused       := false
global firstApply   := true
global interval     := 600000
global order        := "random"
global notifyEach   := false

Log("程序启动 v" version)

; 文件夹和配置文件立即生成
InitEnvironment()
ReadConfig()
BuildMenu()

; 改注册表的操作延后执行，降低安全软件误报概率
SetTimer, InitProgram, -5000
Return


; =============================================================
;  初始化
; =============================================================

InitProgram:
    Log("开始初始化")
    BackupCurrentCursor()
    SyncStartup()
    LoadThemes()
    SetTimer, ScanThemes, 10000

    if (themeCount = 0)
    {
        Log("themes 文件夹为空，等待放入主题")
        TrayTip, Random Cursor, themes 文件夹还是空的。`n把光标主题文件夹放进去，程序会自动开始轮换。, 8
        Return
    }
    SetTimer, FirstApply, -3000
Return

FirstApply:
    StartRotation()
Return


InitEnvironment()
{
    if !FileExist(themesDir)
        FileCreateDir, %themesDir%

    if !FileExist(configFile)
    {
        text =
(
; Random Cursor 配置文件
; 改完后右键托盘图标，选「重新加载配置」即可生效

[Settings]
; 轮换间隔（毫秒）。600000 = 10 分钟，最小 10000（10 秒）
Interval=600000

; 轮换顺序：random = 随机（一轮之内不重复），sequence = 按文件夹顺序
Order=random

; 每次切换都弹出提示：1 = 是，0 = 只在启动时提示
NotifyEachSwitch=0
)
        FileAppend, %text%, %configFile%, UTF-16
    }
}


ReadConfig()
{
    IniRead, iv, %configFile%, Settings, Interval, 600000
    iv := Trim(iv)
    if iv is not integer
        iv := 600000
    if (iv < 10000)
        iv := 10000
    interval := iv

    IniRead, od, %configFile%, Settings, Order, random
    od := Trim(od)
    order := (od = "sequence") ? "sequence" : "random"

    IniRead, ne, %configFile%, Settings, NotifyEachSwitch, 0
    notifyEach := (Trim(ne) = "1")

    Log("配置：间隔 " interval " 毫秒，顺序 " order)
}


BuildMenu()
{
    Menu, Tray, NoStandard
    Menu, Tray, Add, 立即切换主题, ManualSwitch
    Menu, Tray, Default, 立即切换主题
    Menu, Tray, Add, 暂停自动轮换, TogglePause
    Menu, Tray, Add
    Menu, Tray, Add, 打开 themes 文件夹, OpenThemes
    Menu, Tray, Add, 导入当前系统光标为主题, ImportCurrent
    Menu, Tray, Add, 打开配置文件, OpenConfig
    Menu, Tray, Add, 重新加载配置, ReloadConfig
    Menu, Tray, Add
    Menu, Tray, Add, 恢复系统原始光标, RestoreBackup
    Menu, Tray, Add, 开机启动, ToggleStartup
    Menu, Tray, Add
    Menu, Tray, Add, 退出程序, ExitProgram
    Menu, Tray, Tip, Random Cursor
}


; =============================================================
;  日志（超过 512KB 自动归档，避免无限变大）
; =============================================================

Log(msg)
{
    FileGetSize, sz, %logFile%
    if (!ErrorLevel && sz > 524288)
        FileMove, %logFile%, %A_ScriptDir%\cursor_log.old.txt, 1

    FormatTime, ts,, yyyy-MM-dd HH:mm:ss
    FileAppend, %ts% - %msg%`n, %logFile%, UTF-8
}


; =============================================================
;  备份 / 恢复系统原始光标
;  只在 backup.ini 不存在时备份一次，之后不再覆盖
; =============================================================

BackupCurrentCursor()
{
    if (FileExist(backupFile))
    {
        Log("已有备份，跳过备份")
        return
    }

    for i, t in cursorTypes
    {
        RegRead, val, HKCU\Control Panel\Cursors, %t%
        if (ErrorLevel)
            val := ""
        IniWrite, %val%, %backupFile%, Backup, %t%
    }

    ; 方案名（「鼠标属性」里显示的那个名字）
    RegRead, scheme, HKCU\Control Panel\Cursors
    if (ErrorLevel)
        scheme := ""
    IniWrite, %scheme%, %backupFile%, Backup, SchemeName

    Log("系统光标已备份")
}


RestoreBackup:
    if (!FileExist(backupFile))
    {
        TrayTip, Random Cursor, 没有找到备份文件 backup.ini, 4
        Return
    }

    for i, t in cursorTypes
    {
        IniRead, val, %backupFile%, Backup, %t%, __MISSING__
        if (val != "__MISSING__")
            RegWrite, REG_EXPAND_SZ, HKCU\Control Panel\Cursors, %t%, %val%
    }

    IniRead, scheme, %backupFile%, Backup, SchemeName, __MISSING__
    if (scheme != "__MISSING__")
        RegWrite, REG_SZ, HKCU\Control Panel\Cursors, , %scheme%

    RefreshCursor()
    currentTheme := ""
    SetPaused(true)
    Menu, Tray, Tip, Random Cursor（已恢复系统光标）
    Log("恢复系统光标，自动轮换已暂停")
    TrayTip, Random Cursor, 已恢复系统原始光标。`n自动轮换已暂停，可在菜单里取消暂停。, 5
Return


; =============================================================
;  开机启动
; =============================================================

StartupCmd()
{
    return """" A_ScriptFullPath """"
}

IsStartupEnabled()
{
    RegRead, v, %runKey%, RandomCursor
    return !ErrorLevel
}

; 如果开了自启但程序换了位置，自动把路径更新成当前位置
SyncStartup()
{
    if (IsStartupEnabled())
    {
        RegRead, v, %runKey%, RandomCursor
        cmd := StartupCmd()
        if (v != cmd)
        {
            RegWrite, REG_SZ, %runKey%, RandomCursor, %cmd%
            Log("开机启动路径已更新")
        }
        Menu, Tray, Check, 开机启动
    }
    else
        Menu, Tray, Uncheck, 开机启动
}

ToggleStartup:
    if (IsStartupEnabled())
    {
        RegDelete, %runKey%, RandomCursor
        Menu, Tray, Uncheck, 开机启动
        TrayTip, Random Cursor, 已关闭开机启动, 3
        Log("关闭开机启动")
    }
    else
    {
        cmd := StartupCmd()
        RegWrite, REG_SZ, %runKey%, RandomCursor, %cmd%
        Menu, Tray, Check, 开机启动
        TrayTip, Random Cursor, 已开启开机启动, 3
        Log("开启开机启动")
    }
Return


; =============================================================
;  主题列表
; =============================================================

LoadThemes()
{
    themes := []
    Loop, Files, %themesDir%\*, D
        themes.Push(A_LoopFileFullPath)
    themeCount := themes.Length()
}

ScanThemes:
    oldCount := themeCount
    LoadThemes()
    if (themeCount != oldCount)
    {
        Log("主题数量变化：" oldCount " → " themeCount)
        bag := []
        if (oldCount = 0 && themeCount > 0)
            StartRotation()
        else if (themeCount = 0)
            SetTimer, NextTheme, Off
    }
Return


; 洗牌：一轮之内每套主题各出现一次，不会连续重复
RefillBag()
{
    bag := []
    for i, t in themes
        bag.Push(t)
    n := bag.Length()
    Loop, % n - 1
    {
        i := n - A_Index + 1
        Random, j, 1, %i%
        tmp := bag[i], bag[i] := bag[j], bag[j] := tmp
    }
}

PickNext(ref)
{
    if (themeCount = 0)
        return ""

    if (order = "sequence")
    {
        idx := 0
        for i, t in themes
        {
            if (t = ref)
            {
                idx := i
                break
            }
        }
        idx += 1
        if (idx > themeCount)
            idx := 1
        return themes[idx]
    }

    if (themeCount = 1)
        return themes[1]

    Loop, 3
    {
        while (bag.Length() > 0)
        {
            p := bag.Pop()
            if (p != currentTheme && p != ref && InStr(FileExist(p), "D"))
                return p
        }
        RefillBag()
    }
    return themes[1]
}


; =============================================================
;  轮换控制
; =============================================================

StartRotation()
{
    if (paused || themeCount = 0)
        return
    SwitchNow()
    SetTimer, NextTheme, %interval%
}

; 切换到下一套；某套主题读不出光标时自动跳过
SwitchNow()
{
    ref := currentTheme
    Loop, % themeCount
    {
        next := PickNext(ref)
        if (next = "")
            return false
        if (ApplyTheme(next))
            return true
        ref := next
    }
    return false
}

SetPaused(state)
{
    paused := state
    if (paused)
    {
        SetTimer, NextTheme, Off
        Menu, Tray, Check, 暂停自动轮换
    }
    else
    {
        Menu, Tray, Uncheck, 暂停自动轮换
        if (themeCount > 0)
            SetTimer, NextTheme, %interval%
    }
}

NextTheme:
    SwitchNow()
Return

ManualSwitch:
    if (themeCount = 0)
    {
        TrayTip, Random Cursor, themes 文件夹是空的, 3
        Return
    }
    if (SwitchNow())
    {
        SplitPath, currentTheme, name
        TrayTip, Random Cursor, 当前主题：%name%, 3
    }
    ; 手动切换后重新计时
    if (!paused)
        SetTimer, NextTheme, %interval%
Return

TogglePause:
    SetPaused(!paused)
    Log(paused ? "暂停轮换" : "恢复轮换")
Return

ReloadConfig:
    ReadConfig()
    if (!paused && themeCount > 0)
        SetTimer, NextTheme, %interval%
    mins := Round(interval / 60000, 1)
    TrayTip, Random Cursor, 配置已重新加载`n轮换间隔：%mins% 分钟, 4
Return

OpenThemes:
    Run, explorer.exe "%themesDir%"
Return

OpenConfig:
    Run, notepad.exe "%configFile%"
Return

ExitProgram:
    Log("程序退出")
    ExitApp
Return


; =============================================================
;  应用主题
; =============================================================

ApplyTheme(folder)
{
    SplitPath, folder, themeName

    map := ParseInf(folder)
    mode := "INF"
    if (map.Count() = 0)
    {
        map := GuessByFilename(folder)
        mode := "文件名"
    }
    if (map.Count() = 0)
    {
        Log("跳过 " themeName "：没有找到可用的光标文件")
        return false
    }

    ; 17 种指针全部写一遍：主题里没有的设为空（= 系统默认），
    ; 避免残留上一套主题的指针
    missing := ""
    for i, t in cursorTypes
    {
        val := map.HasKey(t) ? map[t] : ""
        if (val = "")
            missing .= t " "
        RegWrite, REG_EXPAND_SZ, HKCU\Control Panel\Cursors, %t%, %val%
    }
    RefreshCursor()

    currentTheme := folder
    Menu, Tray, Tip, Random Cursor - %themeName%
    Log("切换主题：" themeName "（" mode "识别，" map.Count() "/17）" (missing != "" ? " 缺少：" missing : ""))

    if (firstApply)
    {
        firstApply := false
        TrayTip, Random Cursor, 已启动 — 当前主题：%themeName%, 5
    }
    else if (notifyEach)
        TrayTip, Random Cursor, 当前主题：%themeName%, 3

    return true
}

RefreshCursor()
{
    ; SPI_SETCURSORS：让系统从注册表重新载入光标
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
}


; =============================================================
;  解析 install.inf
;
;  标准格式：
;    [Wreg]
;    HKCU,"Control Panel\Cursors",Arrow,0x00020000,"%10%\%CUR_DIR%\%pointer%"
;    [Strings]
;    pointer = "normal.ani"
;
;  先读 [Strings] 里的变量，替换掉 %xxx%，再取文件名去主题文件夹里找。
;  如果没有逐项写法，就退而读 Schemes 那一行（17 个文件按固定顺序排列）。
; =============================================================

ParseInf(folder)
{
    map := {}

    inf := ""
    Loop, Files, %folder%\*.inf
    {
        inf := A_LoopFileFullPath
        break
    }
    if (inf = "")
        return map

    FileRead, text, %inf%
    if (ErrorLevel)
        return map

    strs := {}
    lines := []
    section := ""
    Loop, Parse, text, `n, `r
    {
        line := Trim(A_LoopField)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        if (RegExMatch(line, "^\[(.+)\]$", sm))
        {
            section := Trim(sm1)
            continue
        }
        if (section = "Strings")
        {
            if (RegExMatch(line, "^([^=]+?)\s*=\s*(.*)$", km))
                strs[Trim(km1)] := StripQuotes(km2)
        }
        else
            lines.Push(line)
    }

    ; 方式一：逐项写法
    for i, line in lines
    {
        if (RegExMatch(line, "i)^(?:HKCU|HKEY_CURRENT_USER)\s*,\s*""?Control Panel\\Cursors""?\s*,\s*""?([A-Za-z]+)""?\s*,[^,]*,\s*(.+)$", m))
        {
            t := CanonicalType(m1)
            if (t = "")
                continue
            f := ResolveFile(folder, ExpandInf(StripQuotes(m2), strs))
            if (f != "")
                map[t] := f
        }
    }
    if (map.Count() > 0)
        return map

    ; 方式二：Schemes 行
    for i, line in lines
    {
        if (RegExMatch(line, "i)^(?:HKCU|HKEY_CURRENT_USER)\s*,\s*""?Control Panel\\Cursors\\Schemes""?\s*,[^,]*,[^,]*,\s*(.+)$", m))
        {
            list := ExpandInf(StripQuotes(m1), strs)
            for j, p in StrSplit(list, ",")
            {
                if (j > cursorTypes.Length())
                    break
                f := ResolveFile(folder, p)
                if (f != "")
                    map[cursorTypes[j]] := f
            }
            break
        }
    }
    return map
}

; 去掉引号；没引号的话去掉行尾注释
StripQuotes(s)
{
    s := Trim(s)
    if (SubStr(s, 1, 1) = """")
    {
        p := InStr(s, """", false, 2)
        return p ? SubStr(s, 2, p - 2) : SubStr(s, 2)
    }
    p := InStr(s, ";")
    if (p)
        s := SubStr(s, 1, p - 1)
    return Trim(s)
}

; 替换 %变量%（可能嵌套，最多展开 5 层）
ExpandInf(s, strs)
{
    Loop, 5
    {
        out := ""
        pos := 1
        while (p := RegExMatch(s, "%([^%]*)%", m, pos))
        {
            out .= SubStr(s, pos, p - pos)
            if (m1 = "")
                rep := "%"
            else if (m1 = "10")
                rep := A_WinDir
            else if (strs.HasKey(m1))
                rep := strs[m1]
            else
                rep := m
            out .= rep
            pos := p + StrLen(m)
        }
        out .= SubStr(s, pos)
        if (out == s)
            break
        s := out
    }
    return s
}

; inf 里写的是安装后的路径，只取文件名，到主题文件夹（含子文件夹）里找
ResolveFile(folder, path)
{
    path := Trim(path)
    if (path = "")
        return ""
    SplitPath, path, fname
    if (fname = "")
        return ""
    direct := folder "\" fname
    if (FileExist(direct))
        return direct
    Loop, Files, %folder%\%fname%, R
        return A_LoopFileFullPath
    return ""
}

CanonicalType(name)
{
    for i, t in cursorTypes
        if (t = name)
            return t
    return ""
}


; =============================================================
;  导入当前系统光标为主题
;
;  用于只提供安装程序（exe）的主题：先用它自带的安装程序装好并应用，
;  再点这个菜单，把系统当前正在用的光标文件复制到 themes 里，
;  并自动生成一份 install.inf。
; =============================================================

ImportCurrent:
    ; 先暂停，免得导入途中被自动轮换覆盖
    wasPaused := paused
    SetPaused(true)

    RegRead, scheme, HKCU\Control Panel\Cursors
    if (ErrorLevel || scheme = "")
        scheme := "导入的主题"

    InputBox, newName, 导入当前系统光标, 会把系统当前正在使用的光标复制到 themes 文件夹。`n给这套主题起个名字：, , 360, 160, , , , , %scheme%
    if (ErrorLevel)
    {
        SetPaused(wasPaused)
        Return
    }

    result := ImportCurrentCursors(newName)
    SetPaused(wasPaused)

    if (result = "fromThemes")
        TrayTip, Random Cursor, 当前光标本来就是 themes 里的主题。`n请先用那套主题自带的安装程序应用一次，再导入。, 6
    else if (result = 0)
        TrayTip, Random Cursor, 没有找到可以导入的光标文件。, 4
    else
        TrayTip, Random Cursor, 已导入 %result% 种指针。, 4
Return


ImportCurrentCursors(newName)
{
    newName := Trim(RegExReplace(newName, "[\\/:*?""<>|]", "_"))
    if (newName = "")
        newName := "导入的主题"

    ; 收集当前每种指针的文件
    found := {}
    total := 0
    inThemes := 0
    for i, t in cursorTypes
    {
        RegRead, val, HKCU\Control Panel\Cursors, %t%
        if (ErrorLevel || val = "")
            continue
        path := ExpandEnv(val)
        if (!FileExist(path))
            continue
        total += 1
        if (InStr(path, themesDir "\") = 1)
            inThemes += 1
        found[t] := path
    }
    if (total = 0)
        return 0
    if (inThemes = total)
        return "fromThemes"

    ; 目标文件夹重名时加编号
    dest := themesDir "\" newName
    n := 1
    while (FileExist(dest))
    {
        n += 1
        dest := themesDir "\" newName " (" n ")"
    }
    FileCreateDir, %dest%

    copied := {}
    inf := "[Version]`r`nsignature=""$CHICAGO$""`r`n`r`n[Wreg]`r`n"
    count := 0
    for i, t in cursorTypes
    {
        if (!found.HasKey(t))
            continue
        src := found[t]
        SplitPath, src, fname
        ; 不同来源的同名文件，前面加上指针类型区分
        if (copied.HasKey(fname) && copied[fname] != src)
            fname := t "_" fname
        if (!copied.HasKey(fname))
        {
            FileCopy, %src%, %dest%\%fname%, 1
            if (ErrorLevel)
                continue
            copied[fname] := src
        }
        inf .= "HKCU,""Control Panel\Cursors""," t ",0x00020000,""" fname """`r`n"
        count += 1
    }

    if (count = 0)
    {
        FileRemoveDir, %dest%, 1
        return 0
    }

    FileAppend, %inf%, %dest%\install.inf, UTF-16
    SplitPath, dest, destName
    Log("导入当前光标为主题：" destName "（" count " 种指针）")

    LoadThemes()
    bag := []
    return count
}

; 展开 %SystemRoot% 这类环境变量
ExpandEnv(s)
{
    VarSetCapacity(buf, 65536, 0)
    DllCall("ExpandEnvironmentStrings", "Str", s, "Str", buf, "UInt", 32767)
    return buf
}


; =============================================================
;  没有 inf 时：按文件名识别（英文 / 中文常见命名）
; =============================================================

GuessByFilename(folder)
{
    map := {}
    ; 先 .cur 后 .ani，同一种指针两种都有时动态的 .ani 优先
    for i, ext in ["cur", "ani"]
    {
        Loop, Files, %folder%\*.%ext%, R
        {
            SplitPath, A_LoopFileName, , , , nameNoExt
            t := GuessType(nameNoExt)
            if (t != "")
                map[t] := A_LoopFileFullPath
        }
    }
    return map
}

GuessType(name)
{
    ; 顺序有讲究：Handwriting 要在 Hand 之前，UpArrow 要在 Arrow 之前
    static rules := [["NWPen", "handwrit|nwpen|^pen$|手写"]
        , ["AppStarting", "working|appstart|background|后台"]
        , ["Wait", "busy|wait|忙"]
        , ["Help", "help|帮助"]
        , ["Crosshair", "precision|crosshair|cross|精确|十字"]
        , ["IBeam", "text|ibeam|beam|文本|文字"]
        , ["No", "unavailable|unavail|forbidden|^no$|不可用|禁止"]
        , ["Pin", "^pin$|location|位置"]
        , ["Person", "person|个人"]
        , ["SizeNS", "vertical|sizens|^ns$|垂直"]
        , ["SizeWE", "horizontal|sizewe|^we$|水平"]
        , ["SizeNWSE", "diag\D*1|dgn\D*1|nwse|对角\D*1"]
        , ["SizeNESW", "diag\D*2|dgn\D*2|nesw|对角\D*2"]
        , ["SizeAll", "move|sizeall|移动"]
        , ["UpArrow", "alternate|uparrow|^alt|候选|备用"]
        , ["Hand", "link|hand|链接"]
        , ["Arrow", "normal|arrow|pointer|default|正常|标准"]]

    StringLower, n, name
    n := RegExReplace(n, "[\s_\-\.\(\)\[\]]+")   ; 去掉空格和符号
    n := RegExReplace(n, "^\d+")                 ; 去掉开头编号，如 01normal
    for i, r in rules
        if (RegExMatch(n, r[2]))
            return r[1]
    return ""
}
