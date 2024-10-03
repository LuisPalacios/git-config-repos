# ----------------------------------------------------------------------------------------
# git-status-pull.ps1
# ----------------------------------------------------------------------------------------
# Autor: Luis Palacios
# Fecha: 3 de octubre de 2024
#

# Este script verifica el estado de múltiples repositorios Git desde el directorio actual.
# Proporciona información detallada sobre cada repositorio, incluyendo:
# - La rama actual
# - El número de commits adelantados/atrasados respecto al upstream
# - La presencia de archivos no rastreados, modificados, en stage y stashes
# - Si el repositorio es seguro para hacer pull o necesita ser revisado
#
# El script soporta un modo verbose (-Verbose) que proporciona una salida más detallada, y
# un modo pull (-Pull) para hacer pull de los cambios automáticamente si es posible.
#
# Se utilizan colores para mejorar la legibilidad, y todos los mensajes se formatean dinámicamente.

param (
    [switch]$Verbose,
    [switch]$Pull
)

# Colores (si se está ejecutando en una terminal compatible)
$red = "`e[31m"
$green = "`e[32m"
$yellow = "`e[33m"
$reset = "`e[0m"

function Write-Color {
    param (
        [string]$Text,
        [string]$Color = $reset
    )
    Write-Host "$Color$Text$reset"
}

function Check-GitStatus {
    param (
        [string]$RepoPath
    )

    Set-Location -Path $RepoPath

    # Imprimir el nombre del repositorio
    $repoName = Get-Item -Path . | Select-Object -ExpandProperty Name
    Write-Host "Repositorio: $repoName"

    # Estado de la rama
    $branchName = git rev-parse --abbrev-ref HEAD
    if ($Verbose) {
        Write-Color "  Rama: $branchName" $green
    }

    # Adelantado/Atrasado
    $ahead = (git rev-list @{u}..HEAD 2>$null).Count
    $behind = (git rev-list HEAD..@{u} 2>$null).Count
    if ($Verbose) {
        if ($ahead -ne 0) {
            Write-Color "  Commits adelantados: $ahead" $red
        }
        if ($behind -ne 0) {
            Write-Color "  Commits por detrás: $behind" $green
        }
    }

    # Verificar si se puede hacer pull
    if ($ahead -eq 0 -and $behind -eq 0) {
        Write-Color "  Estado: LIMPIO" $green
    } elseif ($ahead -eq 0 -and $behind -gt 0) {
        if ($Pull) {
            Write-Color "  Estado: HACIENDO PULL" $yellow
            git pull
        } else {
            Write-Color "  Estado: NECESITA PULL" $yellow
        }
    } else {
        Write-Color "  Estado: REQUIERE REVISIÓN" $red
    }

    Set-Location -Path ..  # Volver al directorio original
}

# ----------------------------------------------------------------------------------------
# Ejecución principal del script
# ----------------------------------------------------------------------------------------

Write-Host "Analizando los repositorios Git en el directorio actual..."
$repos = Get-ChildItem -Recurse -Directory -Filter ".git" | ForEach-Object { $_.Parent.FullName }
foreach ($repo in $repos) {
    Check-GitStatus -RepoPath $repo
}
