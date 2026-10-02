<#
  Punch Clock - one-script setup
  ------------------------------
  Put this file in the same folder as index.html, admin.html, etc.
  Easiest: double-click setup.bat
  Or run:  powershell -ExecutionPolicy Bypass -File .\setup.ps1

  What it does:
    1. Installs Node.js, Git, GitHub CLI, Firebase CLI (if missing)
    2. Logs you in to Firebase and GitHub (browser opens)
    3. Creates the Firebase project, web app and database
    4. Writes firebase-config.js and firestore.rules with your admin email
    5. Uploads the security rules
    6. Creates your admin account
    7. Creates the GitHub repo, uploads the files, turns on GitHub Pages
  Safe to run again if something fails halfway.
#>

$ErrorActionPreference = 'Continue'
Set-Location -Path $PSScriptRoot

# ---------------- helpers ----------------
function Step($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "  OK  $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  !!  $t" -ForegroundColor Yellow }
function Fail($t) { Write-Host "`n  XX  $t" -ForegroundColor Red; Read-Host "`nPress Enter to close"; exit 1 }
function Has($c)  { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + "$env:APPDATA\npm"
}
function Get-Json($text) {
  if (-not $text) { return $null }
  $s = $text.IndexOf('{'); $e = $text.LastIndexOf('}')
  if ($s -lt 0 -or $e -lt $s) { return $null }
  try { return $text.Substring($s, $e - $s + 1) | ConvertFrom-Json } catch { return $null }
}
function Write-File($path, $text) {
  [IO.File]::WriteAllText((Join-Path $PSScriptRoot $path), $text, (New-Object Text.UTF8Encoding $false))
}
function Pause-For($msg) { Read-Host "`n  >> $msg, then press Enter" | Out-Null }

Write-Host "`nPunch Clock setup" -ForegroundColor White
Write-Host "This takes about 5-10 minutes. Keep this window open.`n"

foreach ($f in 'index.html', 'admin.html', 'style.css', 'firestore.rules', 'manifest.json', 'sw.js') {
  if (-not (Test-Path $f)) { Fail "Can't find $f. Put setup.ps1 inside the app folder (next to index.html) and run it again." }
}

# ---------------- 1. tools ----------------
Step "1/8  Checking tools"
$tools = @(
  @{ cmd = 'node'; id = 'OpenJS.NodeJS.LTS'; name = 'Node.js' },
  @{ cmd = 'git';  id = 'Git.Git';           name = 'Git' },
  @{ cmd = 'gh';   id = 'GitHub.cli';        name = 'GitHub CLI' }
)
foreach ($t in $tools) {
  if (Has $t.cmd) { Ok "$($t.name) found"; continue }
  if (-not (Has 'winget')) { Fail "$($t.name) is missing and winget isn't available. Install $($t.name) manually, then run setup again." }
  Write-Host "  Installing $($t.name)..."
  winget install --id $t.id -e --silent --accept-package-agreements --accept-source-agreements | Out-Host
  Refresh-Path
  if (-not (Has $t.cmd)) { Fail "$($t.name) was installed but Windows hasn't picked it up yet. Close this window and run setup again." }
  Ok "$($t.name) installed"
}

$npmRoot = (npm.cmd root -g | Out-String).Trim()
$FbJs = Join-Path $npmRoot 'firebase-tools\lib\bin\firebase.js'
if (-not (Test-Path $FbJs)) {
  Write-Host "  Installing Firebase CLI (1-2 minutes)..."
  npm.cmd install -g firebase-tools | Out-Host
  $npmRoot = (npm.cmd root -g | Out-String).Trim()
  $FbJs = Join-Path $npmRoot 'firebase-tools\lib\bin\firebase.js'
  if (-not (Test-Path $FbJs)) { Fail "Firebase CLI install failed. Run 'npm install -g firebase-tools' yourself, then run setup again." }
}
Ok "Firebase CLI ready"
function fb { & node $FbJs @args }

# ---------------- 2. your details ----------------
Step "2/8  Your details"
do {
  $AdminEmail = (Read-Host "  Admin email (you'll log in to the admin page with this)").Trim().ToLower()
} until ($AdminEmail -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
do {
  $sec = Read-Host "  Admin password (min 6 characters)" -AsSecureString
  $AdminPass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  if ($AdminPass.Length -lt 6) { Warn "Password too short." }
} until ($AdminPass.Length -ge 6)
$Repo = (Read-Host "  GitHub repo name [punch-clock]").Trim()
if (-not $Repo) { $Repo = 'punch-clock' }
$ProjectId = (Read-Host "  Existing Firebase project ID (leave empty to create a new one)").Trim()

# ---------------- 3. logins ----------------
Step "3/8  Logging in (your browser will open)"
fb projects:list --json *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "  Log in to Firebase with your Google account..."
  fb login
  fb projects:list --json *> $null
  if ($LASTEXITCODE -ne 0) { Fail "Firebase login didn't complete." }
}
Ok "Firebase login"

gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "  Log in to GitHub (copy the code shown, paste it in the browser)..."
  gh auth login --hostname github.com --git-protocol https --web
  gh auth status *> $null
  if ($LASTEXITCODE -ne 0) { Fail "GitHub login didn't complete." }
}
gh auth setup-git *> $null
$Owner = (gh api user --jq .login | Out-String).Trim()
if (-not $Owner) { Fail "Couldn't read your GitHub username." }
$Domain = "$($Owner.ToLower()).github.io"
$SiteUrl = "https://$Domain/$Repo/"
Ok "GitHub login ($Owner)"

# ---------------- 4. firebase project + web app ----------------
Step "4/8  Firebase project"
if (-not $ProjectId) {
  $suffix = -join ((97..122) + (48..57) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
  $ProjectId = "punch-clock-$suffix"
  Write-Host "  Creating project $ProjectId (about 1 minute)..."
  fb projects:create $ProjectId --display-name "Punch Clock" | Out-Host
  if ($LASTEXITCODE -ne 0) {
    Fail ("Couldn't create the Firebase project.`n" +
          "       If you've never used Firebase: open https://console.firebase.google.com once, accept the terms, then run setup again.`n" +
          "       Free accounts also have a project limit; you can create one in the console and enter its ID when asked.")
  }
}
Ok "Project: $ProjectId"

$appId = $null
$list = Get-Json (fb apps:list WEB --project $ProjectId --json | Out-String)
if ($list -and $list.result) { $appId = @($list.result)[0].appId }
if (-not $appId) {
  $created = Get-Json (fb apps:create WEB "Punch Clock" --project $ProjectId --json | Out-String)
  if ($created) { $appId = $created.result.appId }
}
if (-not $appId) { Fail "Couldn't create the Firebase web app." }
Ok "Web app: $appId"

$sdkOut = Get-Json (fb apps:sdkconfig WEB $appId --project $ProjectId --json | Out-String)
$sdk = $null
if ($sdkOut -and $sdkOut.result.sdkConfig) { $sdk = $sdkOut.result.sdkConfig }
elseif ($sdkOut -and $sdkOut.result.fileContents) { $sdk = Get-Json $sdkOut.result.fileContents }
if (-not $sdk -or -not $sdk.apiKey) { Fail "Couldn't read the Firebase web config." }

Write-File 'firebase-config.js' @"
// Written by setup.ps1
export const firebaseConfig = {
  apiKey: "$($sdk.apiKey)",
  authDomain: "$($sdk.authDomain)",
  projectId: "$($sdk.projectId)",
  storageBucket: "$($sdk.storageBucket)",
  messagingSenderId: "$($sdk.messagingSenderId)",
  appId: "$($sdk.appId)"
};

// The only email allowed into admin.html (must match firestore.rules)
export const ADMIN_EMAIL = "$AdminEmail";

export const FB = "https://www.gstatic.com/firebasejs/10.12.2";
"@
$rules = Get-Content firestore.rules -Raw
$rules = $rules -replace 'request\.auth\.token\.email == "[^"]*"', "request.auth.token.email == `"$AdminEmail`""
Write-File 'firestore.rules' $rules
Write-File 'firebase.json' '{ "firestore": { "rules": "firestore.rules" } }'
Write-File '.firebaserc' "{ `"projects`": { `"default`": `"$ProjectId`" } }"
Write-File '.gitignore' ".firebase/`r`n*.log`r`nSETUP-RESULT.txt`r`n"
Ok "firebase-config.js and firestore.rules updated"

# ---------------- 5. database + rules ----------------
Step "5/8  Database"
$dbOut = fb firestore:databases:create "(default)" --location asia-south1 --project $ProjectId 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) { Ok "Database created (Mumbai region)" }
elseif ($dbOut -match 'already exists|ALREADY_EXISTS') { Ok "Database already exists" }
else {
  Warn "Couldn't create the database automatically."
  Start-Process "https://console.firebase.google.com/project/$ProjectId/firestore"
  Write-Host "     In the browser: Create database > Production mode > location asia-south1 (Mumbai) > Create"
  Pause-For "Create the database"
}

fb deploy --only firestore:rules --project $ProjectId --non-interactive | Out-Host
if ($LASTEXITCODE -eq 0) { Ok "Security rules uploaded" }
else {
  Warn "Couldn't upload rules. Open Firestore > Rules in the console and paste the contents of firestore.rules."
  Start-Process "https://console.firebase.google.com/project/$ProjectId/firestore/rules"
  Pause-For "Paste and publish the rules"
}

# ---------------- 6. login settings (manual, 1 minute) ----------------
Step "6/8  Turn on login (one minute in the browser)"
Start-Process "https://console.firebase.google.com/project/$ProjectId/authentication/providers"
Write-Host @"
     Firebase doesn't allow this step from a script on the free plan, so please do it in the browser:

     a) Click  Get started  (if shown)
     b) Sign-in method > Email/Password > turn on the first switch > Save
     c) Settings tab > Authorized domains > Add domain >  $Domain  > Add
"@ -ForegroundColor White
Pause-For "Finish a, b and c"

# ---------------- 7. admin account ----------------
Step "7/8  Admin account"
$body = @{ email = $AdminEmail; password = $AdminPass; returnSecureToken = $true } | ConvertTo-Json
while ($true) {
  try {
    Invoke-RestMethod -Method Post -ContentType 'application/json' -Body $body `
      -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$($sdk.apiKey)" | Out-Null
    Ok "Admin account created: $AdminEmail"; break
  } catch {
    $m = "$($_.ErrorDetails.Message) $($_.Exception.Message)"
    if ($m -match 'EMAIL_EXISTS') { Ok "Admin account already exists (use the password you set before)"; break }
    elseif ($m -match 'OPERATION_NOT_ALLOWED|CONFIGURATION_NOT_FOUND') {
      Warn "Email/Password login isn't turned on yet (step 6b)."
      Pause-For "Turn it on"
    } else {
      Warn "Couldn't create the admin account: $m"
      Write-Host "     Create it by hand: Firebase console > Authentication > Users > Add user"
      break
    }
  }
}

# ---------------- 8. GitHub repo + Pages ----------------
Step "8/8  Publishing on GitHub Pages"
if (-not (Test-Path .git)) { git init *> $null }
if (-not (git config user.email)) {
  git config user.email "$Owner@users.noreply.github.com"
  git config user.name $Owner
}
git add -A
git commit -m "Punch Clock attendance app" *> $null
git branch -M main

gh repo view "$Owner/$Repo" *> $null
if ($LASTEXITCODE -ne 0) {
  git remote remove origin *> $null
  gh repo create $Repo --public --source . --remote origin --push | Out-Host
  if ($LASTEXITCODE -ne 0) { Fail "Couldn't create the GitHub repo '$Repo'." }
} else {
  if (-not (git remote | Select-String -SimpleMatch 'origin')) { git remote add origin "https://github.com/$Owner/$Repo.git" }
  git push -u origin main | Out-Host
  if ($LASTEXITCODE -ne 0) { Fail "Couldn't upload to the existing repo '$Owner/$Repo'." }
}
Ok "Files uploaded to github.com/$Owner/$Repo"

gh api -X POST "repos/$Owner/$Repo/pages" -f "source[branch]=main" -f "source[path]=/" *> $null
gh api "repos/$Owner/$Repo/pages" *> $null
if ($LASTEXITCODE -eq 0) { Ok "GitHub Pages turned on" }
else {
  Warn "Couldn't turn on Pages automatically."
  Start-Process "https://github.com/$Owner/$Repo/settings/pages"
  Write-Host "     Branch: main, Folder: / (root) > Save"
  Pause-For "Turn on Pages"
}

# ---------------- done ----------------
$result = @"
Punch Clock is ready
--------------------
Employee app : $SiteUrl
Admin page   : ${SiteUrl}admin.html
Admin email  : $AdminEmail
Firebase     : https://console.firebase.google.com/project/$ProjectId
GitHub repo  : https://github.com/$Owner/$Repo

The site can take 1-3 minutes to go live the first time.
To update later: change files, then run  git add -A; git commit -m "update"; git push
"@
Write-File 'SETUP-RESULT.txt' $result
Write-Host "`n$result" -ForegroundColor Green
Write-Host "(Saved in SETUP-RESULT.txt)`n"
$open = Read-Host "Open the admin page now? (y/n)"
if ($open -match '^y') { Start-Process "${SiteUrl}admin.html" }
