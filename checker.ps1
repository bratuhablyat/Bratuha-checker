# =============================================================================
#  Bratuha - OFICJALNY SKRYPT SPRAWDZANIA (screenshare)
#  Zrodlo: https://sprawdzanie.Bratuha
# -----------------------------------------------------------------------------
#  UWAGA: caly plik jest celowo bez polskich ogonkow i bez zadnej obfuskacji,
#  zebys mogl przeczytac kazda linijke i miec pewnosc, co sie dzieje.
# -----------------------------------------------------------------------------
#  CO TEN SKRYPT ROBI:
#    - odczytuje pamiec uruchomionego procesu Minecrafta (javaw.exe / java.exe)
#    - szuka w niej sygnatur znanych cheatow (jawna lista nizej)
#    - wypisuje wynik na ekran wraz z adresem, pod ktorym znalazl trafienie
#
#  CZEGO TEN SKRYPT NIE ROBI (sprawdz sam - Ctrl+F w tym pliku):
#    - NIE laczy sie z internetem  (brak: Invoke-WebRequest, Invoke-RestMethod,
#      Net.WebClient, DownloadString, curl, wget, Start-BitsTransfer, HttpClient)
#    - NIE czyta plikow z kontami/haslami/sesjami (brak: launcher_accounts.json,
#      launcher_profiles.json, usercache, .minecraft, AppData, Credentials)
#    - NIE uruchamia innych programow (brak: Start-Process, cmd.exe)
#    - NIE zapisuje, nie modyfikuje i nie usuwa zadnych plikow
#    - NIE prosi o haslo, kod z e-maila ani o zadne dane
#
#  UCZCIWA UWAGA O "iex":
#    Sam skrypt nie wywoluje iex ani Invoke-Expression - nie znajdziesz ich
#    ponizej poza tym komentarzem. Ale jesli wkleiles wariant jednolinijkowy
#    ("cala komenda" ze strony), to zaczyna sie on od:
#          iex (( ...linie tego skryptu... ) -join "`n")
#    Ten iex skleja z powrotem i uruchamia DOKLADNIE ten tekst, ktory masz
#    przed soba - nie pobiera niczego z sieci i nie siega po zaden inny kod.
#    Nie chcemy udawac, ze go tam nie ma: opis ma sie zgadzac z kodem.
#
#  Skrypt otwiera proces gry z minimalnymi uprawnieniami: TYLKO ODCZYT pamieci
#  (PROCESS_VM_READ | PROCESS_QUERY_INFORMATION). Nic nie zapisuje do gry.
# =============================================================================

$ErrorActionPreference = 'Stop'

$SCRIPT_VERSION = '2.2.0'
$SCRIPT_BRAND   = 'Bratuha'
$SCRIPT_SOURCE  = 'https://sprawdzanie.Bratuha'
$SCRIPT_TOKEN   = ''   # token usunięty przed publikacją

# =============================================================================
#  KROK 0 - KONTROLA UCZCIWOSCI SESJI
#  Sprawdzamy, czy ktos nie podmienil w tej sesji PowerShell komend, ktorych
#  uzywamy (klasyczny sposob oszukania screenshare'a). Odwolujemy sie do
#  silnika PowerShell bezposrednio, bo samo Get-Command tez da sie podmienic.
# =============================================================================
$__integrity = @()

if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    $__integrity += "Tryb jezyka PowerShell: $($ExecutionContext.SessionState.LanguageMode) (oczekiwano FullLanguage)"
}

$__expected = @{
    'Get-Process'    = 'Microsoft.PowerShell.Management'
    'Add-Type'       = 'Microsoft.PowerShell.Utility'
    'Write-Host'     = 'Microsoft.PowerShell.Utility'
    'Get-Date'       = 'Microsoft.PowerShell.Utility'
    'Sort-Object'    = 'Microsoft.PowerShell.Utility'
    'Measure-Object' = 'Microsoft.PowerShell.Utility'
    'ForEach-Object' = 'Microsoft.PowerShell.Core'
    'Get-History'    = 'Microsoft.PowerShell.Core'
}
foreach ($__n in $__expected.Keys) {
    $__c = $ExecutionContext.InvokeCommand.GetCommand($__n, [System.Management.Automation.CommandTypes]::All)
    if ($null -eq $__c) {
        $__integrity += "Brak komendy $__n"
    } elseif ($__c.CommandType -ne [System.Management.Automation.CommandTypes]::Cmdlet -or
              $__c.ModuleName -ne $__expected[$__n]) {
        $__integrity += "Komenda $__n zostala podmieniona w tej sesji ($($__c.CommandType))"
    }
}

# Klasa skanera dostaje losowa nazwe przy KAZDYM pobraniu skryptu z serwera.
# Jesli typ o tej nazwie juz istnieje, ktos probowal go podstawic wczesniej.
if (([System.Management.Automation.PSTypeName]'K9ADBE3DD8413').Type) {
    $__integrity += 'Typ K9ADBE3DD8413 juz istnieje w tej sesji (proba podstawienia falszywego skanera)'
}

# =============================================================================
#  Rysowanie interfejsu
# =============================================================================
$Unicode = $true
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { $Unicode = $false }
try { $Host.UI.RawUI.WindowTitle = "Bratuha - Sprawdzanie v$SCRIPT_VERSION" } catch { }

if ($Unicode) {
    $G = @{
        DTL = [char]0x2554; DTR = [char]0x2557; DBL = [char]0x255A; DBR = [char]0x255D
        DH  = [char]0x2550; DV  = [char]0x2551
        TL  = [char]0x250C; TR  = [char]0x2510; BL  = [char]0x2514; BR  = [char]0x2518
        H   = [char]0x2500; V   = [char]0x2502; ML  = [char]0x251C; MR  = [char]0x2524
        FULL= [char]0x2588; HALF= [char]0x2591; DOT = [char]0x00B7; ELL = [char]0x2026
        OK  = [char]0x2714; BAD = [char]0x2718; WARN= [char]0x0021
    }
} else {
    $G = @{
        DTL='+'; DTR='+'; DBL='+'; DBR='+'; DH='='; DV='|'
        TL='+'; TR='+'; BL='+'; BR='+'; H='-'; V='|'; ML='+'; MR='+'
        FULL='#'; HALF='-'; DOT='.'; ELL='~'; OK='+'; BAD='x'; WARN='!'
    }
}

$W  = 78          # szerokosc ramki
$IN = $W - 2      # szerokosc wnetrza ramki
$PAD = ' '        # wciecie od lewej krawedzi konsoli

function Fit([string]$Text, [int]$Len) {
    if ($null -eq $Text) { $Text = '' }
    if ($Text.Length -le $Len) { return $Text.PadRight($Len) }
    return $Text.Substring(0, [Math]::Max(1, $Len - 1)) + $G.ELL
}

function Box-Top([string]$Title, [string]$Color = 'DarkGray', [switch]$Double) {
    $tl = $(if ($Double) { $G.DTL } else { $G.TL })
    $tr = $(if ($Double) { $G.DTR } else { $G.TR })
    $h  = $(if ($Double) { $G.DH }  else { $G.H  })
    if ($Title) {
        $label = " $Title "
        $rest  = $IN - 1 - $label.Length
        if ($rest -lt 0) { $rest = 0 }
        Write-Host ($PAD + $tl + [string]$h) -ForegroundColor $Color -NoNewline
        Write-Host $label -ForegroundColor White -NoNewline
        Write-Host (([string]$h * $rest) + $tr) -ForegroundColor $Color
    } else {
        Write-Host ($PAD + $tl + ([string]$h * $IN) + $tr) -ForegroundColor $Color
    }
}

function Box-Bottom([string]$Color = 'DarkGray', [switch]$Double) {
    $bl = $(if ($Double) { $G.DBL } else { $G.BL })
    $br = $(if ($Double) { $G.DBR } else { $G.BR })
    $h  = $(if ($Double) { $G.DH }  else { $G.H  })
    Write-Host ($PAD + $bl + ([string]$h * $IN) + $br) -ForegroundColor $Color
}

function Box-Sep([string]$Color = 'DarkGray') {
    Write-Host ($PAD + $G.ML + ([string]$G.H * $IN) + $G.MR) -ForegroundColor $Color
}

# Segmenty: @( @{T='tekst'; C='Kolor'}, ... ) - reszta linii dopelniana spacjami
function Box-Row([object[]]$Segments, [string]$Color = 'DarkGray', [switch]$Double) {
    $v = $(if ($Double) { $G.DV } else { $G.V })
    $len = 0
    foreach ($s in $Segments) { $len += $s.T.Length }
    Write-Host ($PAD + $v) -ForegroundColor $Color -NoNewline
    foreach ($s in $Segments) {
        $c = $s.C; if (-not $c) { $c = 'Gray' }
        Write-Host $s.T -ForegroundColor $c -NoNewline
    }
    $fill = $IN - $len
    if ($fill -lt 0) { $fill = 0 }
    Write-Host ((' ' * $fill) + $v) -ForegroundColor $Color
}

function Box-Empty([string]$Color = 'DarkGray', [switch]$Double) {
    Box-Row @(@{ T = ''; C = 'Gray' }) $Color -Double:$Double
}

function Box-Field([string]$Label, [string]$Value, [string]$ValueColor = 'White') {
    Box-Row @(
        @{ T = '  ' + (Fit $Label 14); C = 'DarkGray' },
        @{ T = $Value;                 C = $ValueColor }
    )
}

function Write-Banner {
    # Dopelnienie liczone z faktycznych dlugosci segmentow, a nie wpisane na
    # sztywno - nazwa serwera jest podstawiana przy pobraniu i moze miec
    # dowolna dlugosc.
    $segBrand = '   ' + $SCRIPT_BRAND
    $segDot   = '   ' + [string]$G.DOT + '   '
    $segTitle = 'OFICJALNE SPRAWDZANIE KLIENTA'
    $segVer   = 'v' + $SCRIPT_VERSION
    # UWAGA: nie nazywac tej zmiennej $pad - PowerShell ignoruje wielkosc liter,
    # wiec nadpisalaby globalne $PAD (wciecie ramki), a funkcje wywolywane nizej
    # dziedzicza zakres wywolujacego i dostalyby liczbe zamiast spacji.
    $gap = $IN - $segBrand.Length - $segDot.Length - $segTitle.Length - $segVer.Length - 1
    if ($gap -lt 1) { $gap = 1 }

    Write-Host ''
    Box-Top '' 'DarkCyan' -Double
    Box-Row @(
        @{ T = $segBrand;                C = 'Cyan' },
        @{ T = $segDot;                  C = 'DarkCyan' },
        @{ T = $segTitle;                C = 'White' },
        @{ T = ((' ' * $gap) + $segVer); C = 'DarkCyan' }
    ) 'DarkCyan' -Double
    Box-Bottom 'DarkCyan' -Double
}

function Write-Verdict([string]$Title, [string]$Sub, [string]$Bg, [string]$Fg) {
    $line = ' ' * $W
    Write-Host ''
    Write-Host ($PAD + $line) -BackgroundColor $Bg -ForegroundColor $Fg
    Write-VerdictLine $Title $Bg $Fg
    if ($Sub) { Write-VerdictLine $Sub $Bg $Fg }
    Write-Host ($PAD + $line) -BackgroundColor $Bg -ForegroundColor $Fg
    Write-Host ''
}

# Wysrodkowanie z DOKLADNIE rownym odstepem po obu stronach. Gdy margines
# wychodzi nieparzysty, tekst dostaje jedna spacje - inaczej blok przechyla
# sie o jeden znak i odstepy wygladaja na rozjechane.
function Write-VerdictLine([string]$Text, [string]$Bg, [string]$Fg) {
    $t = $Text
    if ($t.Length -gt $W) { $t = $t.Substring(0, $W) }
    if ((($W - $t.Length) % 2) -eq 1) { $t = $t + ' ' }
    $side = ($W - $t.Length) / 2
    Write-Host ($PAD + (' ' * $side) + $t + (' ' * ($W - $side - $t.Length))) -BackgroundColor $Bg -ForegroundColor $Fg
}

function Show-Progress([int]$Percent, [string]$Label, [int]$Mb, [double]$Seconds) {
    $barW = 30
    $fill = [int]($barW * $Percent / 100)
    if ($fill -gt $barW) { $fill = $barW }
    if ($fill -lt 0)     { $fill = 0 }
    $bar = ([string]$G.FULL * $fill) + ([string]$G.HALF * ($barW - $fill))
    $speed = 0
    if ($Seconds -gt 0.2) { $speed = [int]($Mb / $Seconds) }
    Write-Host ("`r" + $PAD + ' ') -NoNewline
    Write-Host $bar -ForegroundColor Cyan -NoNewline
    Write-Host ("  {0,3}%  " -f $Percent) -ForegroundColor White -NoNewline
    Write-Host ("{0,-22} {1,6} MB  {2,5} MB/s   " -f $Label, $Mb, $speed) -ForegroundColor DarkGray -NoNewline
}

function Write-Footer([string]$SessionId, [datetime]$Started) {
    Box-Top 'BEZPIECZENSTWO' 'DarkGray'
    Box-Row @(@{ T = '  Dla bezpieczenstwa mozesz skopiowac ze strony CALA komende -'; C = 'White' })
    Box-Row @(@{ T = '  caly skrypt w jednej linii. Wtedy nic nie jest pobierane'; C = 'White' })
    Box-Row @(@{ T = '  z sieci, a przed wklejeniem widzisz dokladnie to, co uruchamiasz.'; C = 'White' })
    Box-Row @(@{ T = ('     ' + $SCRIPT_SOURCE); C = 'Cyan' })
    Box-Empty
    Box-Row @(@{ T = '  Jesli ktokolwiek kaze Ci wpisac INNA komende - odmow i zglos to.'; C = 'Gray' })
    Box-Row @(@{ T = '  Administracja NIGDY nie prosi o haslo, kod z e-maila ani plik'; C = 'Gray' })
    Box-Row @(@{ T = '  z konta. Adres wpisuj recznie, nie z prywatnej wiadomosci.'; C = 'Gray' })
    Box-Sep
    Box-Row @(
        @{ T = '  Kod sesji '; C = 'DarkGray' }, @{ T = (Fit $SessionId 10); C = 'Yellow' },
        @{ T = 'Token '; C = 'DarkGray' },      @{ T = (Fit $SCRIPT_TOKEN 22); C = 'Yellow' },
        @{ T = $Started.ToString('yyyy-MM-dd HH:mm'); C = 'DarkGray' }
    )
    Box-Row @(@{ T = ('  Weryfikacja tokenu: ' + $SCRIPT_SOURCE + '/weryfikacja'); C = 'DarkGray' })
    Box-Bottom
    Write-Host ''
}

# =============================================================================
#  SYGNATURY - jawna lista szukanych ciagow znakow ("kodow")
#  Level: H = pewne wykrycie, L = poszlaka (krotki ciag, mozliwy falszywy alarm)
# =============================================================================
$SIGNATURES = @(
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Nursultan';            Level = 'H'; Pattern = 'nursultan' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Ventura Client';       Level = 'H'; Pattern = 'eu/venturaclient/misc/misc/GameAccessor.classPK' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Azure (peleryna)';     Level = 'H'; Pattern = '/assets/anamvmnt/textures/capes/custom/azure.png' },
    # Korzenie pakietow klientow. Kazdy z nich jest podciagiem setek wariantow
    # z surowych list (np. 'su/catlean' zawiera sie w 2403 wzorcach Catleana),
    # wiec wykrywa dokladnie to samo przy 2403 razy mniejszym koszcie skanu.
    # Wszystkie zweryfikowane na czystym kliencie: zero trafien.
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Catlean';              Level = 'H'; Pattern = 'su/catlean' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Meteor Client';        Level = 'H'; Pattern = 'meteordevelopment/meteorclient' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Vanadium';             Level = 'H'; Pattern = 'nl/vanadium' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Vanadium (JNI)';       Level = 'H'; Pattern = 'nl_vanadium' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Vanadium (vanahui)';   Level = 'H'; Pattern = 'vanahui' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Ventura (pakiet)';     Level = 'H'; Pattern = 'venturaclient' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Ventura (candyman)';   Level = 'H'; Pattern = 'candyman/' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'ThunderHack';          Level = 'H'; Pattern = 'ThunderHack' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Aristois';             Level = 'H'; Pattern = 'aristois' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'BleachHack';           Level = 'H'; Pattern = 'BleachHack' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Wurst';                Level = 'H'; Pattern = 'Wurst' },
    # Cheat nazwany tak samo jak anticheat Grim (celowo, dla zmylki).
    # Samo slowo "grim" jest bezuzyteczne jako sygnatura - to zwykle slowo
    # i trafia w czystym kliencie. Uzywamy korzenia jego pakietu.
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Grim (cheat)';         Level = 'H'; Pattern = 'sixfive/' },
    # Nazwy projektow wydobyte z surowych list (assets/<nazwa>/, handler$..$<nazwa>$,
    # dev/<nazwa>/, <nazwa>:textures/) i zweryfikowane na czystym kliencie.
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Nerith';               Level = 'H'; Pattern = 'nerith' },
    # 'jnic' bez kotwicy ma 4 znaki - taki ciag malych liter trafia sie w kazdym
    # dluzszym tekscie base64 i w danych binarnych. Uzywamy form z separatorem.
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Vanadium (jnic /)';    Level = 'H'; Pattern = 'dev/jnic/' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Vanadium (jnic .)';    Level = 'H'; Pattern = 'dev.jnic.' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Vanadium (jnicLoader)'; Level = 'H'; Pattern = 'jnicLoader' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Kausel';               Level = 'H'; Pattern = 'kausel' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Dqrkis';               Level = 'H'; Pattern = 'dqrkis' },
    # USUNIETE: 'failedtion'. W calym zrodle wystepowalo RAZ, jako 'failedtion/codecs',
    # w regionie czystych smieci binarnych obok tablicy znakow czcionki i kodu Java2D.
    # To sklejka dwoch sasiednich ciagow ('...failed' + 'serialization/codecs'),
    # a nie nazwa klienta - nie ma czego wykrywac.
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Anamvmnt';             Level = 'H'; Pattern = 'anamvmnt' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Meteor (pakiet)';      Level = 'H'; Pattern = 'meteordevelopment' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Starscript (Meteor)';  Level = 'L'; Pattern = 'starscript' },
    # Crack (np. zlamana wersja Grima). UWAGA: samo '.crack' jest bezuzyteczne -
    # trafia w waniliowe klucze Minecrafta (block.minecraft.cracked_nether_bricks,
    # item.wolf_armor.crack, block.sniffer_egg.crack), czyli u kazdego gracza.
    # Dzialaja tylko formy z separatorem sciezki/archiwum - zweryfikowane czyste.
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Crack (katalog)';      Level = 'L'; Pattern = '/crack/' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Crack (plik w jarze)'; Level = 'L'; Pattern = '.crackPK' },
    @{ Cat = 'KLIENCI CHEATOW';   Name = 'Crack (pakiet)';       Level = 'L'; Pattern = '.crack.' },
    @{ Cat = 'HOOKI I MIXINY';    Name = 'Mixin renderFire';     Level = 'H'; Pattern = 'renderFire(Lorg/spongepowered/asm/mixin/injection/callback/CallbackInfo;)V' },
    @{ Cat = 'HOOKI I MIXINY';    Name = 'sendMovementPackets';  Level = 'H'; Pattern = 'Lnet/minecraft/client/network/ClientPlayerEntity;sendMovementPackets()V' },
    @{ Cat = 'HOOKI I MIXINY';    Name = 'Shader blur GUI';      Level = 'H'; Pattern = 'GUI_BEFORE_PRE_BLUR0v' },
    # 'CoreWindowSite' zamiast 'DestructCoreWindowSite' - jest podciagiem tamtej
    # i dodatkowo lapie warianty CoreWindowSite::Invoke..., ::remove_..., ...HideComponent.
    @{ Cat = 'SYGNATURY PAMIECI'; Name = 'CoreWindowSite';       Level = 'H'; Pattern = 'CoreWindowSite' },
    # USUNIETE: 'jose4j', 'getX509CertificateSha256Thumbprint', 'EcdsaSECP256K1UsingSha256'.
    # To nazwy z biblioteki jose4j (JSON Web Token) - w zrodlowych listach wystepuja
    # jako 'org/jose4j/jwe/...', czyli zwykla sciezka biblioteki. Zawieraja ja
    # launchery logujace sie na konto Microsoft, dlatego trafialy w proces java.exe
    # launchera na wielu komputerach. Obecnosc tej biblioteki niczego nie dowodzi.
    @{ Cat = 'SYGNATURY PAMIECI'; Name = 'setWasTouchingWaterH'; Level = 'H'; Pattern = 'setWasTouchingWaterH' },
    @{ Cat = 'SYGNATURY PAMIECI'; Name = 'uv_quad_color';        Level = 'L'; Pattern = 'uv_quad_color' },
    @{ Cat = 'SYGNATURY PAMIECI'; Name = 'IORegistryEntry';      Level = 'H'; Pattern = 'IORegistryEntryGetChildEntry' },
    @{ Cat = 'SYGNATURY PAMIECI'; Name = 'Sygnatura #1';         Level = 'H'; Pattern = 'LLLeLLCLLL23L3' },
    @{ Cat = 'SYGNATURY PAMIECI'; Name = 'Sygnatura #2';         Level = 'H'; Pattern = 'i4fCf.G5.MyZdu^Z2l' },
    @{ Cat = 'SYGNATURY PAMIECI'; Name = 'Sygnatura #3';         Level = 'H'; Pattern = 'BW_s_QfMHBRVQSGKa]Z' },
    @{ Cat = 'SYGNATURY PAMIECI'; Name = 'Sygnatura #4';         Level = 'H'; Pattern = 'DqFETsH_bDCOcsu' },
    @{ Cat = 'SYGNATURY PAMIECI'; Name = 'Sygnatura #5';         Level = 'H'; Pattern = 'yHKHMAYcdi' },
    @{ Cat = 'SYGNATURY PAMIECI'; Name = 'Sygnatura #6';         Level = 'L'; Pattern = 'tWJ]yX' },
    @{ Cat = 'SYGNATURY PAMIECI'; Name = 'Sygnatura #7';         Level = 'L'; Pattern = 'aaa.bbb' }
)

# --- Sygnatury Doomsday (surowe wzorce pamieci) ------------------------------
# Single-quoted here-string: wszystko literalnie (backtick, $, ", ' bez escapowania).
# Kazda linia = jeden szukany ciag. Duplikaty usuwane w czasie dzialania.
$DOOMSDAY = @'
xVl,#WK
#@_]D$f7+:!s
8\cW!0voReLAd;
Dwm2V[Kw
]yBU]Ick
+$_s&BL P
pkohge\_
^Dk_gZblK
![D'W7&
YS<3]_$],4 1_dNp&q
:b_feVh8WbFW
HOEHv3xZ
OV$\@jgxo&q1Wv\EW(
xiO_kZEdFglDch
hn#^K=9e52ijC
i2nkhYbY
CkN^dlN32F
&)<j"haVWOJx
4(hN8Bx]L?;l",
f8784xiskN"ne^V
[TNxWnxPMCbondnQ[Y
jM'[A+Ax0"_%y1MCu
CEy>KpT!\%*
XLwOSiLwav
-7=5TxR+d6[3j]
xrp6#_h^
N#h$C\Y[L<\w
q[HlxCjGqOteW\FdaTD
mVQtRYJCLk
QEfOGhLDM
ClUbCwMCJ^ZAId
n,[*aeje
9Lr?[*"
WdKtG\n[YB_\a
dNaGBibtWfaqO
JxkgkyPQS
r[R[HZKclxU
R]jntXLF]
Wb[TloBx
dFyrkeI
yokosJiM
"U`,kGZ8G@URL
rKo4mNjg<(!Y^fI^DJ
=n>V$dB
NW+I+:Lm1TI*mtv&(
3]3+b^sq
JZ^A\WH[HL[
JDRvLaSjiw),b
a*e2mJhy
bxi[wI_srfBl
OPobmcf[MP
JvHCS"*M36a7 (@jHQ
T>2W,EpwdbH
aimx'J teX&
qdBR&.via
Wi[CNhp`[G
IGmEr_AWn\
ZOBCi#o
-CTjSrSV>uj1Z Ex h(
wcmlSiv[mE`Uyp
E[YcZADEJdZBS
ElBjGpSAMDVa
iaDpJPivdmXGDZ`
R,CEpZl:.MF$j
AtcQpWYE`UhnGt
/ZC8sXuRkJ6i5S9*q
dn1!O_;
"!J(#Z(
BkQsWTYbqOVP
AJteTVHW
?,#/HS2*a2&AyF]
K[Se83$u8M r0$[\a
c:V=$K"P#+QO<`Hf=J[
xnAcY]eqGJDtSdmjhJt
a6?%C1)a
50!mFty,B`6H[F`ib
_f7EB@=SCtE(km
?df&F'c<r!0?uWZ
!'umTmjN0hiWu-
:w/p'6`WA$.V@MB>
3D"YKaL-X<u;
HoJ>CE0?
VTm\ZWTPN^ueY
ynAFC`vqR
hrdS`E_AdP
y)Y#$/#]
BxhbHNt`g
cs8?hbJ)/W)
YOFXguQiDUs
EbpHlUWjlDPvlcRT
L;;<**<>L<
3KlFEF %
HsvYmnXJbrvk^EM`
.`]2S'8P*\
BXM7LE9K
7CTqc(K-i[e]6RH
8iPyo?L!?8+;uH&U
-csV1xiXfWlVHR\a9M
^NOJXfrg
vTqLhqmjemo`
avuKOfIUmAEUQ
uJtxDyLtJ`Mh
TU\vebgkJdfH
!&cWI2d'<m@m"sT03Ky
&ueGp?j?+BX%
\WJ;B9Y!so+-i
UnJUh`Fa_W
(RYor`Id%&8e_W6A
FaypNWKaeAJK[BGY
#p's"RCk
Mh\`CfHWyWaDlStk
#;Nq[2<
UdWmF:MFJK'W,aO4
mPC#M[c
aIVJiy\
WMZSCnYnUYWO
#"x#SY&s
dcGQ^xPsaQJ
Rlr]aLg
9guHdM,"l
K6LaM6t:AU
\VIFDCpHe
nBmtQifkPA`O_hJq\
+0!E4JZ3K$.8d
'@

# Dopisanie sygnatur Doomsday do listy (dedup wzgledem juz istniejacych, Ordinal)
$__seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($__s in $SIGNATURES) { [void]$__seen.Add($__s.Pattern) }
$__all = New-Object System.Collections.ArrayList
foreach ($__s in $SIGNATURES) { [void]$__all.Add($__s) }
$__dn = 0
foreach ($__line in ($DOOMSDAY -split "`n")) {
    $__p = $__line -replace "`r$", ''
    if ($__p.Length -eq 0) { continue }
    if (-not $__seen.Add($__p)) { continue }
    $__dn++
    [void]$__all.Add(@{
        Cat     = 'DOOMSDAY'
        Name    = ('Doomsday #{0}' -f $__dn)
        Level   = $(if ($__p.Length -lt 8) { 'L' } else { 'H' })
        Pattern = $__p
        Bulk    = $true
    })
}
# --- Poszlaki -----------------------------------------------------------------
# Wzorce wydobyte z surowych zrzutow pamieci cheatow. Kazdy przeszedl test na
# czystym kliencie (zero trafien), ma strukture artefaktu Javy/Minecrafta i nie
# zawiera sladu popularnych modow. Mimo to wchodza WYLACZNIE jako poszlaki
# (zolte PODEJRZANE) - pochodza z jednego zrzutu i nie sa dowodem same w sobie.
$POSZLAKI = @'
Ldev/jnic/LDQFbx/G;
Ldev/jnic/LDQFbx/U;
Ldev/jnic/LDQFbx/B;
Ldev/jnic/LDQFbx/f;
Ldev/jnic/LDQFbx/w;
Ldev/jnic/LDQFbx/C;
frames/0132.png?
Ldev/jnic/LDQFbx/n;
*mnopqrstuvwf/0
sounds/patchern.ogg
!25G/CFGPWZGfmpGj
!25G/ILG?Y\GVwzGf
jdk/proxy3/$Proxy59
block/christmas_hat
/2D<FIDCY\Dfy|Dv
textures/hat.png
/'$25X.EHXdvyXs
sounds/roxmboff.ogg
/2o)BEo<RUofpsom
9<p/ILpFXXpbnqp{
/register_key?key=
sounds/roxmbon.ogg
/9<Y4NQYGbeY\ssYsY
sounds/daszek.ogg
1\/N?FcUgO]NX
,/r9FIr=TWraknr
failedtion/codecs
/checktest?data=
nl/cU$$Lambda
assets/nerith/PK
/getlist?data=
sounds/baka.ogg
//TBNQTH]`TouuT
nl/g.classPK
nl/cU.classPK
nl/f.classPK
nl/h.classPK
58T/EHTRYYTiooT
nl.vanadium.mixin.
nl/cT.classPK
58l/EHlRYYldqql
nl.vanadium.mixin
/velaris/native
/assets/nerith
/sounds/a.ogg
/nl/cU.class
/nl/cT.class
dev/jnic/LDQFbx/JNICLoader.classPK
/dev/jnic/LDQFbx/JNICLoader.class
nerith:textures/particle/snowflake1.png
nerith:textures/jumpcircle/vajfon.png
dev/jnic/LDQFbx/G.classPK
dev/jnic/LDQFbx/JNICLoader
dev/jnic/LDQFbx/w.classPK
dev/jnic/LDQFbx/R.classPK
dev/jnic/LDQFbx/N.classPK
dev/jnic/LDQFbx/f.classPK
ClN)QS/"V<K^CiJeUQ9<ZgG_C
dev/jnic/LDQFbx/W.classPK
dev/jnic/LDQFbx/U.classPK
dev/jnic/LDQFbx/C.classPK
handler$zbf001$dqrkis$onAttack
dev/jnic/LDQFbx/B.classPK
nl.vanadium.mixin.LivingEntityAccessor
assets/minecraft/sounds/roxmbon.oggPK
dev/jnic/LDQFbx/c.classPK
assets/minecraft/sounds/baka.oggPK
assets/minecraft/sounds/patchern.oggPK
(Ldev/jnic/LDQFbx/C;II)V
nl.vanadium.mixin.KeyboardInputMixin
assets/minecraft/sounds/daszek.oggPK
dev/jnic/LDQFbx/n.classPK
dev/jnic/LDQFbx/F.classPK
assets/minecraft/sounds/roxmboff.oggPK
handler$zbb000$dqrkis$onRenderHotbarEnd
(Ldev/jnic/LDQFbx/C;B)V
textures/particle/snowflake1.png
/assets/minecraft/shaders/core/blur.vsh
FireworkRocketEntityMixin.java
handler$zzk000$dqrkis$onSendPacket
nerith-client-refmap.jsonPK
(Ldev/jnic/LDQFbx/C;)V
(Ldev/jnic/LDQFbx/B;B)V
nerith:textures/jumpcircle/circle3.png
nerith:textures/jumpcircle/circle2.png
(Ldev/jnic/LDQFbx/B;)V
assets/nerith/textures/arrows/ar1.pngPK
nl.vanadium.mixin.CobwebBlockMixin
client-nerith-client-refmap.jsonPK
nerith:textures/jumpcircle/circle6.png
/ModuleList.classhri<TE
kausel/technologies/obfuscation/PK
nerith:textures/targetesp/glow.png
handler$znm000$nerith-client$onKey
assets/minecraft/sounds.jsonPK
/client-nerith-client-refmap.json
assets/minecraft/shaders/program/PK
/assets/minecraft/sounds/patchern.ogg
/assets/minecraft/sounds/roxmboff.ogg
assets/nerith/textures/jumpcircle/PK
/nerith-client-refmap.json
/assets/minecraft/sounds/roxmbon.ogg
/assets/minecraft/sounds/daszek.ogg
InGameOverlayRendererMixin.java
assets/minecraft/shaders/core/arc.vshPK
nl.vanadium.mixin.ChatScreenMixin
/assets/minecraft/sounds/baka.ogg
handler$zbb001$dqrkis$onRender
nerith:textures/particle/heart1.png
nerith:textures/jumpcircle/circle.png
assets/nerith/textures/christmas.pngPK
handler$znl000$nerith-client$onRemoved
/assets/minecraft/shaders/core/blur.fsh
CobwebBlockMixin.java
textures/particle/heart1.png
assets/minecraft/blockstates/PK
LEType.javas/Pan4ur/T
hpack/Decoder#7/HeaderTable
assets/minecraft/shaders/include/PK
nerith-client.client.mixins.jsonPK
/assets/nerith/textures/arrows/ar1.png
textures/jumpcircle/circle2.png
nl.vanadium.mixin.EntityRendererMixin
nl.vanadium.mixin.HeldItemRendererMixin
nerith-client.mixins.jsonPK
assets/minecraft/shaders/core/arc.fshPK
nl.vanadium.mixin.KeyboardMixin
nl.vanadium.mixin.MinecraftClientMixin
assets/nerith/textures/killeffect/PK
textures/jumpcircle/circle4.png
/assets/minecraft/shaders/core/arc.json
handler$zoa000$nerith-client$hurt
/assets/minecraft/sounds.json
nl.vanadium.mixin.ClientConnectionMixin
/assets/minecraft/shaders/program
/assets/minecraft/shaders/core/arc.vsh
InGameOverlayRendererMixin
kausel/technologies/PK
/assets/nerith/textures/christmas.png
nl.vanadium.mixin.LivingEntityMixin
textures/particle/star1.png
assets/minecraft/models/item/PK
/assets/minecraft/shaders/program/core
textures/jumpcircle/circle.png
assets/nerith/textures/particle/PK
nl/ExampleMixin.classPK
handler$znl000$nerith-client$onRender
assets/minecraft/shaders/core/PK
handler$zni000$nerith-client$onRender
/assets/nerith/textures/jumpcircle
assets/minecraft/sounds/PK
[Ldev/jnic/LDQFbx/c;
assets/nerith/textures/hat.pngPK
[Ldev/jnic/LDQFbx/F;
/nerith-client.client.mixins.json
/nerith-client.mixins.json
handler$znk001$nerith-client$tick
com.slither.velaris.mixin
assets/minecraft/shaders/PK
assets/nerith/textures/targetesp/PK
assets/minecraft/textures/item/PK
textures/targetesp/glow.png
/assets/minecraft/shaders/core/arc.fsh
FireworkRocketEntityMixin
textures/targetesp/quadstapple.png
handler$znh000$nerith-client$tick
nl.vanadium.mixin.GameRendererMixin
assets/nerith/textures/arrows/PK
/assets/nerith/textures/killeffect
nl.vanadium.mixin.InGameHudMixin
textures/targetesp/trianglestapple.png
/nl/ExampleMixin.class
assets/minecraft/fonts/PK
/assets/nerith/textures/hat.png
/kausel/technologies
/kausel.accesswidener
nl.vanadium.mixin.EntityMixin
nl.vanadium.mixin.ItemMixin
nl.vanadium.mixin.MouseMixin
item/christmas/christmas_hat_layer
assets/minecraft/items/PK
/assets/nerith/textures/targetesp
/assets/nerith/textures/arrows
assets/nerith/textures/PK
/assets/minecraft/fonts
assets/minecraft/fonts/
item/christmas/christmas_hat
/assets/nerith/textures
mM8M18cZMm5u0smh4DugzeApIC3XA/dKQ2TC+XTLxz7N8AqXojoVl2+nRfPXoOTH
LaO+Br9c0iXnVaYePuT/BgD+TySyn6Hqm6735UuFNPwFeRrfLxSiQnt7OX/d4nZ6
AQAYX/vvh6zS4CmtIzQpGK8EX1QF4SSrKBIn3D4YLscevJ+HJWM1qHIHvNnuIUo4
WIoK3/OWATHJED1WdOr2U8CP07O9OnRQPwPfzzNHbYG3Wg0DI/Yj1t58KTlQPGfs
@:QPONMLKJIHGFEDCBA@?>=<;:98765/.-,(&%$#"
AoIBAQCwuKqr9ohNhVqDFOgzV8wI94cemJL4BI9+yvNNrCX7hbvF+Bed/IsFYc7n
//W1H3JcN+VvbP2Puq0Glrsl+2VTAgMBAAGjMjAwMA8GA1UdEQQIMAaHBJI7fuAw
OgXdn2XTnJqlJxsadPswuF7EkOnPu4YjaiPucJmdX4uZ5Km+LWLWs/8Pr9sqX+OH
>HEXJHMJ8=<E,NCO="V"C21=970+1)<!<68857546<*9IA/E30
/org/freedesktop/dbus/exceptions/InvalidBusNameException.class
dev/jnic/lib/ad56f049-35f9-4bfd-a7a4-b0489ecd3a4e.datPK
handler$zoc000$nerith-client$injectAfterMatrixPushHandPosition
handler$zoc000$nerith-client$injectBeforeRenderCrossBowItem
handler$zni000$nerith-client$onRenderStatusEffectOverlay
assets/minecraft/shaders/program/core/blur.jsonPK
assets/nerith/textures/jumpcircle/vajfon.pngPK
assets/nerith/textures/particle/snowflake1.pngPK
handler$zbb000$dqrkis$onSetOverlayMessage
handler$znh000$nerith-client$onPushOutOfBlocksHook
handler$zoe000$nerith-client$vnd_fakeHackerSmooth
handler$zog000$nerith-client$renderLabelIfPresent
handler$znj000$nerith-client$renderFireOverlayHook
handler$zoa000$nerith-client$hookShowFloatingItem
nl.vanadium.mixin.FireworkRocketEntityMixin
kausel/technologies/obfuscation/Exclude.classPK
assets/minecraft/models/block/christmas_hat.jsonPK
kausel/technologies/obfuscation/Include.classPK
assets/nerith/textures/jumpcircle/circle2.pngPK
assets/nerith/textures/particle/dollar1.pngPK
/assets/nerith/textures/particle/snowflake1.png
assets/nerith/textures/killeffect/sigma.pngPK
assets/nerith/textures/jumpcircle/circle3.pngPK
assets/minecraft/shaders/core/blur.jsonPK
assets/nerith/textures/killeffect/akise2.pngPK
handler$zoc000$nerith-client$injectBeforeRenderItem
handler$zoi000$nerith-client$onEntityCollisionHook
assets/minecraft/blockstates/christmas_hat.jsonPK
assets/minecraft/shaders/core/blur.vshPK
/assets/nerith/textures/jumpcircle/vajfon.png
assets/nerith/textures/jumpcircle/sva.pngPK
handler$zoj000$nerith-client$attackEntityPost
nl.vanadium.mixin.ClientPlayerInteractionManagerMixin
)Lkausel/technologies/obfuscation/Include;
assets/nerith/textures/jumpcircle/circle4.pngPK
assets/nerith/textures/jumpcircle/circle6.pngPK
assets/nerith/textures/jumpcircle/circle5.pngPK
assets/minecraft/shaders/program/core/round.jsonPK
/kausel/technologies/obfuscation/Exclude.class
assets/minecraft/models/item/christmas_hat.jsonPK
assets/minecraft/textures/item/christmas/testhead.pngPK
handler$zoj000$nerith-client$attackEntityPre
assets/minecraft/shaders/include/common.glslPK
assets/nerith/textures/particle/bubble1.pngPK
assets/nerith/textures/particle/leaves1.pngPK
assets/nerith/textures/jumpcircle/circle.pngPK
handler$znl000$nerith-client$onMouseClicked
assets/nerith/textures/killeffect/frag.pngPK
assets/minecraft/shaders/core/blur.fshPK
/assets/minecraft/models/block/christmas_hat.json
/kausel/technologies/obfuscation/Include.class
handler$zno000$nerith-client$onReceivePacket
/assets/nerith/textures/particle/dollar1.png
assets/nerith/textures/targetesp/glow.pngPK
/assets/nerith/textures/killeffect/akise2.png
/assets/nerith/textures/jumpcircle/circle3.png
assets/nerith/textures/particle/heart1.pngPK
/assets/nerith/textures/jumpcircle/circle2.png
assets/nerith/textures/particle/star1.pngPK
assets/nerith/textures/targetesp/quadstapple.pngPK
handler$zoh000$nerith-client$onGetTargetingMargin
nl.vanadium.mixin.LivingEntityRendererMixin
assets/minecraft/shaders/core/round.jsonPK
handler$znn000$nerith-client$onMouseButton
/assets/nerith/textures/jumpcircle/circle5.png
/assets/nerith/textures/jumpcircle/circle6.png
handler$zoh000$nerith-client$getBoundingBox
/assets/nerith/textures/killeffect/sigma.png
/assets/nerith/textures/jumpcircle/sva.png
/assets/minecraft/shaders/program/core/round.json
assets/minecraft/shaders/core/round.vshPK
/assets/nerith/textures/jumpcircle/circle4.png
assets/nerith/textures/targetesp/idk.pngPK
handler$zno000$nerith-client$onSendPacket
assets/minecraft/shaders/core/arc.jsonPK
/assets/nerith/textures/killeffect/frag.png
assets/minecraft/shaders/core/round.fshPK
nl.vanadium.mixin.ClientPlayerEntityMixin
/assets/minecraft/shaders/include/common.glsl
handler$zni000$nerith-client$onRenderHotbar
handler$zoa000$nerith-client$hookWorldRender
assets/minecraft/shaders/core/comets.vshPK
assets/minecraft/items/christmas_hat.jsonPK
/assets/nerith/textures/particle/leaves1.png
/assets/nerith/textures/particle/bubble1.png
assets/minecraft/shaders/core/comets.jsonPK
nl.vanadium.mixin.InGameOverlayRendererMixin
assets/minecraft/shaders/program/core/PK
/assets/nerith/textures/jumpcircle/circle.png
/assets/anamvmnt/textures/capes/custom/azure.png
/assets/nerith/textures/targetesp/glow.png
nl/f.class
nl/g.class
nl/h.class
Char2ObjectArrayMap.java
ChatScreenMixin
ChatScreenMixin.java
class_9974.java
ClientPlayerEntityMixin
KeyboardInputMixin
KeyboardInputMixin.java
LivingEntityAccessor.java
'@

$__pn = 0
foreach ($__line in ($POSZLAKI -split "`n")) {
    $__p = $__line -replace "`r$", ''
    if ($__p.Length -eq 0) { continue }
    if (-not $__seen.Add($__p)) { continue }
    $__pn++
    [void]$__all.Add(@{
        Cat     = 'POSZLAKI'
        Name    = ('Poszlaka #{0}' -f $__pn)
        Level   = 'L'
        Pattern = $__p
        Bulk    = $true
    })
}

$SIGNATURES = $__all.ToArray()

# =============================================================================
#  Silnik skanowania (Win32 API - wylacznie odczyt pamieci).
#  Jedno przejscie po pamieci szuka WSZYSTKICH sygnatur naraz, w dwoch
#  kodowaniach: ASCII i UTF-16 (tak Java trzyma teksty w pamieci).
#  Zapamietuje tez adres i kodowanie pierwszego trafienia - to trafia do
#  sekcji DOWODY w wyniku.
#  Nazwa klasy K9ADBE3DD8413 jest losowana przez serwer przy kazdym pobraniu.
# =============================================================================
$CS = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class K9ADBE3DD8413
{
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("kernel32.dll")]
    static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
    [DllImport("kernel32.dll")]
    static extern int VirtualQueryEx(IntPtr h, IntPtr addr, out MI mi, uint len);
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr h);

    [StructLayout(LayoutKind.Sequential)]
    public struct MI
    {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public uint   AllocationProtect;
        public IntPtr RegionSize;
        public uint   State;
        public uint   Protect;
        public uint   Type;
    }

    // Minimalne mozliwe uprawnienia - tylko odczyt.
    const int PROCESS_QUERY_INFORMATION = 0x0400;
    const int PROCESS_VM_READ           = 0x0010;
    const int MEM_COMMIT                = 0x1000;
    const int CHUNK                     = 4 * 1024 * 1024;

    IntPtr   h;
    byte[][] pats;
    int[]    owner;
    int[]    encOf;     // 0 = ASCII, 1 = UTF-16
    int[][]  byPair;    // kubelki po DWOCH pierwszych bajtach
    byte[]   buf;
    int      maxLen;
    long     curBase;

    public bool[] Found;
    public long[] Addr;      // adres pierwszego trafienia
    public int[]  Enc;       // kodowanie trafienia
    public long   BytesRead;

    public static K9ADBE3DD8413 Open(int pid, string[] targets)
    {
        IntPtr h = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, pid);
        if (h == IntPtr.Zero) return null;
        K9ADBE3DD8413 s = new K9ADBE3DD8413();
        s.h = h;
        s.Build(targets);
        return s;
    }

    void Build(string[] targets)
    {
        Found = new bool[targets.Length];
        Addr  = new long[targets.Length];
        Enc   = new int[targets.Length];

        List<byte[]> pl = new List<byte[]>();
        List<int>    ol = new List<int>();
        List<int>    el = new List<int>();
        for (int i = 0; i < targets.Length; i++)
        {
            pl.Add(Encoding.ASCII.GetBytes(targets[i]));   ol.Add(i); el.Add(0);
            pl.Add(Encoding.Unicode.GetBytes(targets[i])); ol.Add(i); el.Add(1);
        }
        pats  = pl.ToArray();
        owner = ol.ToArray();
        encOf = el.ToArray();

        // Kubelkowanie po DWOCH pierwszych bajtach zamiast jednego: przy kilkuset
        // sygnaturach pojedynczy bajt dawal dziesiatki kandydatow na kazda pozycje
        // w pamieci i skan trwal ponad dwa razy dluzej.
        List<int>[] buckets = new List<int>[65536];
        maxLen = 2;
        for (int i = 0; i < pats.Length; i++)
        {
            if (pats[i].Length < 2) continue;
            int key = (pats[i][0] << 8) | pats[i][1];
            if (buckets[key] == null) buckets[key] = new List<int>();
            buckets[key].Add(i);
            if (pats[i].Length > maxLen) maxLen = pats[i].Length;
        }
        byPair = new int[65536][];
        for (int i = 0; i < 65536; i++)
            byPair[i] = (buckets[i] == null) ? null : buckets[i].ToArray();

        buf = new byte[CHUNK];
    }

    public long[][] Regions()
    {
        List<long[]> list = new List<long[]>();
        long addr  = 0;
        // Na 32-bitowym PowerShellu new IntPtr(addr) rzucilby OverflowException.
        long limit = (IntPtr.Size == 4) ? 0x7FFF0000L : 0x7FFFFFFF0000L;
        uint sz    = (uint)Marshal.SizeOf(typeof(MI));
        MI   mi;
        while (addr < limit)
        {
            if (VirtualQueryEx(h, new IntPtr(addr), out mi, sz) == 0) break;
            long rs  = mi.RegionSize.ToInt64();
            long bas = mi.BaseAddress.ToInt64();
            if (rs <= 0) break;

            uint p = mi.Protect;
            bool readable = (p == 0x02 || p == 0x04 || p == 0x08 ||
                             p == 0x20 || p == 0x40 || p == 0x80);
            if (mi.State == MEM_COMMIT && readable)
                list.Add(new long[] { bas, rs });

            long next = bas + rs;
            if (next <= addr) break;
            addr = next;
        }
        return list.ToArray();
    }

    public void Scan(long baseAddr, long size)
    {
        long off = 0;
        while (off < size)
        {
            int want = (int)Math.Min((long)CHUNK, size - off);
            IntPtr read;
            if (!ReadProcessMemory(h, new IntPtr(baseAddr + off), buf, (IntPtr)want, out read))
            {
                off += want;
                continue;
            }
            int n = (int)read.ToInt64();
            if (n <= 0) { off += want; continue; }

            curBase = baseAddr + off;
            Search(n);
            BytesRead += n;

            int step = n - (maxLen - 1);
            if (step <= 0) step = n;
            off += step;
        }
    }

    void Search(int n)
    {
        byte[] b = buf;
        for (int i = 0; i + 1 < n; i++)
        {
            int[] cand = byPair[(b[i] << 8) | b[i + 1]];
            if (cand == null) continue;
            for (int k = 0; k < cand.Length; k++)
            {
                int pi = cand[k];
                int o  = owner[pi];
                if (Found[o]) continue;
                byte[] p = pats[pi];
                if (i + p.Length > n) continue;
                int j = 2;   // dwa pierwsze bajty zgodne z kubelka
                while (j < p.Length && b[i + j] == p[j]) j++;
                if (j == p.Length)
                {
                    Found[o] = true;
                    Addr[o]  = curBase + i;
                    Enc[o]   = encOf[pi];
                }
            }
        }
    }

    public void Close()
    {
        if (h != IntPtr.Zero) { CloseHandle(h); h = IntPtr.Zero; }
    }
}
'@

# =============================================================================
#  START
# =============================================================================
try { Clear-Host } catch { }
Write-Banner

Write-Host ''
Write-Host ($PAD + '  Ten skrypt tylko ODCZYTUJE pamiec procesu gry i wypisuje wynik.') -ForegroundColor Gray
Write-Host ($PAD + '  Nie laczy sie z internetem, nie czyta hasel ani plikow z kontami,') -ForegroundColor Gray
Write-Host ($PAD + '  nic nie pobiera i nic nie zapisuje. Cale zrodlo przeczytasz tu:') -ForegroundColor Gray
Write-Host ($PAD + '  ' + $SCRIPT_SOURCE) -ForegroundColor Cyan
Write-Host ''

$sessionId = ([guid]::NewGuid().ToString('N').Substring(0, 8)).ToUpper()
$startedAt = Get-Date

Box-Top 'SESJA' 'DarkGray'
Box-Field 'Kod sesji'  $sessionId 'Yellow'
Box-Field 'Data i czas' $startedAt.ToString('yyyy-MM-dd HH:mm:ss')
Box-Field 'Komputer'   ("{0} \ {1}" -f $env:COMPUTERNAME, $env:USERNAME)
Box-Field 'PowerShell' ("{0}   ({1}-bit)" -f $PSVersionTable.PSVersion, $(if ([Environment]::Is64BitProcess) { 64 } else { 32 }))
Box-Bottom

# --- Wynik kontroli uczciwosci sesji -----------------------------------------
if ($__integrity.Count -gt 0) {
    Write-Host ''
    Box-Top 'KONTROLA SESJI' 'Red'
    foreach ($m in $__integrity) {
        Box-Row @(@{ T = ('  ' + [string]$G.BAD + ' '); C = 'Red' }, @{ T = (Fit $m ($IN - 5)); C = 'Red' }) 'Red'
    }
    Box-Bottom 'Red'
    Write-Verdict 'SESJA POWERSHELL ZOSTALA ZMANIPULOWANA' 'wynik niewiarygodny - sprawdzenie przerwane' 'DarkRed' 'White'
    Write-Host ($PAD + '  Zamknij WSZYSTKIE okna PowerShell, otworz nowe i uruchom ponownie.') -ForegroundColor Yellow
    Write-Host ''
    Write-Footer $sessionId $startedAt
    return
}

$warnings = @()
$histCount = 0
try { $histCount = @(Microsoft.PowerShell.Core\Get-History).Count } catch { }
if ($histCount -gt 0) {
    $warnings += "To okno PowerShell bylo juz uzywane ($histCount komend) - uzyj swiezego okna."
}
if (-not [Environment]::Is64BitProcess) {
    $warnings += 'To 32-bitowy PowerShell - nie odczyta calej pamieci gry.'
}
if ($warnings.Count -gt 0) {
    Write-Host ''
    Box-Top 'OSTRZEZENIA' 'DarkYellow'
    foreach ($m in $warnings) {
        Box-Row @(@{ T = ('  ' + [string]$G.WARN + ' '); C = 'Yellow' }, @{ T = (Fit $m ($IN - 5)); C = 'Yellow' }) 'DarkYellow'
    }
    Box-Bottom 'DarkYellow'
}

# --- Kompilacja silnika -------------------------------------------------------
try {
    Add-Type -TypeDefinition $CS
} catch {
    Write-Verdict 'NIE UDALO SIE PRZYGOTOWAC SKANERA' $_.Exception.Message 'DarkRed' 'White'
    Write-Footer $sessionId $startedAt
    return
}

# --- Procesy gry --------------------------------------------------------------
$procs = @(Get-Process -Name 'javaw', 'java' -ErrorAction SilentlyContinue |
           Sort-Object -Property WorkingSet64 -Descending)

Write-Host ''
Box-Top 'PROCESY GRY' 'DarkGray'
if ($procs.Count -eq 0) {
    Box-Row @(@{ T = '  Nie znaleziono procesu javaw.exe / java.exe.'; C = 'Yellow' })
    Box-Row @(@{ T = '  Wlacz Minecrafta i uruchom sprawdzanie ponownie.'; C = 'Yellow' })
    Box-Bottom
    Write-Verdict 'BRAK URUCHOMIONEJ GRY' 'sprawdzenie niewykonane' 'DarkYellow' 'Black'
    Write-Footer $sessionId $startedAt
    return
}
Box-Row @(
    @{ T = ('  ' + (Fit 'PROCES' 14)); C = 'DarkGray' },
    @{ T = (Fit 'PID' 10);             C = 'DarkGray' },
    @{ T = (Fit 'PAMIEC' 12);          C = 'DarkGray' },
    @{ T = 'START';                    C = 'DarkGray' }
)
foreach ($p in $procs) {
    # Uwaga: PowerShell 5.1 nie pozwala przypisac wyniku try/catch do zmiennej.
    $started = '?'
    try { $started = $p.StartTime.ToString('HH:mm:ss') } catch { }
    Box-Row @(
        @{ T = ('  ' + (Fit ($p.ProcessName + '.exe') 14)); C = 'White' },
        @{ T = (Fit ([string]$p.Id) 10);                    C = 'Gray' },
        @{ T = (Fit ("{0} MB" -f [int]($p.WorkingSet64 / 1MB)) 12); C = 'Gray' },
        @{ T = $started;                                    C = 'Gray' }
    )
}
Box-Bottom

# --- Skanowanie ---------------------------------------------------------------
$patterns = @($SIGNATURES | ForEach-Object { $_.Pattern })
$n        = $SIGNATURES.Count
$hits     = New-Object 'bool[]' $n
$hitAddr  = New-Object 'long[]' $n
$hitEnc   = New-Object 'int[]'  $n
$hitPid   = New-Object 'int[]'  $n
$hitProc  = New-Object 'string[]' $n
$scanned  = 0L
$opened   = 0

Write-Host ''
Write-Host ($PAD + ' SKANOWANIE PAMIECI') -ForegroundColor White
Write-Host ($PAD + ' ' + ([string]$G.H * ($W - 2))) -ForegroundColor DarkGray

foreach ($p in $procs) {
    $scanner = [K9ADBE3DD8413]::Open($p.Id, $patterns)
    if ($null -eq $scanner) {
        Write-Host ($PAD + " $($G.WARN) Brak dostepu do PID $($p.Id) - uruchom PowerShell jako administrator.") -ForegroundColor Yellow
        continue
    }
    $opened++
    try {
        $regions = $scanner.Regions()
        $total = 0L
        foreach ($r in $regions) { $total += $r[1] }
        if ($total -le 0) { $total = 1 }

        $label   = "{0} (PID {1})" -f $p.ProcessName, $p.Id
        $t0      = Get-Date
        $done    = 0L
        $lastPct = -1
        foreach ($r in $regions) {
            $scanner.Scan($r[0], $r[1])
            $done += $r[1]
            $pct = [int](100 * $done / $total)
            if ($pct -ne $lastPct) {
                Show-Progress $pct $label ([int]($scanner.BytesRead / 1MB)) ((Get-Date) - $t0).TotalSeconds
                $lastPct = $pct
            }
        }
        Show-Progress 100 $label ([int]($scanner.BytesRead / 1MB)) ((Get-Date) - $t0).TotalSeconds
        Write-Host ''

        $found = $scanner.Found
        for ($i = 0; $i -lt $n; $i++) {
            if ($found[$i] -and -not $hits[$i]) {
                $hits[$i]    = $true
                $hitAddr[$i] = $scanner.Addr[$i]
                $hitEnc[$i]  = $scanner.Enc[$i]
                $hitPid[$i]  = $p.Id
                $hitProc[$i] = $p.ProcessName
            }
        }
        $scanned += $scanner.BytesRead
    } finally {
        $scanner.Close()
    }
}

if ($opened -eq 0) {
    Write-Verdict 'BRAK DOSTEPU DO PAMIECI GRY' 'uruchom PowerShell jako administrator' 'DarkYellow' 'Black'
    Write-Footer $sessionId $startedAt
    return
}

# --- Wyniki -------------------------------------------------------------------
$OK_TXT  = '[ CZYSTO     ]'
$BAD_TXT = '[ WYKRYTO    ]'
$SUS_TXT = '[ PODEJRZANE ]'

Write-Host ''
Box-Top 'WYNIKI' 'DarkGray'
Box-Row @(
    @{ T = ('  ' + (Fit 'SYGNATURA' 22)); C = 'DarkGray' },
    @{ T = (Fit 'SZUKANY KOD' 34);        C = 'DarkGray' },
    @{ T = '  STATUS';                    C = 'DarkGray' }
)

function Write-SigRow([hashtable]$Sig, [bool]$Hit) {
    if ($Hit) {
        if ($Sig.Level -eq 'H') { $status = $BAD_TXT; $sc = 'Red'; $mark = $G.BAD; $mc = 'Red' }
        else                    { $status = $SUS_TXT; $sc = 'Yellow'; $mark = $G.WARN; $mc = 'Yellow' }
        $nameColor = 'White'
    } else {
        $status = $OK_TXT; $sc = 'Green'; $mark = $G.OK; $mc = 'DarkGreen'; $nameColor = 'Gray'
    }
    Box-Row @(
        @{ T = ('  ' + [string]$mark + ' '); C = $mc },
        # 19 + wymuszona spacja: przy nazwie dokladnie 20-znakowej kolumny
        # zlewalyby sie ze soba bez odstepu.
        @{ T = ((Fit $Sig.Name 19) + ' ');   C = $nameColor },
        @{ T = (Fit $Sig.Pattern 34);        C = 'DarkGray' },
        @{ T = ('  ' + $status);             C = $sc }
    )
}

$hi = 0; $lo = 0
$i = 0
while ($i -lt $n) {
    $cat = $SIGNATURES[$i].Cat
    Box-Sep
    Box-Row @(@{ T = ('  ' + $cat); C = 'Cyan' })

    if ($SIGNATURES[$i].Bulk) {
        # Kategoria zbiorcza: pokazujemy tylko trafienia + podsumowanie reszty.
        $catStart = $i
        $catHits  = @()
        while ($i -lt $n -and $SIGNATURES[$i].Cat -eq $cat) {
            if ($hits[$i]) { $catHits += $i }
            $i++
        }
        $catTotal = $i - $catStart
        foreach ($hidx in $catHits) {
            if ($SIGNATURES[$hidx].Level -eq 'H') { $hi++ } else { $lo++ }
            Write-SigRow $SIGNATURES[$hidx] $true
        }
        $clean = $catTotal - $catHits.Count
        if ($catHits.Count -eq 0) {
            Box-Row @(
                @{ T = ('  ' + [string]$G.OK + ' '); C = 'DarkGreen' },
                @{ T = ("wszystkie {0} sygnatur czyste" -f $catTotal); C = 'Green' }
            )
        } else {
            Box-Row @(
                @{ T = ('  ' + [string]$G.OK + ' '); C = 'DarkGreen' },
                @{ T = ("pozostale {0} z {1} sygnatur czyste" -f $clean, $catTotal); C = 'Gray' }
            )
        }
    } else {
        while ($i -lt $n -and $SIGNATURES[$i].Cat -eq $cat) {
            Write-SigRow $SIGNATURES[$i] $hits[$i]
            if ($hits[$i]) {
                if ($SIGNATURES[$i].Level -eq 'H') { $hi++ } else { $lo++ }
            }
            $i++
        }
    }
}
Box-Sep
$elapsed = (Get-Date) - $startedAt
Box-Row @(
    @{ T = '  Przeskanowano '; C = 'DarkGray' }, @{ T = ("{0} MB" -f [int]($scanned / 1MB)); C = 'White' },
    @{ T = '  w '; C = 'DarkGray' },             @{ T = ("{0:N1} s" -f $elapsed.TotalSeconds); C = 'White' },
    @{ T = '   sygnatur: '; C = 'DarkGray' },    @{ T = [string]$n; C = 'White' },
    @{ T = '   trafien: '; C = 'DarkGray' },     @{ T = [string]($hi + $lo); C = $(if ($hi + $lo -gt 0) { 'Red' } else { 'Green' }) }
)
Box-Bottom

# --- Dowody -------------------------------------------------------------------
if ($hi + $lo -gt 0) {
    Write-Host ''
    Box-Top 'DOWODY' 'Red'
    $k = 0
    for ($i = 0; $i -lt $n; $i++) {
        if (-not $hits[$i]) { continue }
        $k++
        $sig = $SIGNATURES[$i]
        $col = $(if ($sig.Level -eq 'H') { 'Red' } else { 'Yellow' })
        if ($k -gt 1) { Box-Sep 'Red' }
        Box-Row @(
            @{ T = ("  {0}. " -f $k); C = 'DarkGray' },
            @{ T = (Fit $sig.Name 24); C = $col },
            @{ T = $(if ($sig.Level -eq 'H') { 'pewne wykrycie' } else { 'poszlaka - do weryfikacji recznej' }); C = 'DarkGray' }
        ) 'Red'
        Box-Row @(
            @{ T = '     proces    '; C = 'DarkGray' },
            @{ T = ("{0}.exe (PID {1})" -f $hitProc[$i], $hitPid[$i]); C = 'White' }
        ) 'Red'
        Box-Row @(
            @{ T = '     adres     '; C = 'DarkGray' },
            @{ T = ("0x{0:X16}" -f $hitAddr[$i]); C = 'White' },
            @{ T = ('   kodowanie: ' + $(if ($hitEnc[$i] -eq 1) { 'UTF-16' } else { 'ASCII' })); C = 'DarkGray' }
        ) 'Red'
        Box-Row @(
            @{ T = '     kod       '; C = 'DarkGray' },
            @{ T = (Fit $sig.Pattern ($IN - 15)); C = 'Gray' }
        ) 'Red'
    }
    Box-Bottom 'Red'
}

# --- Werdykt ------------------------------------------------------------------
if ($hi -gt 0) {
    Write-Verdict ("WYKRYTO CHEATY ({0})" -f $hi) 'szczegoly znajdziesz w sekcji DOWODY' 'DarkRed' 'White'
} elseif ($lo -gt 0) {
    Write-Verdict ("PODEJRZANE ({0})" -f $lo) 'krotkie sygnatury - wymagaja recznej weryfikacji' 'DarkYellow' 'Black'
} else {
    Write-Verdict 'CZYSTO' ("nie znaleziono zadnej z {0} sygnatur" -f $n) 'DarkGreen' 'White'
}

Write-Footer $sessionId $startedAt
