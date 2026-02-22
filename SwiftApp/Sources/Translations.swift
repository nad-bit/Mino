import Foundation

enum Translations {
    static let i18n: [String: [String: String]] = [
        "en": [
            "configureToken": "Configure Token...", "enterTokenMsg": "Enter your GitHub personal access token:",
            "changeInterval": "Change Update Interval...", "enterIntervalMsg": "Select interval (1-24 hours):",
            "addRepoManual": "Add Repository Manually...", "addRepoBrew": "Add from Homebrew...",
            "selectCaskPlaceholder": "--- Select a Cask ---",
            "enterRepoMsg": "Enter repository (owner/name):",
            "deleteRepo": "Delete Repository", "openReleases": "Open Releases Page", "releaseNotes": "Release Notes",
            "installUpdate": "Install via Homebrew", "installingTitle": "Homebrew Installation",
            "installingMsg": "Installing {cask_name}",
            "installComplete": "'{cask_name}' has been installed/updated successfully.",
            "installFailed": "Failed to install '{cask_name}'.",
            "alreadyInstalled": "'{cask_name}' is already up to date.",
            "days": "days", "about": "About GitHub Watcher", "aboutMsg": "nad\nVersion 0.8.3 (167)",
            "preferences": "Preferences", "ok": "OK", "cancel": "Cancel", "quit": "Quit",
            "refreshNow": "Refresh Repositories", "refreshing": "Refreshing...",
            "nextRefresh": "Next auto-refresh in", "minutes": "min", "hours": "hours",
            "startAtLogin": "Start at Login",
            "addFromBrew": "Select a Homebrew Cask:", "loadingBrew": "Loading Homebrew Casks...",
            "noRepos": "No repositories added", "confirmDelete": "Are you sure you want to delete this repository?",
            "repoNotFound": "Repository not found", "repoExists": "This repository is already in the list.",
            "invalidRepoFormat": "Invalid format. Must be: owner/name",
            "loading": "Loading...", "error": "Error", "noNotes": "No release notes provided.",
            "brewErrorTitle": "Homebrew Error",
            "brewRepoNotFound": "Could not find a GitHub repository for '{app_name}'.",
            "brewIntegration": "Homebrew Integration",
            "sortLabel": "Sort by", "sortNameOnly": "Name", "sortDateOnly": "Date",
            "intervalDynamic": "Update interval: {hours} {unit}",
            "sortByName": "Sort by Name",
            "sortByDate": "Sort by Date",
            "showOwner": "Show Owner Name",
            "hideOwner": "Hide Owner Name",
            "showIcons": "Show Icons",
            "tokenValidationSuccess": "Token saved. Rate limit increased to 5000/hr.",
            "tokenValidationError": "Invalid token. Please check your GitHub Personal Access Token.",
            "tokenValidationEmpty": "Token cleared. Reverting to unauthenticated rate limit (60/hr).",
            "unitMin": "min", "unitHour": "hr", "unitDay": "day", "unitHoursPlural": "hrs",
            "currentToken": "Current token", "tokenPlaceholder": "Paste new token here...", "deleteToken": "Delete Token", "showToken": "Show Token",
        ],
        "es": [
            "configureToken": "Configurar Token...", "enterTokenMsg": "Introduce tu token personal de GitHub:",
            "changeInterval": "Cambiar intervalo...", "enterIntervalMsg": "Selecciona intervalo (1-24 horas):",
            "addRepoManual": "Añadir repositorio manualmente...", "addRepoBrew": "Añadir desde Homebrew...",
            "selectCaskPlaceholder": "--- Selecciona un Cask ---",
            "enterRepoMsg": "Introduce el repositorio (owner/nombre):",
            "deleteRepo": "Eliminar Repositorio", "openReleases": "Abrir página de lanzamientos", "releaseNotes": "Notas de la versión",
            "installUpdate": "Instalar via Homebrew", "installingTitle": "Instalación de Homebrew",
            "installingMsg": "Instalando {cask_name}",
            "installComplete": "'{cask_name}' se ha instalado/actualizado correctamente.",
            "installFailed": "Falló la instalación de '{cask_name}'.",
            "alreadyInstalled": "'{cask_name}' ya está actualizado.",
            "days": "días", "about": "Acerca de GitHub Watcher", "aboutMsg": "nad\nVersión 0.8.3 (167)",
            "preferences": "Preferencias", "ok": "Aceptar", "cancel": "Cancelar", "quit": "Salir",
            "refreshNow": "Actualizar repositorios", "refreshing": "Actualizando...",
            "nextRefresh": "Próxima act. automática en", "minutes": "min", "hours": "horas",
            "startAtLogin": "Arrancar al inicio",
            "addFromBrew": "Selecciona un Cask de Homebrew:", "loadingBrew": "Cargando Casks...",
            "noRepos": "No hay repositorios añadidos", "confirmDelete": "¿Seguro que quieres eliminar este repositorio?",
            "repoNotFound": "Repositorio no encontrado", "repoExists": "Este repositorio ya está en la lista.",
            "invalidRepoFormat": "Formato inválido. Debe ser: owner/nombre",
            "loading": "Cargando...", "error": "Error", "noNotes": "No hay notas de la versión.",
            "brewErrorTitle": "Error de Homebrew",
            "brewRepoNotFound": "No se pudo encontrar un repositorio de GitHub para '{app_name}'.",
            "brewIntegration": "Integración con Homebrew",
            "sortLabel": "Ordenar por", "sortNameOnly": "Nombre", "sortDateOnly": "Fecha",
            "intervalDynamic": "Intervalo de actualización: {hours} {unit}",
            "sortByName": "Ordenar por Nombre",
            "sortByDate": "Ordenar por Fecha",
            "showOwner": "Mostrar propietario",
            "hideOwner": "Ocultar propietario",
            "showIcons": "Mostrar iconos",
            "tokenValidationSuccess": "Token guardado. Límite aumentado a 5000/hr.",
            "tokenValidationError": "Token inválido. Por favor revisa tu Token Personal de GitHub.",
            "tokenValidationEmpty": "Token eliminado. Volviendo al límite no autenticado (60/h).",
            "unitMin": "min", "unitHour": "hora", "unitDay": "día", "unitHoursPlural": "horas",
            "currentToken": "Token actual", "tokenPlaceholder": "Pega el nuevo token aquí...", "deleteToken": "Borrar Token", "showToken": "Mostrar Token",
            "addRepoUnified": "Añadir Repositorio", "addRepoUnifiedMsg": "Elige cómo añadir el repositorio:",
            "manualOption": "Entrada Manual", "brewOption": "Desde Homebrew"
        ]
    ]
    
    static var currentLanguage: String {
        if #available(macOS 13, *) {
            let langCode = Locale.current.language.languageCode?.identifier ?? "en"
            return i18n.keys.contains(langCode) ? langCode : "en"
        } else {
            let langCode = Locale.current.languageCode ?? "en"
            return i18n.keys.contains(langCode) ? langCode : "en"
        }
    }
    
    static func get(_ key: String) -> String {
        let lang = currentLanguage
        if let translated = i18n[lang]?[key] {
            return translated
        }
        return i18n["en"]?[key] ?? key
    }
}

// Extension for String substitution
extension String {
    func format(with arguments: [String: String]) -> String {
        var str = self
        for (key, value) in arguments {
            str = str.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return str
    }
}
