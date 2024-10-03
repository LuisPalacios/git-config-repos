#!/bin/bash

# ----------------------------------------------------------------------------------------
# git-config-repos.sh
# ----------------------------------------------------------------------------------------
# Autor: Luis Palacios
# Fecha: 21 de septiembre de 2024
#
# SCRIPT MULTIPLATAFORMA: Probado en Linux, MacOS y Windows con WSL2
#
# Para los usuarios de Windows. Este script modifica el comportamiento de GIT en Windows,
# y hace modificaciones en el File System NTFS (C:\Users\...) pero debe ser ejecutado
# desde WSL2.
#
# Descripción:
#
# Este script automatiza la configuración de repositorios Git para una estación de trabajo
# de un desarrollador, utilizando Git Credential Manager para manejar credenciales mediante
# HTTPS. El script lee un archivo JSON de configuración, que define los parámetros globales
# y específicos de cada cuenta y repositorio, y realiza las siguientes acciones:
#
#  - Configura Git globalmente según los parámetros definidos en el archivo JSON.
#  - Clona repositorios si no existen en el sistema local.
#  - Configura las credenciales y parámetros específicos para cada repositorio.
#
# Ejecución:
#
# chmod +x git-config-repos.sh
# ./git-config-repos.sh
#
# Requisitos:
#
# - Git Credential Manager instalado en Linux, MacOS o Windows (se instala en Windows,
#   no en WSL2)
# - jq: Es necesario tener instalado jq para parsear el archivo JSON. En Windows este
#   comando debe estar instalado dentro de WSL2
# - Acceso de escritura a los directorios donde se clonarán los repositorios. En Windows,
#   se usará el comando git.exe para que la ejecución sea a nivel Windows
# - Permisos para configurar Git globalmente en el sistema.
#
# Riesgos:
#
# - Este script sobrescribirá configuraciones existentes de Git si los parámetros en el
#   archivo JSON difieren de los actuales. Asegúrese de revisar el archivo JSON antes de
#   ejecutar el script para evitar configuraciones no deseadas.
# - Si hay errores en el archivo JSON, el script puede fallar o no configurar los
#   repositorios correctamente.
#
# ----------------------------------------------------------------------------------------

# Trap ctrl-c and call ctrl_c()
trap ctrl_c INT

# ----------------------------------------------------------------------------------------
# Variables Globales
# ----------------------------------------------------------------------------------------

IS_WSL2=false
if grep -qEi "(Microsoft|WSL)" /proc/version &>/dev/null; then
    IS_WSL2=true
    # Para evitar warnings (cuando llamo a cmd.exe y git.exe) cambio a un
    # directorio windows. Obtengo la ruta USERPROFILE de Windows y elimino
    # el retorno de carro (\r). Nota: Necesita instalar wslu (sudo apt install wslu)
    USERPROFILE=$(wslpath "$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r')")
    cd $USERPROFILE
fi

# ----------------------------------------------------------------------------------------
# Pretty Messaging Setup
# ----------------------------------------------------------------------------------------

# Colors for status messages
COLOR_GREEN=$(tput setaf 2)
COLOR_YELLOW=$(tput setaf 3)
COLOR_RED=$(tput setaf 1)

# Terminal width
width=$(tput cols)
message_len=0

# Function to print a message
echo_message() {
    local message=$1
    message_len=${#message}
    printf "%s " "$message"
}

# Function to print a status message (OK, WARNING, ERROR) right-justified
echo_status() {
    local status=$1
    local status_msg
    local status_color

    case $status in
    ok)
        status_msg="OK"
        status_color=${COLOR_GREEN}
        ;;
    warning)
        status_msg="WARNING"
        status_color=${COLOR_YELLOW}
        ;;
    error)
        status_msg="ERROR"
        status_color=${COLOR_RED}
        ;;
    *)
        status_msg="UNKNOWN"
        status_color=${COLOR_RED}
        ;;
    esac

    local status_len=${#status_msg}
    local spaces=$((width - message_len - status_len - 2))

    printf "%${spaces}s" "["
    printf "${status_color}${status_msg}\e[0m"
    echo "]"
}

# ----------------------------------------------------------------------------------------
# Utility Functions
# ----------------------------------------------------------------------------------------

# Función de controlador de señal para manejar CTRL-C
function ctrl_c() {
    echo "** Abortado por CTRL-C"
    exit
}

# Función para convertir una ruta de WSL a una ruta de Windows
# Si no se puede convertir se sale del programa porque se considera
# un error en la configuración del archivo JSON y es grave
#
# Ejemplo de uso
# windos_global_folder=$(convert_wsl_to_windows_path $global_folder)
#
#
convert_wsl_to_windows_path() {
    local wsl_path="$1"

    # Comprobar si el path empieza con /mnt/
    if [[ "$wsl_path" =~ ^/mnt/([a-zA-Z])/ ]]; then
        # Extraer la letra de la unidad
        local drive_letter=$(echo "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')

        # Remover el prefijo /mnt/<unidad>/
        local path_without_prefix="${wsl_path#/mnt/${BASH_REMATCH[1]}/}"

        # Reemplazar las barras inclinadas (/) con barras invertidas (\)
        local windows_path=$(echo "$path_without_prefix" | sed 's|/|\\|g')

        # Formar la ruta final en el formato de Windows
        echo "${drive_letter}:\\${windows_path}"
    else
        echo "Error: La ruta $global_folder no está en el formato esperado de WSL2."
        echo "Revisa global.folder en el .json, asegúrate de que comience con /mnt/<unidad>/"
        exit 1
    fi
}

# Definición de la función wcm_search para buscar credenciales en Windows Credential Manager
wcm_search() {
    local target="$1"
    local user="$2"

    # Ejecutar cmdkey y guardar la salida
    output=$(cmd.exe /c "cmdkey /list" | tr -d '\r')

    # Buscar el bloque que contiene el target y el usuario
    match=$(echo "$output" | awk -v tgt="$target" -v usr="$user" '
        $0 ~ "Target:" && $0 ~ tgt {found_tgt=1}
        found_tgt && $0 ~ "User:" && $0 ~ usr {found_usr=1}
        found_tgt && found_usr {print_block=1}
        print_block && $0 ~ /^$/ {exit}
        print_block {print}
    ')

    # Comprobar si se encontró el bloque
    if [ -n "$match" ]; then
        #echo "$match"
        return 0
    else
        #echo "No se encontró ninguna coincidencia para Target: $target y User: $user"
        return 1
    fi
}

# Función para comprobar la existencia de un comando
check_command() {
    if ! which "$1" >/dev/null; then
        echo "Error: $1 no se encuentra en el PATH."
        return 1
    else
        return 0
    fi
}

# Function to check if a credential is stored in the credential manager
check_credential_in_store() {

    case "$OSTYPE" in
    # MacOS
    darwin* | freebsd*)
        # OSX Keychain
        security find-generic-password -s "git:$1" -a "$2" &>/dev/null
        return $?
        ;;
    # Linux
    *)
        if [ ${IS_WSL2} == true ]; then
            # Windows Credential Manager
            wcm_search "git:$1" "$2"
            return $?
        else
            # Linux Secret Service
            output=$(secret-tool search service "git:$1" account "$2" 2>/dev/null)
            line_count=$(echo "$output" | wc -l)
            if [ "$line_count" -gt 1 ]; then
                return 0
            fi
            return 1
        fi
        ;;
    esac
}

# ----------------------------------------------------------------------------------------
# Dependencias del Script
# ----------------------------------------------------------------------------------------

# PROGRAMAS que deben estar intalados
if [ ${IS_WSL2} == true ]; then
    programs=("git" "jq" "wslpath" "git-credential-manager.exe")
else
    programs=("git" "jq" "git-credential-manager")
fi

# Compruebo las dependencias
for program in "${programs[@]}"; do
    if ! command -v $program &>/dev/null; then

        echo
        echo "Error: $program no está instalado."
        echo
        echo "Hay una serie de dependencias que tienes que tener instaladas:"
        echo

        case "$OSTYPE" in
        # MacOS
        darwin* | freebsd*)
            echo " macos:"
            echo "       brew update && brew upgrade"
            echo "       brew install jq git"
            echo "       brew tap microsoft/git"
            echo "       brew install --cask git-credential-manager-core"
            echo
            ;;
        # Linux
        *)
            if [ ${IS_WSL2} == true ]; then
                echo " windows: Desde una sesión de WSL2"
                echo "       sudo apt update && sudo apt upgrade -y && sudo apt full-upgrade -y"
                echo "       sudo apt install -y jq git"
                echo
                echo " Asegúrate de tener instalador el Git Credential Manager para Windows"
                echo " https://github.com/git-ecosystem/git-credential-manager/releases"
                echo
                echo
            else
                echo " linux:"
                echo "       sudo apt update && sudo apt upgrade -y && sudo apt full-upgrade -y"
                echo "       sudo apt install -y jq git"
                echo
                echo " Asegúrate de tener instalador el Git Credential Manager para Linux"
                echo " https://github.com/git-ecosystem/git-credential-manager/releases"
                echo " Ejemplo: sudo dpkg -i gcm-linux_amd64.2.5.1.deb"
            fi
            ;;
        esac
        exit 1
    fi
done

# En WSL2 comprobar si cmd.exe y git.exe están en el PATH
# Nota, en WSL2 uso git.exe en vez de git de ubuntu porque es compatible con
# el Credential Manager de Windows
if [ ${IS_WSL2} == true ]; then
    # Comprobar cmd.exe
    check_command "cmd.exe"
    cmd_status=$?

    # Comprobar git.exe
    check_command "git.exe"
    git_status=$?

    # Sugerencias para añadir al PATH si no se encuentran
    if [ $cmd_status -ne 0 ] || [ $git_status -ne 0 ]; then
        echo ""
        echo "Añade al PATH:"

        if [ $cmd_status -ne 0 ]; then
            echo "  - /mnt/c/Windows/System32 (para cmd.exe)"
        fi

        if [ $git_status -ne 0 ]; then
            echo "  - /mnt/c/Program Files/Git/mingw64/bin (para git.exe)"
            echo "Te recomiendo que instales Git for Windows desde https://git-scm.com/download/win"
        fi

        echo "Para hacerlo permanente, añádelo a ~/.zshrc, ~/.bashrc o ~/.profile."
        exit 1
    fi
fi

# ----------------------------------------------------------------------------------------
# Main Script Execution
# ----------------------------------------------------------------------------------------

# Ficheros de configuración
if [ ${IS_WSL2} == true ]; then
    # En WSL2 uso git.exe
    git_command="git.exe"
    # En WSL2 trabajo sobre el disco de Windows
    #git_global_config_file="/mnt/c/Users/${USER}/.gitconfig"
    # Cargar y parsear el archivo JSON usando jq
    git_config_repos_json_file="/mnt/c/Users/${USER}/.config/git-config-repos/git-config-repos.json"
else
    # En Mac y Linux el comando git es git
    git_command="git"
    # En Mac y Linux el home del usuario
    #git_global_config_file="${HOME}/.gitconfig"
    # Cargar y parsear el archivo JSON usando jq
    git_config_repos_json_file="$HOME/.config/git-config-repos/git-config-repos.json"
fi
echo_message "* Config $git_config_repos_json_file"
if [ ! -f "$git_config_repos_json_file" ]; then
    echo_status error
    echo "ERROR: El archivo de configuración $git_config_repos_json_file no existe."
    exit 1
fi

# Validar el archivo JSON con jq
jq '.' "$git_config_repos_json_file" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo_status error
    echo "ERROR: El archivo JSON $git_config_repos_json_file contiene errores de sintaxis."
    exit 1
fi
echo_status ok

# Extraer configuraciones globales
global_folder=$(jq -r '.global.folder' "$git_config_repos_json_file")
credential_helper=$(jq -r '.global.credential.helper' "$git_config_repos_json_file")
credential_store=$(jq -r '.global.credential.credentialStore' "$git_config_repos_json_file")

# Crear el directorio global de Git
echo_message "Directorio Git: $global_folder"
mkdir -p "$global_folder" &>/dev/null
if [ $? -ne 0 ]; then
    echo_status error
    echo "ERROR: No se ha podido crear $global_folder."
    exit 1
fi
echo_status ok

# Configurar globalmente Git
echo_message "Configuración de Git global"
$git_command config --global --replace-all credential.helper "$credential_helper"
$git_command config --global credential.credentialStore "$credential_store"
accounts=$(jq -r '.accounts | keys[]' "$git_config_repos_json_file")
for account in $accounts; do
    account_credential_url=$(jq -r ".accounts[\"$account\"].credential_url" "$git_config_repos_json_file")
    account_username=$(jq -r ".accounts[\"$account\"].username" "$git_config_repos_json_file")
    account_provider=$(jq -r ".accounts[\"$account\"].provider" "$git_config_repos_json_file")
    account_useHttpPath=$(jq -r ".accounts[\"$account\"].useHttpPath" "$git_config_repos_json_file")
    # Configurar las credenciales globales para la cuenta
    $git_command config --global credential."$account_credential_url".provider "$account_provider"
    $git_command config --global credential."$account_credential_url".useHttpPath "$account_useHttpPath"
done
echo_status ok

# CREDENCIALES
# Iterar sobre las cuentas para los CREDENCIALES
accounts=$(jq -r '.accounts | keys[]' "$git_config_repos_json_file")
for account in $accounts; do
    account_url=$(jq -r ".accounts[\"$account\"].url" "$git_config_repos_json_file")
    account_credential_url=$(jq -r ".accounts[\"$account\"].credential_url" "$git_config_repos_json_file")
    account_username=$(jq -r ".accounts[\"$account\"].username" "$git_config_repos_json_file")

    # Avisar al usuario para que prepare el navegador para que se autentique
    echo_message "Comprobando credenciales de $account > $account_username"
    check_credential_in_store "$account_credential_url" "$account_username"
    if [ $? -eq 0 ]; then
        echo_status ok
    else
        echo_status warning
        read -p "Preapara tu navegador para autenticar a $account > $account_username - (Enter/Ctrl-C)." confirm
        credenciales="/tmp/tmp-credenciales"
        (
            echo url="$account_credential_url"
            echo "username=$account_username"
            echo
        ) | $git_command credential fill >$credenciales 2>/dev/null
        if [ -f $credenciales ] && [ ! -s $credenciales ]; then
            # No deberia entrar por aquí
            echo "    Ya se habián configurado las credenciales en el pasado"
            echo "$account/$username ya tiene los credenciales configurados en el almacen"
        else
            echo_message "    Añado las credenciales al almacen de credenciales"
            cat $credenciales | $git_command credential approve
            echo_status ok
        fi
    fi
done

# REPORITORIOS
# Iterar sobre las cuentas para los REPOSITORIOS
accounts=$(jq -r '.accounts | keys[]' "$git_config_repos_json_file")
for account in $accounts; do
    account_url=$(jq -r ".accounts[\"$account\"].url" "$git_config_repos_json_file")
    account_clone_url=$(jq -r ".accounts[\"$account\"].clone_url" "$git_config_repos_json_file")
    account_credential_url=$(jq -r ".accounts[\"$account\"].credential_url" "$git_config_repos_json_file")
    account_username=$(jq -r ".accounts[\"$account\"].username" "$git_config_repos_json_file")
    account_folder=$(jq -r ".accounts[\"$account\"].folder" "$git_config_repos_json_file")
    account_provider=$(jq -r ".accounts[\"$account\"].provider" "$git_config_repos_json_file")
    account_useHttpPath=$(jq -r ".accounts[\"$account\"].useHttpPath" "$git_config_repos_json_file")

    # Crear el directorio para la cuenta
    echo_message "  $account_folder"
    mkdir -p "$global_folder/$account_folder"
    if [ $? -ne 0 ]; then
        echo_status error
        echo "ERROR: No se ha podido crear $global_folder/$account_folder."
        exit 1
    fi
    echo_status ok

    # Iterar sobre los repositorios de la cuenta
    repos=$(jq -r ".accounts[\"$account\"].repos | keys[]" "$git_config_repos_json_file")
    for repo in $repos; do
        repo_name=$(jq -r ".accounts[\"$account\"].repos[\"$repo\"].name" "$git_config_repos_json_file")
        repo_email=$(jq -r ".accounts[\"$account\"].repos[\"$repo\"].email" "$git_config_repos_json_file")

        repo_path="$global_folder/$account_folder/$repo"

        # Si el repositorio no existe, clonarlo
        if [ ! -d "$repo_path" ]; then
            echo "   - $repo_path"
            echo_message "    ⬇ $repo_path"

            # Si estamos en WSL2 convertir la ruta de destino del clone a formato C:\..
            if [ ${IS_WSL2} == true ]; then
                destination_directory=$(convert_wsl_to_windows_path $repo_path) # En WSL2
            else
                destination_directory=$repo_path # En Mac y Linux
            fi
            # Clonar el repo
            $git_command clone "$account_clone_url/$repo.git" "$destination_directory" &>/dev/null
            if [ $? -eq 0 ]; then
                echo_status ok
            else
                echo_status error
                continue
            fi
        else
            echo_message "   - $repo_path"
            echo_status ok
        fi

        # Configurar el repositorio local
        cd "$repo_path" || continue
        $git_command remote set-url origin "$account_url/$repo.git"
        $git_command config user.name "$repo_name"
        $git_command config user.email "$repo_email"
        $git_command remote set-url --push origin "$account_url/$repo.git"
        $git_command config credential."$account_credential_url".username "$account_username"

    done
done

# ----------------------------------------------------------------------------------------
