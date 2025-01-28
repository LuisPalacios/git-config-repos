#!/bin/bash

# ----------------------------------------------------------------------------------------
# git-config-repos.sh
# ----------------------------------------------------------------------------------------
# Autor: Luis Palacios
# Fecha: 21 de septiembre de 2024
#
# SCRIPT MULTIPLATAFORMA: Probado en Linux, MacOS y Windows con WSL2
#
# Nota previa solo para usuarios de Windows. Este script debe ser ejecutado desde WSL2,
# aunque las modificaciones que hace serán en el "C:\Users\..."
#
# Descripción:
#
# Este script permite configurar repositorios Git de forma automática en tu equipo,
# soportando múltiples cuentas con uno o más proveedores Git (GitHub, GitLab, Gitea, ...),
# y también definiendo con qué método quieres autenticarte en cada cuenta y repositorio.
#
# Soporta dos métodos. El primero es HTTPS + Git Credential Manager, muy útil y recomendado
# en entornos de desktop. El segundo es SSH multicuenta, óptimo para entornos
# “headless”, servidores a los que nos conectamos en remoto vía (CLI o VSCode remote).
#
# El script lee un archivo JSON de configuración, que define parámetros globales
# y los específicos de cada cuenta y repositorio:
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
# - Git Credential Manager en Linux, MacOS o Windows (se instala en Windows, no en WSL2)
# - Cliente SSH instalado y configurado para autenticación SSH.
# - jq: Es necesario tener instalado jq para parsear el archivo JSON. En Windows este
#   comando debe estar instalado dentro de WSL2
# - Acceso de escritura a los directorios donde se clonarán los repositorios. En Windows,
#   aunque el script se ejecuta en WSL, usará git.exe para que su ejecución sea desde Windows
#   y no desde WSL2, para evitar el problema de lentitud de Git bajo WSL2.
# - Acceso a Internet para clonar los repositorios.
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

# Capturo Ctrl-C y hago que llame al a función ctrl_c()
trap ctrl_c INT

# ----------------------------------------------------------------------------------------
# Variables Globales
# ----------------------------------------------------------------------------------------
credential_ssh="false"
credential_gcm="true"

# Averiguar si estamos en WSL2
IS_WSL2=false
if grep -qEi "(Microsoft|WSL)" /proc/version &>/dev/null; then
    IS_WSL2=true
    # Para evitar warnings (cuando llamo a cmd.exe y git.exe) cambio a un
    # directorio windows. Obtengo la ruta USERPROFILE de Windows y elimino
    # el retorno de carro (\r). Nota: Necesita instalar wslu (sudo apt install wslu)
    USERPROFILE=$(wslpath "$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r')")
    # Cambio al directorio típico del usuario C:\Users\<usuario>
    cd $USERPROFILE
fi

# ----------------------------------------------------------------------------------------
# Mostrar mensajes bonitos
# ----------------------------------------------------------------------------------------

# Colores para los menasjes de estado
COLOR_GREEN=$(tput setaf 2)
COLOR_YELLOW=$(tput setaf 3)
COLOR_RED=$(tput setaf 1)

# Ancho de la terminal
width=$(tput cols)
message_len=0

# Función para imprimir un mensaje
echo_message() {
    local message=$1
    message_len=${#message}
    printf "%s " "$message"
}

# Función para imprimir un mensaje de estado (OK, WARNING, ERROR) alineado a la derecha
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
    created)
        status_msg="CREADA"
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
# Funciones de utilidad
# ----------------------------------------------------------------------------------------

# Esto se ejecuta cuando pulsan CTRL-C
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

# Comprobar si las dependencias necesarias están instaladas
check_installed_programs() {
    # PROGRAMAS que deben estar intalados
    if [ ${IS_WSL2} == true ]; then
        programs=("git" "jq" "wslpath" "git-credential-manager.exe")
    else
        if [ "$credential_gcm" == "true" ]; then
            programs=("git" "jq" "git-credential-manager")
        else
            programs=("git" "jq")
        fi
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
}

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

# GLOBAL
# Extraer configuración global del JSON
global_folder=$(jq -r '.global.folder' "$git_config_repos_json_file")
credential_ssh=$(jq -r '.global.credential_ssh.enabled' "$git_config_repos_json_file")
ssh_folder=$(jq -r '.global.credential_ssh.ssh_folder' "$git_config_repos_json_file")
credential_gcm=$(jq -r '.global.credential_gcm.enabled' "$git_config_repos_json_file")
credential_helper=$(jq -r '.global.credential_gcm.helper' "$git_config_repos_json_file")
credential_store=$(jq -r '.global.credential_gcm.credentialStore' "$git_config_repos_json_file")

#
# COMPROBAR PROGRAMAS INSTALADOS
#
check_installed_programs

# DIRECTORIO GLOBAL
# Crear el directorio global de Git
echo_message "Directorio Git: $global_folder"
mkdir -p "$global_folder" &>/dev/null
if [ $? -ne 0 ]; then
    echo_status error
    echo "ERROR: No se ha podido crear $global_folder."
    exit 1
fi
echo_status ok

# DIRECTORIO SSH
# Crear el directorio global de Git
if [ "$credential_ssh" == true ]; then
    echo_message "Directorio SSH: $ssh_folder"
    mkdir -p "$ssh_folder" &>/dev/null
    if [ $? -ne 0 ]; then
        echo_status error
        echo "ERROR: No se ha podido crear $ssh_folder."
        exit 1
    fi
    echo_status ok
fi

# CONFIGURACIÓN GLOBAL de GCM
# --
# Para HTTPS + Git Credential Manager
if [ "$credential_gcm" == "true" ]; then

    echo_message "Configuración de Git global"
    $git_command config --global --replace-all credential.helper "$credential_helper"
    $git_command config --global credential.credentialStore "$credential_store"
    accounts=$(jq -r '.accounts | keys[]' "$git_config_repos_json_file")
    for account in $accounts; do
        account_url=$(jq -r ".accounts[\"$account\"].url" "$git_config_repos_json_file")
        account_username=$(jq -r ".accounts[\"$account\"].username" "$git_config_repos_json_file")
        account_gcm_provider=$(jq -r ".accounts[\"$account\"].gcm_provider" "$git_config_repos_json_file")
        account_gcm_useHttpPath=$(jq -r ".accounts[\"$account\"].gcm_useHttpPath" "$git_config_repos_json_file")
        # Obtengo "gratis", la URL las credenciales desde account_url
        account_credential_url=$(echo "$account_url" | sed -E 's|(https://[^/]+).*|\1|')
        # Configurar las credenciales globales para la cuenta
        $git_command config --global credential."$account_credential_url".provider "$account_gcm_provider"
        $git_command config --global credential."$account_credential_url".useHttpPath "$account_gcm_useHttpPath"
    done
    echo_status ok

    # CREDENCIALES
    # Iterar sobre las cuentas para los CREDENCIALES de GCM
    # En esta seccion se configuran las credenciales en el almacen de credenciales, mediante
    # el proceso de ir a la URL de la cuenta y autenticarse con el navegador
    accounts=$(jq -r '.accounts | keys[]' "$git_config_repos_json_file")
    for account in $accounts; do
        account_url=$(jq -r ".accounts[\"$account\"].url" "$git_config_repos_json_file")
        account_username=$(jq -r ".accounts[\"$account\"].username" "$git_config_repos_json_file")
        # Obtengo "gratis", la URL las credenciales desde account_url
        account_credential_url=$(echo "$account_url" | sed -E 's|(https://[^/]+).*|\1|')

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
fi

# CONFIGURACIÓN GLOBAL de SSH
# --
# Para SSH configuro las Keys
if [ "$credential_ssh" == true ]; then

    ssh_config_file="$ssh_folder/config"
    git_config_comment="# Configuración para git-config-repos.sh"
    git_include_line="Include $ssh_folder/git-config-repos"
    ssh_config_file_git_config_repos="$ssh_folder/git-config-repos"

    # Comprueba si las líneas ya existen
    echo_message "Configuración Hosts SSH en $ssh_config_file"
    if ! grep -qF "$git_config_comment" "$ssh_config_file" && ! grep -qF "$git_include_line" "$ssh_config_file"; then
        # Añade las líneas al principio del archivo
        {
            cat "$ssh_config_file"
            echo ""
            echo "$git_config_comment"
            echo "$git_include_line"
            echo ""
        } > "$ssh_config_file.tmp" && mv "$ssh_config_file.tmp" "$ssh_config_file"
        echo_status created
    else
        echo_status ok
    fi

    # Verificar y/o crear las KEYS por cuenta, añañdir al ssh-agent y configurar el archivo de configuración
    # de SSH para que use las claves SSH correctas
    echo "# Configuración para git-config-repos.sh" > "$ssh_config_file_git_config_repos"
    accounts=$(jq -r '.accounts | keys[]' "$git_config_repos_json_file")
    for account in $accounts; do
        echo_message "Claves SSH para $account"

        # Extraer los valores de la cuenta desde el archivo JSON
        ssh_host=$(jq -r ".accounts[\"$account\"].ssh_host" "$git_config_repos_json_file")
        if [ "$ssh_host" == "" ] || [ "$ssh_host" == "null" ]; then
            echo "Error: La cuenta $account no tiene definida el prefijo del nombre de clave SSH (ssh_host)."
            echo_status error
            exit 1
        fi
        ssh_hostname=$(jq -r ".accounts[\"$account\"].ssh_hostname" "$git_config_repos_json_file")
        if [ "$ssh_hostname" == "" ] || [ "$ssh_hostname" == "null" ]; then
            echo "Error: La cuenta $account no tiene definida el Hostname SSH (ssh_hostname)."
            echo_status error
            exit 1
        fi
        account_ssh_type=$(jq -r ".accounts[\"$account\"].ssh_type" "$git_config_repos_json_file")
        if [ "$account_ssh_type" == "" ] || [ "$account_ssh_type" == "null" ]; then
            echo_status error
            echo "Error: La cuenta $account no tiene definido el tipo de clave SSH (ssh_type)."
            exit 1
        fi
        account_ssh_key="$ssh_folder/$ssh_host-sshkey"

        # Comprobar si la clave SSH existe, si no, crearla
        if [ ! -f "$account_ssh_key" ] || [ ! -f "$account_ssh_key.pub" ]; then
            # Intentar generar la clave SSH y capturar errores
            account_url=$(jq -r ".accounts[\"$account\"].url" "$git_config_repos_json_file")
            account_username=$(jq -r ".accounts[\"$account\"].username" "$git_config_repos_json_file")
            account_ssh_comment="$(whoami)@$(hostname) $account_username $account_url"
            if $(echo "y" | ssh-keygen -q -t "$account_ssh_type" -f "$account_ssh_key" -C "$account_ssh_comment" -N "" &>/dev/null); then
                echo_status created
            else
                echo_status error
                echo "Error creando la clave SSH para $account" >&2
                exit 1
            fi
        else
            echo_status ok
        fi

        # Añadir el host al fichero de configuración SSH git-config-repos, ejemplo
        echo_message "Configuración Host SSH para $account"
        echo "Host $ssh_host" >>"$ssh_config_file_git_config_repos"
        echo "    HostName $ssh_hostname" >>"$ssh_config_file_git_config_repos"
        echo "    User git" >>"$ssh_config_file_git_config_repos"
        echo "    IdentityFile $account_ssh_key" >>"$ssh_config_file_git_config_repos"
        echo "    IdentitiesOnly yes" >>"$ssh_config_file_git_config_repos"
        echo_status ok
    done

    # Añadirlas al ssh-agent
    ssh-add -D &>/dev/null
    for account in $accounts; do
        ssh_host=$(jq -r ".accounts[\"$account\"].ssh_host" "$git_config_repos_json_file")
        account_ssh_key="$ssh_folder/$ssh_key-sshkey"
        echo_message "Añadiendo clave SSH a ssh-agent para $account"
        ssh-add "$account_ssh_key" &>/dev/null
        echo_status ok
    done
fi

# REPOSITORIOS
# Iterar sobre las cuentas para los REPOSITORIOS
# En esta sección se clonan los repositorios y se configuran los repositorios locales
accounts=$(jq -r '.accounts | keys[]' "$git_config_repos_json_file")
for account in $accounts; do

    # Extraer los valores de la cuenta desde el archivo JSON
    account_url=$(jq -r ".accounts[\"$account\"].url" "$git_config_repos_json_file")
    account_username=$(jq -r ".accounts[\"$account\"].username" "$git_config_repos_json_file")
    account_folder=$(jq -r ".accounts[\"$account\"].folder" "$git_config_repos_json_file")
    account_user_name=$(jq -r ".accounts[\"$account\"].name" "$git_config_repos_json_file")
    account_user_email=$(jq -r ".accounts[\"$account\"].email" "$git_config_repos_json_file")

    # Preparo variables si la cuenta tiene credenciales vía SSH
    if [ "$credential_ssh" == true ]; then
        ssh_host=$(jq -r ".accounts[\"$account\"].ssh_host" "$git_config_repos_json_file")
        account_ssh_type=$(jq -r ".accounts[\"$account\"].ssh_type" "$git_config_repos_json_file")
        account_ssh_key="$ssh_folder/$ssh_host-sshkey"
        # Extraigo el nombre de la cuenta de la URL, por ejemplo, para
        # una url del tipo https://github.com/usuario, extraigo "usuario"
        git_account_user=$(echo "$account_url" | sed -E 's|.*/([^/]+)$|\1|')
        # Reconstruyo la URL de clonación usando el ssh_host y el usuario
        account_clone_url="$ssh_host:$git_account_user"
        remote_origin_url=$account_clone_url
    elif [ "$credential_gcm" == true ]; then
        # Preparo variables si la cuenta tiene credenciales vía GCM
        # Obtengo valores "gratis", la URL de clonación y la de las credenciales
        account_clone_url=$(echo "$account_url" | sed -E "s|https://(.*)|https://$account_username@\1|")
        account_credential_url=$(echo "$account_url" | sed -E 's|(https://[^/]+).*|\1|')
        remote_origin_url=$account_url
    fi

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

        # Si tengo nombre y email del usuario a nivel de repositorio, los pillo
        repo_name=$(jq -r ".accounts[\"$account\"].repos[\"$repo\"].name" "$git_config_repos_json_file")
        if [ "$repo_name" != "" ] && [ "$repo_name" != "null" ]; then
            account_user_name=$repo_name
        fi
        repo_email=$(jq -r ".accounts[\"$account\"].repos[\"$repo\"].email" "$git_config_repos_json_file")
        if [ "$repo_email" != "" ] && [ "$repo_email" != "null" ]; then
            account_user_email=$repo_email
        fi


        # Averiguo el tipo de credencial para el repositorio
        repo_credential_type=$(jq -r ".accounts[\"$account\"].repos[\"$repo\"].credential_type" "$git_config_repos_json_file")

        # Construyo la ruta del repositorio
        # Compruebo si este repo tiene la clave "folder" a su nivel, eso puede significar
        # que el usuario quiere que se clone sobre un nombre de folder distinto al
        # nombre del repositorio.
        repo_folder=$(jq -r ".accounts[\"$account\"].repos[\"$repo\"].folder" "$git_config_repos_json_file")
        if [ "$repo_folder" != "" ] && [ "$repo_folder" != "null" ]; then
            # Si $repo_folder empieza por /, es una ruta absoluta, por lo que la pongo
            # como tal, si no, la pongo como relativa al directorio de la cuenta
            if [ "${repo_folder:0:1}" == "/" ]; then
                repo_path="$repo_folder"
            else
                repo_path="$global_folder/$account_folder/$repo_folder"
            fi
        else
            repo_path="$global_folder/$account_folder/$repo"
        fi

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

        # Configurar el repositorio local (.git/config)
        cd "$repo_path" || continue
        $git_command remote set-url origin "$remote_origin_url/$repo.git"
        $git_command remote set-url --push origin "$remote_origin_url/$repo.git"
        if [ "$account_user_name" != "" ] && [ "$account_user_name" != "null" ]; then
            $git_command config user.name "$account_user_name"
        fi
        if [ "$account_user_email" != "" ] && [ "$account_user_email" != "null" ]; then
            $git_command config user.email "$account_user_email"
        fi
        if  [ "$credential_gcm" == true ]; then
            $git_command config credential."$account_credential_url".username "$account_username"
        fi

    done
done

# ----------------------------------------------------------------------------------------
