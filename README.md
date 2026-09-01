# AI Engineering Workflow

Repositorio distribuible para instalar un workflow de ingeniería asistida por IA en proyectos existentes o crear proyectos nuevos con la configuración incluida.

Este repositorio no es una aplicación y no debe ejecutar `/ai-bootstrap` sobre sí mismo. La configuración consumible vive en `template/` y sólo se activa después de copiarla a un repositorio de destino.

## Capacidades

- Instalar el workflow en un proyecto existente sin sobrescribir conflictos.
- Crear un proyecto nuevo desde un preset extensible.
- Actualizar una instalación conservando archivos personalizados.
- Analizar tickets de Azure DevOps, specs o requisitos escritos.
- Exigir aprobación humana antes de modificar código.
- Ejecutar quality gates determinísticos, review read-only y pruebas.
- Preparar explicación y descripción de PR sin commit, push, merge ni deploy automáticos.

## Estructura

```text
template/                    Payload que recibe cada proyecto
presets/projects/            Generadores de proyectos nuevos
presets/stacks/              Perfiles de contexto por tecnología
presets/architectures/       Arquitecturas seleccionables
scripts/install.ps1          Instalación en un proyecto existente
scripts/new-project.ps1      Creación de un proyecto nuevo
scripts/update.ps1           Actualización segura del payload
scripts/validate.ps1         Validación determinística de esta distribución
workflow.manifest.json       Manifiesto de distribución
VERSION                      Versión del workflow
```

## Instalar en un proyecto existente

Primero se puede inspeccionar el plan sin escribir:

```powershell
.\scripts\install.ps1 `
  -TargetPath "C:\ruta\al\proyecto" `
  -DryRun
```

Después, instalar:

```powershell
.\scripts\install.ps1 -TargetPath "C:\ruta\al\proyecto"
```

La instalación se cancela antes de copiar si encuentra cualquier archivo de destino existente. Los hashes iniciales quedan registrados en `.ai/workflow-installation.json` para permitir actualizaciones seguras.

## Crear un proyecto nuevo

Listar presets:

```powershell
.\scripts\new-project.ps1 -ListPresets
```

Ejemplo sin dependencias externas:

```powershell
.\scripts\new-project.ps1 `
  -Name "mi-servicio" `
  -ParentPath "C:\Repositorios" `
  -Preset "node-basic" `
  -Architecture "vertical-slice" `
  -InitializeGit
```

Presets iniciales:

- `empty`: sólo crea el repositorio y agrega el workflow.
- `node-basic`: Node.js sin dependencias, con tests nativos.
- `python-basic`: paquete Python mínimo con `unittest`.
- `dotnet-webapi`: usa el template oficial `dotnet new webapi`.
- `react-vite`: usa el generador oficial de Vite; requiere red.

Los presets son datos bajo `presets/projects/`; se pueden agregar nuevos sin modificar el motor de creación.

## Actualizar un proyecto instalado

```powershell
.\scripts\update.ps1 -TargetPath "C:\ruta\al\proyecto" -DryRun
.\scripts\update.ps1 -TargetPath "C:\ruta\al\proyecto"
```

`update.ps1` sólo reemplaza archivos que conservan el hash de la instalación anterior. Si un archivo fue personalizado, aborta toda la actualización y muestra el conflicto. Los archivos retirados del template se informan, pero no se eliminan automáticamente.

## Usar el workflow en el proyecto destino

```powershell
cd "C:\ruta\al\proyecto"
opencode2
```

Dentro de OpenCode:

```text
/ai-bootstrap
```

Bootstrap inspecciona el proyecto real, propone `.ai/project.json` y espera aprobación explícita. Después quedan disponibles `/ticket`, `/implement`, `/review`, `/test`, `/explain` y `/pr`.

## Validar esta distribución

```powershell
.\scripts\validate.ps1
```

No se fijan modelos en la versión base. La selección de modelos debe realizarse después de validar el workflow contra proyectos reales.

La versión V2 actual carga `AGENTS.md` como instrucción persistente, mientras que el campo `instructions` de `opencode.json` todavía no resuelve archivos adicionales. Por eso `AGENTS.md` exige cargar `project-context`, y ese skill lee `.ai/project-rules.md` explícitamente antes de trabajar.
