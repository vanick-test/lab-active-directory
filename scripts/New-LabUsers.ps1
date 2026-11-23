<#
.SYNOPSIS
    Cree des utilisateurs AD en masse a partir d'un fichier CSV.

.DESCRIPTION
    Pour chaque ligne du CSV (Prenom, Nom, Departement, Titre) :
      - cree le compte prenom.nom dans OU=<Departement>,OU=Utilisateurs,OU=LAB
      - l'ajoute au groupe global GG_<Departement>
      - force le changement de mot de passe a la premiere connexion
    Les comptes existants sont ignores (le script peut etre relance sans erreur).

.EXAMPLE
    .\New-LabUsers.ps1 -CsvPath .\users.csv
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [string]$DomainDN = "DC=lab,DC=local",
    [string]$UpnSuffix = "lab.local"
)

Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path $CsvPath)) { throw "Fichier introuvable : $CsvPath" }

$initialPassword = Read-Host -AsSecureString "Mot de passe initial (respecte la politique : 12 car. min, complexe)"

function Remove-Accents([string]$text) {
    $normalized = $text.Normalize([Text.NormalizationForm]::FormD)
    -join ($normalized.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark'
    })
}

$results = foreach ($u in Import-Csv -Path $CsvPath) {
    $sam    = (Remove-Accents("$($u.Prenom).$($u.Nom)")).ToLower() -replace '[^a-z0-9.\-]', ''
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0, 20) }   # limite sAMAccountName
    $ouPath = "OU=$($u.Departement),OU=Utilisateurs,OU=LAB,$DomainDN"
    $group  = "GG_$($u.Departement)"

    try {
        if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
            [pscustomobject]@{ Compte = $sam; Statut = "Deja existant" }
            continue
        }

        if ($PSCmdlet.ShouldProcess($sam, "Creer l'utilisateur dans $ouPath")) {
            New-ADUser -Name "$($u.Prenom) $($u.Nom)" `
                -GivenName $u.Prenom -Surname $u.Nom `
                -DisplayName "$($u.Prenom) $($u.Nom)" `
                -SamAccountName $sam `
                -UserPrincipalName "$sam@$UpnSuffix" `
                -Title $u.Titre -Department $u.Departement `
                -Path $ouPath `
                -AccountPassword $initialPassword `
                -ChangePasswordAtLogon $true `
                -Enabled $true

            Add-ADGroupMember -Identity $group -Members $sam
            [pscustomobject]@{ Compte = $sam; Statut = "Cree + ajoute a $group" }
        }
    }
    catch {
        [pscustomobject]@{ Compte = $sam; Statut = "ERREUR : $($_.Exception.Message)" }
    }
}

$results | Format-Table -AutoSize
