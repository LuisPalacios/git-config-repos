# Configurador de repositorios Git

Este script simplifica la configuración de Git multicuenta si utilizas HTTPS y Git Credential Manager como método de gestión de credenciales.

Lee y analiza el archivo `git-config-repos.json`, de donde obtiene parámetros globales de GIT y parámetros específicos para varias cuentas y repositorios.

Para cada uno de los repositorios:

- Verifica los credenciales y los guarda en el almacén local
- Clona el repo bajo el directorio de la cuenta y lo configura
- Si ya existía el repo, revisa la configuración y arregla lo que no esté correcto

El fichero JSON tiene dos claves principales: "global" y "accounts".

- La clave "global" indica cuál es el directorio raíz GIT donde el usuario despliega toda la estructura de directorios y algunos parámetros que servirán para configurar el fichero global (`$HOME/.gitconfig`)
- La clave "accounts" incluye claves para diferentes cuentas en distintos proveedores Git y dentro de dichas cuentas incluye a su vez repositorios.

Este script se apoya en Git Credential Manager. Está probado en Linux, MacOS y Windows

