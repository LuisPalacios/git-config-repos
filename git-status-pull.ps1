# ----------------------------------------------------------------------------------------
# git-status-pull.ps1
# ----------------------------------------------------------------------------------------
# Autor: Luis Palacios
# Fecha: 3 de octubre de 2024
#

param (
    [switch]$Verbose,
    [switch]$Pull,
    [switch]$Help
)
# Guardar el directorio original
$originalDir = Get-Location

# Colores (si se está ejecutando en una terminal compatible)
$red = "`e[31m"
$green = "`e[32m"
$yellow = "`e[33m"
$purple = "`e[35m"
$reset = "`e[0m"


# Mostrar la información de uso del script
function Show-Usage {
    Write-Host "Uso del script: git-status-pull.ps1 [-Verbose] [-Pull] [-Help]"
    Write-Host ""
    Write-Host "Opciones:"
    Write-Host "  -Verbose     Muestra salida detallada."
    Write-Host "  -Pull        Realiza un 'git pull' automáticamente si es posible."
    Write-Host "  -Help        Muestra este mensaje de ayuda."
    Write-Host ""
    Write-Host "Este script verifica el estado de múltiples repositorios Git desde el directorio actual."
    Write-Host "Proporciona información detallada sobre cada repositorio, incluyendo:"
    Write-Host "- La rama actual."
    Write-Host "- El número de commits adelantados/atrasados respecto al upstream."
    Write-Host "- La presencia de archivos no rastreados, modificados, en stage y stashes."
    Write-Host "- Si el repositorio es seguro para hacer pull o necesita ser revisado."
    Write-Host ""
    exit 0
}

# Si se proporciona el parámetro -Help, mostrar la ayuda y salir
if ($Help) {
    Show-Usage
}

# Validar parámetros
$validParameters = @("Verbose", "Pull", "Help")

# Validar si hay parámetros incorrectos o mal escritos
foreach ($param in $PSCmdlet.MyInvocation.BoundParameters.Keys) {
    if ($validParameters -notcontains $param) {
        Write-Host "Error: Parámetro no soportado '$param'."
        Show-Usage
    }
}

# Validar si hay parámetros posicionales no soportados
if ($args.Count -gt 0) {
    Write-Host "Error: Parámetro posicional no soportado: '$($args -join ' ')'."
    Show-Usage
}

# Lista de repositorios ya evaluados (global para que persista entre las llamadas a funciones)
$global:evaluatedRepos = @()

# Escritura de texto con color
function Write-Color {
    param (
        [string]$Text,
        [string]$Color = $reset
    )
    Write-Host "$Color$Text$reset"
}

# Comprobar si un repositorio está dentro de otro ya evaluado
function Is-RepoInsideAnother {
    param (
        [string]$repoPath
    )

    # Normalizar el camino para asegurar consistencia en la comparación
    $normalizedRepoPath = (Get-Item $repoPath).FullName.ToLower()
    #Write-Host "  Normalizado: $normalizedRepoPath"
    #Write-Host "  Contenido de evaluatedRepos: $($global:evaluatedRepos -join ', ')"

    # Verificar si la ruta actual es una subruta de algún repositorio ya evaluado
    foreach ($evaluatedRepo in $global:evaluatedRepos) {
        $normalizedEvaluatedRepo = (Get-Item $evaluatedRepo).FullName.ToLower()
        #Write-Host "  Comparando con: $normalizedEvaluatedRepo"
        if ($normalizedRepoPath.StartsWith($normalizedEvaluatedRepo)) {
            return $true
        }
    }
    return $false
}

# Comprobar el estado de un repositorio Git
function Check-GitStatus {
    # Parámetros de entrada
    param (
        [string]$RepoPath
    )

    # Si el repositorio está dentro de otro, lo ignoramos
    if (Is-RepoInsideAnother -repoPath $RepoPath) {
        #Write-Color "  Repositorio dentro de otro, se ignora: $RepoPath" $yellow
        return
    }

    # Añadir el repositorio a la lista de evaluados
    $global:evaluatedRepos += (Get-Item $repoPath).FullName.ToLower()

    # Cambiar al directorio del repositorio
    Set-Location -Path $RepoPath

    # Imprimir el nombre del repositorio
    $repoName = Get-Item -Path . | Select-Object -ExpandProperty Name
    Write-Host "Repositorio: $repoName"

    # Hacer fetch para saber si estamos atrasados
    git fetch origin --quiet

    # Estado de la rama
    $branchName = git rev-parse --abbrev-ref HEAD
    if ($Verbose) {
        Write-Color "  Rama: $branchName" $green
    }

    # Adelantado/Atrasado
    $ahead = (git rev-list --count "@{u}..HEAD" 2>$null)
    $behind = (git rev-list --count "HEAD..@{u}" 2>$null)
    if ($Verbose) {
        if ($ahead -ne 0) {
            Write-Color "  Commits adelantados: $ahead" $red
        }
        if ($behind -ne 0) {
            Write-Color "  Commits por detrás: $behind" $green
        }
    }

    # Divergencia (si hay commits por delante y por detrás)
    $diverged = ($ahead -ne 0 -and $behind -ne 0)
    if ($diverged -and $Verbose) {
        Write-Color "  Divergencia: sí" $red
    }

    # Verificar stashes
    $stashed = (git stash list | Measure-Object).Count
    if ($stashed -gt 0 -and $Verbose) {
        Write-Color "  Elementos en stash: $stashed" $red
    }

    # Verificar staged
    $staged = (git diff --cached --name-only | Measure-Object).Count
    if ($staged -gt 0 -and $Verbose) {
        Write-Color "  Archivos en stage: $staged" $red
    }

    # Verificar archivos no rastreados
    $untracked = (git ls-files --others --exclude-standard | Measure-Object).Count
    if ($untracked -gt 0 -and $Verbose) {
        Write-Color "  Archivos no rastreados: $untracked" $red
    }

    # Verificar archivos modificados
    $modified = (git ls-files -m | Measure-Object).Count
    if ($modified -gt 0 -and $Verbose) {
        Write-Color "  Archivos modificados: $modified" $red
    }

    # Verificar archivos movidos/renombrados
    $moved = (git diff --name-status | Select-String '^R' | Measure-Object).Count
    if ($moved -gt 0 -and $Verbose) {
        Write-Color "  Archivos movidos: $moved" $red
    }

    # Verificar si hay commits pendientes de push
    $pending_push = $ahead
    if ($pending_push -gt 0 -and $Verbose) {
        Write-Color "  Push pendiente (commits): $pending_push" $red
    }

    # Verificar si es seguro hacer pull
    if ($ahead -eq 0 -and $diverged -eq $false -and $stashed -eq 0 -and $staged -eq 0 -and $untracked -eq 0 -and $modified -eq 0 -and $moved -eq 0 -and $pending_push -eq 0) {
        if ($behind -eq 0) {
            Write-Host "  Estado: LIMPIO"
        } else {
            if ($Pull) {
                Write-Color "  Estado: HACIENDO PULL" $purple
                git pull
            } else {
                Write-Color "  Estado: NECESITA PULL" $green
            }
        }
    } else {
        Write-Color "  Estado: REQUIERE REVISIÓN" $red
    }

    Set-Location -Path ..  # Volver al directorio original
}

# ----------------------------------------------------------------------------------------
# Ejecución principal del script
# ----------------------------------------------------------------------------------------

try {
    Write-Host "Analizando los repositorios Git en el directorio actual..."

    # Buscar todos los directorios que contienen un repositorio Git
    $repos = Get-ChildItem -Recurse -Directory | Where-Object { Test-Path "$($_.FullName)\.git" }

    foreach ($repo in $repos) {
        Check-GitStatus -RepoPath $repo.FullName
    }

} finally {
    # Volver al directorio original cuando termine
    Set-Location -Path $originalDir
}
