# Herramientas para repositorios Git

Scripts de apoyo para trabajar con Git en entorno de múltiples cuentas con uno o más proveedores Git (GitHub, GitLab, Gitea).

Soportan las dos opciones de autenticación: 1) HTTPS + Git Credential Manager y 2) SSH multicuenta. La primera, HTTPS + Git Credential Manager, es la que suelo usar cuando trabajo en un Desktop con UI porque es compatible con el CLI y/o herramientas GUI tipo Visual Studio, VSCode, Git Desktop, Gitkraken, etc. La segunda opción, SSH multicuenta, la suelo usar en equipos linux “headless”, servidores a los que conecto en remoto vía (CLI o VSCode remote) y necesito que clonen repositorios y trabajen sobre ellos.

Tengo un apunte donde describo como trabajar en entornos [Git Multicuenta](https://www.luispa.com/desarrollo/2024/09/21/git-multicuenta.html).

## `git-config-repos.sh`

Simplifica la configuración de Git multicuenta. Lee y analiza el archivo `~/.config/git-config-repos.json`, de donde obtiene parámetros globales de GIT y parámetros específicos para el tipo de credenciales, cuentas y repositorios.

Para cada uno de los repositorios:

- Verifica los credenciales y los guarda en el almacén local
- Clona el repo bajo el directorio de la cuenta y lo configura
- Si ya existía el repo, revisa la configuración y arregla lo que no esté correcto

El fichero JSON tiene dos claves principales: "global" y "accounts".

- La clave "global" indica cuál es el directorio raíz GIT donde el usuario despliega toda la estructura de directorios y algunos parámetros que servirán para configurar el fichero global `~/.gitconfig` y en el caso de SSH el fichero `~/.ssh/config`
- La clave "accounts" incluye claves para diferentes cuentas en distintos proveedores Git y dentro de dichas cuentas incluye a su vez repositorios.

Este script se apoya en Git Credential Manager y/o SSH Multicuenta. Está probado en Linux, MacOS y Windows con WSL2

## `git-status-pull.sh`

Este script verifica el estado de múltiples repositorios Git a partir del directorio actual (desde donde lo ejecutes). Su objetivo es informar al usuario sobre qué repositorios necesitan un pull para estar sincronizados con su upstream.

Si se proporciona el argumento Pull, el script puede hacer pull automáticamente. Además es capaz de proporcionar información detallada sobre cada repositorio, cuando no se puede hacer pull automáticamente, informando de la razón por la que el repositorio no está limpio y necesita ser revisado. Soporta el modo verbose (-v) para dar dicha informacion más detallada
