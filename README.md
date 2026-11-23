# 🧩 Lab X — Active Directory sur Windows Server 2022

> Lab pratique de niveau **technicien N1/N2** : déploiement d'un domaine Active Directory complet (AD DS, DNS, DHCP, GPO, partages) dans VirtualBox, puis réalisation des tâches courantes du support et de cas de dépannage réels.

![Windows Server](https://img.shields.io/badge/Windows%20Server-2022-0078D6?logo=windows)
![VirtualBox](https://img.shields.io/badge/VirtualBox-7.x-183A61?logo=virtualbox)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell)
![Coût](https://img.shields.io/badge/Co%C3%BBt-0%20%24-success)

---

## 📌 Objectifs

- Installer et configurer un **contrôleur de domaine** (AD DS + DNS intégré)
- Déployer un serveur **DHCP** autorisé dans AD
- Construire une **arborescence d'OU** claire et une stratégie de groupes **AGDLP**
- Créer des utilisateurs **en masse** avec PowerShell (CSV)
- Appliquer des **GPO** (mots de passe, verrouillage, mappage de lecteur, restrictions)
- Joindre un **poste client Windows 11** au domaine
- Réaliser les **tâches N1** (réinitialisation, déverrouillage, départ d'employé)
- Diagnostiquer des **pannes N2** (DNS, GPO, jonction au domaine)

## 🏗️ Architecture

```
                 VirtualBox — NAT Network "LAB-AD" (192.168.50.0/24)
                 Passerelle VirtualBox : 192.168.50.1 (accès Internet)
                                   │
          ┌────────────────────────┴────────────────────────┐
          │                                                 │
┌─────────┴───────────┐                          ┌──────────┴─────────┐
│ DC01                │                          │ CLIENT01           │
│ Windows Server 2022 │                          │ Windows 11 Ent.    │
│ 192.168.50.10 (fixe)│◄──── DHCP / DNS / AD ────│ DHCP (.100 à .200) │
│ AD DS · DNS · DHCP  │                          │ Membre de lab.local│
│ Partage de fichiers │                          │                    │
└─────────────────────┘                          └────────────────────┘
```

| Élément | Valeur |
|---|---|
| Domaine | `lab.local` (NetBIOS : `LAB`) |
| Contrôleur de domaine | `DC01` — 192.168.50.10/24 |
| Passerelle | 192.168.50.1 (NAT VirtualBox) |
| Redirecteurs DNS | 1.1.1.1, 8.8.8.8 |
| Étendue DHCP | 192.168.50.100 à 192.168.50.200 |
| Poste client | `CLIENT01` (Windows 11 Enterprise) |

> 💡 **Note sur le nom de domaine** : `.local` convient pour un lab isolé. En production, on utilise plutôt un sous-domaine d'un domaine qu'on possède (ex. `ad.entreprise.com`) pour éviter les conflits avec mDNS et faciliter les certificats.

## 🧰 Prérequis (0 $)

| Ressource | Source |
|---|---|
| VirtualBox 7.x | virtualbox.org |
| ISO Windows Server 2022 (évaluation 180 jours) | Microsoft Evaluation Center |
| ISO Windows 11 Enterprise (évaluation 90 jours) | Microsoft Evaluation Center |
| PC hôte | 16 Go de RAM recommandés, ~100 Go libres |

| VM | vCPU | RAM | Disque |
|---|---|---|---|
| DC01 | 2 | 4 Go | 60 Go |
| CLIENT01 | 2 | 4 Go | 64 Go (TPM 2.0 + Secure Boot activés dans VirtualBox 7) |

---

## 🚀 Déploiement étape par étape

### Étape 1 — Créer le réseau NAT dans VirtualBox

1. **Fichier → Outils → Gestionnaire de réseau → onglet NAT Networks → Créer**
2. Nom : `LAB-AD` · Préfixe IPv4 : `192.168.50.0/24`
3. **Décocher « Enable DHCP »**, puisque c'est DC01 qui fera le DHCP.

> Pourquoi un NAT Network : les VM se voient entre elles **et** ont accès à Internet, sans exposer le lab au réseau de la maison.

### Étape 2 — Installer Windows Server 2022 (DC01)

1. Nouvelle VM : `DC01`, ISO Server 2022, **cocher « Skip Unattended Installation »**.
2. Réseau : **Carte 1 → Réseau NAT → LAB-AD**.
3. Installer l'édition **Windows Server 2022 Standard Evaluation (Desktop Experience)**.
4. Définir le mot de passe Administrateur local.
5. Installer les **Guest Additions** (Périphériques → Insérer l'image CD des Additions invité).
6. 📸 **Prendre un instantané** : `00-OS-installe`.

### Étape 3 — Configuration de base du serveur

PowerShell **en administrateur** :

```powershell
# Identifier la carte réseau
Get-NetAdapter

# IP fixe (adapter -InterfaceAlias si nécessaire)
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.50.10 -PrefixLength 24 -DefaultGateway 192.168.50.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 1.1.1.1   # temporaire, avant la promotion

# Fuseau horaire et nom
Set-TimeZone -Id "Eastern Standard Time"
Rename-Computer -NewName "DC01" -Restart
```

Après le redémarrage : lancer **Windows Update** et appliquer les mises à jour.

### Étape 4 — Installer AD DS et promouvoir en contrôleur de domaine

```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Install-ADDSForest `
    -DomainName "lab.local" `
    -DomainNetbiosName "LAB" `
    -InstallDns `
    -SafeModeAdministratorPassword (Read-Host -AsSecureString "Mot de passe DSRM") `
    -Force
```

Le serveur redémarre. Tu te connectes ensuite avec **`LAB\Administrator`**.

Vérifications :

```powershell
Get-ADDomain | Select-Object DNSRoot, NetBIOSName, PDCEmulator
Get-DnsClientServerAddress -InterfaceAlias "Ethernet"   # doit pointer vers 127.0.0.1 / ::1
dcdiag /q                                              # aucune sortie = aucune erreur
```

> 🔎 **Constaté pendant le lab** : juste après la promotion, `dcdiag /q` signale `failed test DFSREvent`. Ce test remonte tout avertissement DFS Replication des dernières 24 h, y compris ceux émis au démarrage avant que le DNS ou AD soient prêts. Sur un premier DC, c'est normal tant que SYSVOL est bien partagé :
>
> ```powershell
> net share | findstr /i "SYSVOL NETLOGON"     # les deux partages doivent exister
> dfsrmig /getglobalstate                      # attendu : « Eliminated » (SYSVOL répliqué par DFSR)
> Get-WinEvent -LogName "DFS Replication" -MaxEvents 20 |
>     Where-Object LevelDisplayName -ne "Information" | Format-List TimeCreated, Id, Message
> dcdiag /test:sysvolcheck /test:advertising   # doivent réussir
> ```
>
> Relancer `dcdiag /q` après 24 h : l'erreur disparaît si aucun nouvel avertissement n'est apparu.

📸 Instantané : `01-DC-promu`.

### Étape 5 — Configurer le DNS

```powershell
# Redirecteurs vers Internet
Set-DnsServerForwarder -IPAddress 1.1.1.1, 8.8.8.8

# Zone de recherche inversée
Add-DnsServerPrimaryZone -NetworkId "192.168.50.0/24" -ReplicationScope Domain

# Enregistrement PTR du DC
ipconfig /registerdns

# Tests
Resolve-DnsName dc01.lab.local
Resolve-DnsName -Type SRV _ldap._tcp.dc._msdcs.lab.local
Resolve-DnsName microsoft.com
```

### Étape 6 — Installer et autoriser le DHCP

```powershell
Install-WindowsFeature DHCP -IncludeManagementTools

# Groupes de sécurité DHCP + autorisation dans AD
netsh dhcp add securitygroups
Restart-Service DHCPServer
Add-DhcpServerInDC -DnsName "dc01.lab.local" -IPAddress 192.168.50.10

# Retirer l'avertissement « configuration post-installation » du Gestionnaire de serveur
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name ConfigurationState -Value 2

# Étendue + options (003 routeur, 006 DNS, 015 suffixe)
Add-DhcpServerv4Scope -Name "LAB-Clients" -StartRange 192.168.50.100 -EndRange 192.168.50.200 `
    -SubnetMask 255.255.255.0 -LeaseDuration 8.00:00:00 -State Active
Set-DhcpServerv4OptionValue -ScopeId 192.168.50.0 -Router 192.168.50.1 `
    -DnsServer 192.168.50.10 -DnsDomain "lab.local"
```

### Étape 7 — Arborescence des OU

```
lab.local
└── LAB
    ├── Utilisateurs
    │   ├── Direction
    │   ├── Comptabilite
    │   ├── Ventes
    │   └── TI
    ├── Ordinateurs
    ├── Groupes
    ├── Comptes-Service
    └── Desactives
```

```powershell
$base = "DC=lab,DC=local"
New-ADOrganizationalUnit -Name "LAB" -Path $base
$lab = "OU=LAB,$base"

"Utilisateurs","Ordinateurs","Groupes","Comptes-Service","Desactives" | ForEach-Object {
    New-ADOrganizationalUnit -Name $_ -Path $lab
}
"Direction","Comptabilite","Ventes","TI" | ForEach-Object {
    New-ADOrganizationalUnit -Name $_ -Path "OU=Utilisateurs,$lab"
}

# Les nouveaux ordinateurs joints au domaine arrivent dans la bonne OU (au lieu de CN=Computers)
redircmp "OU=Ordinateurs,OU=LAB,DC=lab,DC=local"
```

> Les OU créées via PowerShell sont protégées contre la suppression accidentelle par défaut. C'est une bonne pratique.

### Étape 8 — Groupes (modèle AGDLP)

**AGDLP** : les comptes (**A**) vont dans des groupes **G**lobaux par service, qui vont dans des groupes de **D**omaine **L**ocal qui portent les **P**ermissions.

```powershell
$grp = "OU=Groupes,OU=LAB,DC=lab,DC=local"

# Groupes globaux par service
"Direction","Comptabilite","Ventes","TI" | ForEach-Object {
    New-ADGroup -Name "GG_$_" -GroupScope Global -GroupCategory Security -Path $grp
}

# Groupes domaine local pour les droits sur le partage
New-ADGroup -Name "DL_Partage_Compta_RW" -GroupScope DomainLocal -GroupCategory Security -Path $grp
New-ADGroup -Name "DL_Partage_Compta_RO" -GroupScope DomainLocal -GroupCategory Security -Path $grp

Add-ADGroupMember -Identity "DL_Partage_Compta_RW" -Members "GG_Comptabilite"
Add-ADGroupMember -Identity "DL_Partage_Compta_RO" -Members "GG_Direction"
```

### Étape 9 — Création des utilisateurs en masse

Le script [`scripts/New-LabUsers.ps1`](scripts/New-LabUsers.ps1) lit [`scripts/users.csv`](scripts/users.csv), crée chaque compte (`prenom.nom`) dans l'OU de son service, l'ajoute au groupe `GG_<Service>` et force le changement de mot de passe à la première connexion.

```powershell
cd C:\Lab\scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\New-LabUsers.ps1 -CsvPath .\users.csv
```

### Étape 10 — Partage de fichiers « Comptabilite »

Bonne pratique : **permissions de partage larges** et **NTFS restrictives**.

```powershell
New-Item -Path "C:\Partages\Comptabilite" -ItemType Directory

New-SmbShare -Name "Comptabilite" -Path "C:\Partages\Comptabilite" `
    -FullAccess "LAB\Domain Admins" -ChangeAccess "Authenticated Users"

# NTFS : retirer l'héritage, puis donner les droits aux groupes DL
icacls "C:\Partages\Comptabilite" /inheritance:r `
    /grant "SYSTEM:(OI)(CI)F" "LAB\Domain Admins:(OI)(CI)F" `
           "LAB\DL_Partage_Compta_RW:(OI)(CI)M" "LAB\DL_Partage_Compta_RO:(OI)(CI)RX"

# Bonus : n'afficher que les dossiers auxquels l'utilisateur a accès (ABE)
Set-SmbShare -Name "Comptabilite" -FolderEnumerationMode AccessBased -Force
```

> ⚠️ Si ton serveur est installé **en français**, les noms des groupes intégrés changent : `Admins du domaine`, `Utilisateurs authentifiés`, `Système`.

### Étape 11 — Stratégies de groupe (GPO)

**a) Politique de mots de passe et de verrouillage (au niveau du domaine)**

```powershell
Set-ADDefaultDomainPasswordPolicy -Identity "lab.local" `
    -MinPasswordLength 12 -ComplexityEnabled $true -MaxPasswordAge 90.00:00:00 `
    -LockoutThreshold 5 -LockoutDuration 00:15:00 -LockoutObservationWindow 00:15:00
```

**b) Création et liaison des GPO**

```powershell
$users = "OU=Utilisateurs,OU=LAB,DC=lab,DC=local"
$compta = "OU=Comptabilite,$users"
$ventes = "OU=Ventes,$users"

New-GPO -Name "U-Compta-MappageLecteur"   | New-GPLink -Target $compta
New-GPO -Name "U-Ventes-RestrictionPanneau" | New-GPLink -Target $ventes
New-GPO -Name "C-Tous-BanniereConnexion"  | New-GPLink -Target "OU=Ordinateurs,OU=LAB,DC=lab,DC=local"
```

Puis configurer chaque GPO dans **Gestion des stratégies de groupe (gpmc.msc)** :

| GPO | Chemin | Paramètre |
|---|---|---|
| U-Compta-MappageLecteur | Config. utilisateur → Préférences → Paramètres Windows → Mappages de lecteurs | Nouveau : `\\DC01\Comptabilite`, lettre **S:**, action *Mettre à jour* |
| U-Ventes-RestrictionPanneau | Config. utilisateur → Stratégies → Modèles d'administration → Panneau de configuration | *Interdire l'accès au Panneau de configuration et aux paramètres du PC* → **Activé** |
| C-Tous-BanniereConnexion | Config. ordinateur → Stratégies → Paramètres Windows → Paramètres de sécurité → Stratégies locales → Options de sécurité | *Ouverture de session interactive : titre / texte du message* → avertissement d'utilisation |

📸 Instantané : `02-AD-configure`.

### Étape 12 — Joindre CLIENT01 au domaine

1. Installer Windows 11 Enterprise dans une VM reliée au réseau NAT **LAB-AD**.
2. Vérifier que le client reçoit une IP du DHCP :
   ```cmd
   ipconfig /all          :: IP en 192.168.50.100-200, DNS = 192.168.50.10, suffixe lab.local
   nslookup lab.local
   ```
3. Joindre le domaine (PowerShell admin sur le client) :
   ```powershell
   Rename-Computer -NewName "CLIENT01"
   Add-Computer -DomainName "lab.local" -Credential "LAB\Administrator" -Restart
   ```
4. Sur DC01, vérifier que l'ordinateur est bien dans l'OU `Ordinateurs` (grâce à `redircmp`) :
   ```powershell
   Get-ADComputer CLIENT01 | Select-Object DistinguishedName
   ```
5. Se connecter avec un compte de la Comptabilité et vérifier le lecteur **S:**, puis avec un compte des Ventes et vérifier le blocage du Panneau de configuration.
   ```cmd
   gpupdate /force
   gpresult /r
   ```

📸 Instantané : `03-Client-joint`.

---

## 🎫 Scénarios N1 : tâches courantes du support

| # | Billet | Commandes |
|---|---|---|
| 1 | « J'ai oublié mon mot de passe » | `Set-ADAccountPassword jean.tremblay -Reset -NewPassword (Read-Host -AsSecureString)` puis `Set-ADUser jean.tremblay -ChangePasswordAtLogon $true` |
| 2 | « Mon compte est bloqué » | `Search-ADAccount -LockedOut` puis `Unlock-ADAccount jean.tremblay` |
| 3 | « J'ai besoin d'accéder au dossier Comptabilité » | `Add-ADGroupMember GG_Comptabilite -Members marie.gagnon` (déconnexion/reconnexion nécessaire pour le nouveau jeton) |
| 4 | Départ d'un employé | `Disable-ADAccount luc.roy` puis `Get-ADUser luc.roy \| Move-ADObject -TargetPath "OU=Desactives,OU=LAB,DC=lab,DC=local"` |
| 5 | « Qui fait partie du groupe Ventes ? » | `Get-ADGroupMember GG_Ventes \| Select-Object Name, SamAccountName` |
| 6 | Audit des comptes inactifs | `Search-ADAccount -AccountInactive -TimeSpan 90.00:00:00 -UsersOnly` |

## 🔧 Scénarios N2 : dépannage

### Panne 1 — « Le domaine lab.local est introuvable » lors de la jonction
- **Reproduction** : configurer manuellement le DNS du client sur `8.8.8.8`.
- **Diagnostic** : `ipconfig /all` → le DNS ne pointe pas vers le DC ; `nslookup -type=SRV _ldap._tcp.dc._msdcs.lab.local` échoue.
- **Cause** : le client doit utiliser **le DNS AD** pour trouver les enregistrements SRV du contrôleur de domaine.
- **Correctif** : remettre le DNS en automatique (DHCP) ou sur `192.168.50.10`.

### Panne 2 — Le lecteur S: n'apparaît pas pour un comptable
- **Reproduction** : déplacer l'utilisateur dans l'OU `Ventes`, ou délier la GPO.
- **Diagnostic** : `gpresult /r` (section *Objets de stratégie de groupe appliqués*) ; `gpresult /h rapport.html`.
- **Causes possibles** : utilisateur dans la mauvaise OU, GPO non liée ou désactivée, filtrage de sécurité, GPO utilisateur liée à une OU d'ordinateurs.
- **Correctif** : corriger l'OU ou le lien, puis `gpupdate /force` et reconnexion.

### Panne 3 — Verrouillages de compte répétés
- **Reproduction** : saisir 5 mauvais mots de passe sur CLIENT01.
- **Diagnostic** : `Get-ADUser jean.tremblay -Properties LockedOut, BadLogonCount, LastBadPasswordAttempt` ; Observateur d'événements du DC → Sécurité → **ID 4740**.
- **Correctif** : `Unlock-ADAccount`, puis trouver la source (session mémorisée, lecteur mappé avec un ancien mot de passe, téléphone).

### Panne 4 — Le client perd la relation d'approbation avec le domaine
- **Reproduction** : restaurer un ancien instantané de CLIENT01 après un changement de mot de passe machine.
- **Diagnostic** : message « La relation d'approbation entre cette station de travail et le domaine principal a échoué » ; `Test-ComputerSecureChannel`.
- **Correctif** : `Test-ComputerSecureChannel -Repair -Credential LAB\Administrator` (depuis un compte admin local).

### Commandes de santé du DC
```powershell
dcdiag /v
nltest /dsgetdc:lab.local
Get-Service NTDS, DNS, Netlogon, KDC, DHCPServer
Get-DhcpServerv4Lease -ScopeId 192.168.50.0
```

---

## 📸 Captures d'écran

Les captures sont dans [`/screenshots`](screenshots) :

| Fichier | Contenu |
|---|---|
| `01-virtualbox-natnetwork.png` | Réseau NAT LAB-AD |
| `02-addsforest-success.png` | Promotion du DC |
| `03-dns-zones.png` | Zones directe et inversée |
| `04-dhcp-scope.png` | Étendue DHCP active |
| `05-aduc-ou-structure.png` | Arborescence des OU |
| `06-users-created.png` | Sortie du script de création |
| `07-gpmc-links.png` | GPO liées |
| `08-client-joined.png` | CLIENT01 membre du domaine |
| `09-gpresult.png` | GPO appliquées sur le client |
| `10-drive-s-mapped.png` | Lecteur S: mappé |

## 🧠 Ce que j'ai appris

- Le **DNS est le cœur d'Active Directory** : la majorité des pannes de jonction ou d'authentification viennent d'un client qui ne pointe pas vers le DNS du DC.
- **AGDLP** rend la gestion des accès évolutive : on ajoute une personne à un groupe de service, pas à 15 ACL différentes.
- Une GPO **utilisateur** doit être liée à une OU qui contient des **utilisateurs** (et une GPO ordinateur, à une OU d'ordinateurs).
- `gpresult` et l'Observateur d'événements sont les premiers réflexes de diagnostic.
- Les **instantanés** VirtualBox permettent de casser et de réparer sans risque.

## 🔜 Améliorations possibles

- Ajouter un **second contrôleur de domaine** (DC02) et tester la réplication (`repadmin /replsummary`)
- Déployer **LAPS** (Windows LAPS) pour les mots de passe admin locaux
- Créer des **comptes administrateurs séparés** (`adm-prenom.nom`) et un modèle de tiering
- Installer **WSUS** ou une autorité de certification (**AD CS**)
- Connecter le domaine à **Microsoft Entra ID** (Entra Connect) pour un scénario hybride

## 📂 Structure du dépôt

```
lab-active-directory/
├── README.md
├── scripts/
│   ├── New-LabUsers.ps1
│   └── users.csv
└── screenshots/
```

---

👤 **Auteur** : Vanick · Lab réalisé dans le cadre d'une série de labs réseau et administration système.
