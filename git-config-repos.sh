#!/bin/bash

# ----------------------------------------------------------------------------------------
# git-config-repos.sh
# ----------------------------------------------------------------------------------------
# Autor: Luis Palacios
# Fecha: 21 de septiembre de 2024
# Multiplataforma: Probado en Linux, MacOS y Windows con WSL2
#
# Descripción:
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
# git-config-repos.sh
#
# Requisitos:
# - jq: Es necesario tener instalado jq para parsear el archivo JSON.
# - Acceso de escritura a los directorios donde se clonarán los repositorios.
# - Permisos para configurar Git globalmente en el sistema.
#
# Riesgos:
# - Este script sobrescribirá configuraciones existentes de Git si los parámetros en el
#   archivo JSON difieren de los actuales. Asegúrese de revisar el archivo JSON antes de
#   ejecutar el script para evitar configuraciones no deseadas.
# - Si hay errores en el archivo JSON, el script puede fallar o no configurar los
#   repositorios correctamente.
#
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# Variables Globales
# ----------------------------------------------------------------------------------------

IS_WSL2=false
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
  IS_WSL2=true
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

# Function to check if a credential is stored in the credential manager
check_credential_in_store() {

    case "$OSTYPE" in
      # MacOS
      darwin*|freebsd*)
        security find-generic-password -s "git:$1" -a "$2" &>/dev/null
        return $?
        ;;
      # Linux
      *)
        if [ ${IS_WSL2} == true ]; then
            echo "ERROR TODAVIA NO SE SOPORTA WINDOWS WSL2"
            return 1
        else
            secret-tool search --all "git:" | grep "$1" &>/dev/null
            return $?
        fi
        ;;
    esac
}

# ----------------------------------------------------------------------------------------
# Dependencias del Script
# ----------------------------------------------------------------------------------------

# Array de dependencias
programs=("git" "jq")

# Compruebo las dependencias
for program in "${programs[@]}"; do
    if ! command -v $program &> /dev/null; then
        echo
        echo "Error: $program no está instalado."
        echo
        echo " linux:"
        echo "       sudo apt update && sudo apt upgrade -y && sudo apt full-upgrade -y"
        echo "       sudo apt install -y jq git"
        echo
        echo " macos:"
        echo "       brew update && brew upgrade"
        echo "       brew install jq git"
        echo
        echo " windows: Desde una sesión de WSL2"
        echo "       sudo apt update && sudo apt upgrade -y && sudo apt full-upgrade -y"
        echo "       sudo apt install -y jq git"
        echo
        exit 1
    fi
done

# ----------------------------------------------------------------------------------------
# Main Script Execution
# ----------------------------------------------------------------------------------------

# Cargar y parsear el archivo JSON usando jq
config_file="$HOME/.config/git-config-repos/git-config-repos.json"
echo_message "* Config $config_file"
if [ ! -f "$config_file" ]; then
    echo_status error
    echo "ERROR: El archivo de configuración $config_file no existe."
    exit 1
fi

# Validar el archivo JSON con jq
jq '.' "$config_file" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo_status error
    echo "ERROR: El archivo JSON $config_file contiene errores de sintaxis."
    exit 1
fi
echo_status ok

# Extraer configuraciones globales
global_folder=$(jq -r '.global.folder' "$config_file")
credential_helper=$(jq -r '.global.credential.helper' "$config_file")
credential_store=$(jq -r '.global.credential.credentialStore' "$config_file")

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
git config --global credential.helper "$credential_helper"
git config --global credential.credentialStore "$credential_store"
accounts=$(jq -r '.accounts | keys[]' "$config_file")
for account in $accounts; do
    account_credential_url=$(jq -r ".accounts[\"$account\"].credential_url" "$config_file")
    account_username=$(jq -r ".accounts[\"$account\"].username" "$config_file")
    account_provider=$(jq -r ".accounts[\"$account\"].provider" "$config_file")
    account_useHttpPath=$(jq -r ".accounts[\"$account\"].useHttpPath" "$config_file")
    # Configurar las credenciales globales para la cuenta
    git config --global credential."$account_credential_url".provider "$account_provider"
    git config --global credential."$account_credential_url".useHttpPath "$account_useHttpPath"
    #git config --global credential."$account_credential_url".username "$account_username"
done
echo_status ok


# CREDENCIALES
# Iterar sobre las cuentas para los CREDENCIALES
accounts=$(jq -r '.accounts | keys[]' "$config_file")
for account in $accounts; do
    account_url=$(jq -r ".accounts[\"$account\"].url" "$config_file")
    account_credential_url=$(jq -r ".accounts[\"$account\"].credential_url" "$config_file")
    account_username=$(jq -r ".accounts[\"$account\"].username" "$config_file")

    # Avisar al usuario para que prepare el navegador para que se autentique

    echo_message "Comprobando credenciales de $account > $account_username"
    check_credential_in_store "$account_credential_url" "$account_username"
    if [ $? -eq 0 ]; then
        echo_status ok
    else
        echo_status warning
        read -p "Preapara tu navegador para autenticar a $account > $account_username - (Enter/Ctrl-C)." confirm
        credenciales="/tmp/tmp-credenciales"
        ( echo url="$account_credential_url"; echo "username=$account_username"; echo ) | git credential fill > $credenciales 2>/dev/null
        if [ -f $credenciales ] && [ ! -s $credenciales ]; then
            # No deberia entrar por aquí
            echo "    Ya se habián configurado las credenciales en el pasado"
            echo "$account/$username ya tiene los credenciales configurados en el almacen"
        else
            echo_message "    Añado las credenciales al almacen de credenciales"
            cat $credenciales | git credential approve
            echo_status ok
        fi
    fi
done

# REPORITORIOS
# Iterar sobre las cuentas para los REPOSITORIOS
accounts=$(jq -r '.accounts | keys[]' "$config_file")
for account in $accounts; do
    account_url=$(jq -r ".accounts[\"$account\"].url" "$config_file")
    account_clone_url=$(jq -r ".accounts[\"$account\"].clone_url" "$config_file")
    account_credential_url=$(jq -r ".accounts[\"$account\"].credential_url" "$config_file")
    account_username=$(jq -r ".accounts[\"$account\"].username" "$config_file")
    account_folder=$(jq -r ".accounts[\"$account\"].folder" "$config_file")
    account_subfolder=$(jq -r ".accounts[\"$account\"].subfolder" "$config_file")
    if [ $account_subfolder == "null" ]; then
        account_subfolder=""
    fi
    account_provider=$(jq -r ".accounts[\"$account\"].provider" "$config_file")
    account_useHttpPath=$(jq -r ".accounts[\"$account\"].useHttpPath" "$config_file")

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
    repos=$(jq -r ".accounts[\"$account\"].repos | keys[]" "$config_file")
    for repo in $repos; do
        repo_name=$(jq -r ".accounts[\"$account\"].repos[\"$repo\"].name" "$config_file")
        repo_email=$(jq -r ".accounts[\"$account\"].repos[\"$repo\"].email" "$config_file")

        # Crea estructura de carpeta(s) si el repo tiene un subdir
        if [ -n "$account_subfolder" ]; then
            repo_path="$global_folder/$account_folder/$account_subfolder/$repo"
        else
            repo_path="$global_folder/$account_folder/$repo"
        fi

        # Si el repositorio no existe, clonarlo
        if [ ! -d "$repo_path" ]; then
            echo         "   - $repo_path"
            echo_message "    ⬇ $repo_path"
            git clone "$account_clone_url/$repo.git" "$repo_path" &>/dev/null
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
        git remote set-url origin "$account_url/$repo.git"
        git config user.name "$repo_name"
        git config user.email "$repo_email"
        git remote set-url --push origin "$account_url/$repo.git"
        git config credential."$account_credential_url".username "$account_username"

    done
done

# ----------------------------------------------------------------------------------------
