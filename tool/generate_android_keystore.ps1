param(
  [string]$OutFile = 'keystore.jks',
  [string]$Alias = 'fclash'
)

$ErrorActionPreference = 'Stop'

if (Test-Path $OutFile) {
  throw "Refusing to overwrite existing keystore: $OutFile"
}

$securePass = Read-Host -AsSecureString 'Enter keystore password (min 6 chars)'
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass)
try {
  $pass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
} finally {
  [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

if ($pass.Length -lt 6) {
  throw 'Password must be at least 6 characters.'
}

keytool -genkeypair -v `
  -keystore $OutFile `
  -storetype PKCS12 `
  -alias $Alias `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -storepass $pass `
  -keypass $pass `
  -dname 'CN=FClash, O=nicelic, C=US'

$encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $OutFile)))
Write-Host ''
Write-Host 'Configure these 4 GitHub repository Secrets (Settings -> Secrets and variables -> Actions):'
Write-Host "  KEY_ALIAS=$Alias"
Write-Host "  STORE_PASSWORD=$pass"
Write-Host "  KEY_PASSWORD=$pass"
Write-Host "  KEYSTORE=$encoded"
