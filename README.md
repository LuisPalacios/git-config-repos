# Configurador de repositorios Git

El script `git-config-repos.sh` simplifica la configuración de Git para de una estación de trabajo de un desarrollador que utiliza HTTPS y Git Credential Manager como método de gestión de sus credenciales.

Lee y analiza el archivo `git-config-repos.json` de donde obtiene parámetros globales de GIT y parámetros específicos para varias cuentas y repositorios.

Para cada uno de los repositorios ofrece:

- Si no existe el repo lo clona bajo el directorio de la cuenta y lo configura
- Si existe el repo, revisa la configuración y arregla lo que no esté correcto

El fichero JSON tiene dos claves principales: "global" y "accounts".

- La clave "global" indica cuál es el directorio raíz GIT donde el usuario despliega toda la estructura de directorios y algunos parámetros que servirán para configurar el fichero de git (`$HOME/.gitconfig`)
- La clave "accounts" incluye a su vez claves para diferentes cuentas en distintos proveedores Git y dentro de dichas cuentas incluye a su vez repositorios.

Este script se apoya en Git Credential Manager. Está probado solo en MacOS.
