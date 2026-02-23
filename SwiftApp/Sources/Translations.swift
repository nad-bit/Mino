import Foundation

enum Translations {
    static let i18n: [String: [String: String]] = [
        "en": [
            "configureToken": "Configure Token...", "enterTokenMsg": "Enter your GitHub personal access token:",
            "changeInterval": "Change Update Interval...", "enterIntervalMsg": "Select interval (1-24 hours):",
            "selectCaskPlaceholder": "--- Select a Cask ---",
            "enterRepoMsg": "Enter repository (owner/name):",
            "deleteRepo": "Delete Repository", "openReleases": "Open Releases Page", "releaseNotes": "Release Notes",
            "installUpdate": "Install via Homebrew", "installingTitle": "Homebrew Installation",
            "installingMsg": "Installing {cask_name}",
            "installComplete": "'{cask_name}' has been installed/updated successfully.",
            "installFailed": "Failed to install '{cask_name}'.",
            "alreadyInstalled": "'{cask_name}' is already up to date.",
            "days": "days", "aboutMsg": "nad\nVersion 0.9.2 (171)",
            "preferences": "Preferences", "ok": "OK", "cancel": "Cancel", "quit": "Quit",
            "refreshNow": "Refresh Repositories", "refreshing": "Refreshing...",
            "minutes": "min", "hours": "hours",
            "startAtLogin": "Start at Login",
            "addFromBrew": "Select a Homebrew Cask:", "loadingBrew": "Loading Homebrew Casks...",
            "noRepos": "No repositories added", "confirmDelete": "Are you sure you want to delete this repository?",
            "confirmDeleteToken": "Are you sure you want to delete the stored token?",
            "repoNotFound": "Repository not found", "repoExists": "This repository is already in the list.",
            "loading": "Loading...", "error": "Error", "noNotes": "No release notes provided.",
            "brewErrorTitle": "Homebrew Error",
            "brewRepoNotFound": "Could not find a GitHub repository for '{app_name}'.",
            "sortLabel": "Sort by", "sortNameOnly": "Name", "sortDateOnly": "Date",
            "intervalDynamic": "Update interval: {hours} {unit}",
            "showOwner": "Show Owner Name",
            "showIcons": "Show Icons",
            "showNewIndicator": "Show New Release Indicator (✦)",
            "indicatorDays": "Show indicator for releases within {days} {unit}",
            "tokenValidationSuccess": "Token saved. Rate limit increased to 5000/hr.",
            "tokenValidationError": "Invalid token. Please check your GitHub Personal Access Token.",
            "tokenValidationEmpty": "Token cleared. Reverting to unauthenticated rate limit (60/hr).",
            "unitMin": "min", "unitHour": "hr", "unitDay": "day", "unitHoursPlural": "hrs",
            "currentToken": "Current token", "tokenPlaceholder": "Paste new token here...", "deleteToken": "Delete Token",
        ],
        "es": [
            "configureToken": "Configurar Token...", "enterTokenMsg": "Introduce tu token personal de GitHub:",
            "changeInterval": "Cambiar intervalo...", "enterIntervalMsg": "Selecciona intervalo (1-24 horas):",
            "selectCaskPlaceholder": "--- Selecciona un Cask ---",
            "enterRepoMsg": "Introduce el repositorio (owner/nombre):",
            "deleteRepo": "Eliminar Repositorio", "openReleases": "Abrir página de lanzamientos", "releaseNotes": "Notas de la versión",
            "installUpdate": "Instalar via Homebrew", "installingTitle": "Instalación de Homebrew",
            "installingMsg": "Instalando {cask_name}",
            "installComplete": "'{cask_name}' se ha instalado/actualizado correctamente.",
            "installFailed": "Falló la instalación de '{cask_name}'.",
            "alreadyInstalled": "'{cask_name}' ya está actualizado.",
            "days": "días", "aboutMsg": "nad\nVersión 0.9.2 (171)",
            "preferences": "Preferencias", "ok": "Aceptar", "cancel": "Cancelar", "quit": "Salir",
            "refreshNow": "Actualizar repositorios", "refreshing": "Actualizando...",
            "minutes": "min", "hours": "horas",
            "startAtLogin": "Arrancar al inicio",
            "addFromBrew": "Selecciona un Cask de Homebrew:", "loadingBrew": "Cargando Casks...",
            "noRepos": "No hay repositorios añadidos", "confirmDelete": "¿Seguro que quieres eliminar este repositorio?",
            "confirmDeleteToken": "¿Seguro que quieres eliminar el token almacenado?",
            "repoNotFound": "Repositorio no encontrado", "repoExists": "Este repositorio ya está en la lista.",
            "loading": "Cargando...", "error": "Error", "noNotes": "No hay notas de la versión.",
            "brewErrorTitle": "Error de Homebrew",
            "brewRepoNotFound": "No se pudo encontrar un repositorio de GitHub para '{app_name}'.",
            "sortLabel": "Ordenar por", "sortNameOnly": "Nombre", "sortDateOnly": "Fecha",
            "intervalDynamic": "Intervalo de actualización: {hours} {unit}",
            "showOwner": "Mostrar propietario",
            "showIcons": "Mostrar iconos",
            "showNewIndicator": "Mostrar indicador de novedad (✦)",
            "indicatorDays": "Indicar novedades de los últimos {days} {unit}",
            "tokenValidationSuccess": "Token guardado. Límite aumentado a 5000/hr.",
            "tokenValidationError": "Token inválido. Por favor revisa tu Token Personal de GitHub.",
            "tokenValidationEmpty": "Token eliminado. Volviendo al límite no autenticado (60/h).",
            "unitMin": "min", "unitHour": "hora", "unitDay": "día", "unitHoursPlural": "horas",
            "currentToken": "Token actual", "tokenPlaceholder": "Pega el nuevo token aquí...", "deleteToken": "Borrar Token",
            "addRepoUnified": "Añadir Repositorio",
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
