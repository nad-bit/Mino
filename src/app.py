import rumps
import requests
import json
from pathlib import Path
import webbrowser
import subprocess
import threading
import time
import math
import re
import concurrent.futures
import logging
import sys
from typing import Optional, Dict, Any, List, Tuple
from AppKit import (
    NSAlert, NSScrollView, NSTextView, NSMakeRect, NSTextField, 
    NSView, NSPopUpButton, NSApp, NSSize, NSSlider, NSButton
)

from .translations import i18n
from .utils import (
    get_macos_language, 
    safe_dispatch_to_main_thread, 
    get_release_age,
    save_token_to_keychain,
    get_token_from_keychain,
    delete_token_from_keychain
)
from .handlers import SliderHandler, AddRepoHandler
from . import constants as const

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

lang = get_macos_language()
t = i18n.get(lang, i18n["en"])

# ------------------------------------------------------------
# 🧠 Clase Principal de la Aplicación
# ------------------------------------------------------------
class GitHubWatcherApp(rumps.App):
    """
    Main application class for GitHub Watcher.
    
    Manages the menu bar interface, background fetching of repository data,
    and configuration persistence.
    """
    
    DEFAULT_REPOS = [
        {"name": "exelban/stats", "source": "brew", "cask": "stats"},
        {"name": "p0deje/Maccy","source": "brew", "cask": "maccy"},
        {"name": "utmapp/UTM", "source": "brew", "cask": "utm"},
        {"name": "objective-see/LuLu", "source": "brew", "cask": "lulu"},
        {"name": "alienator88/Pearcleaner", "source": "brew", "cask": "pearcleaner"},
        {"name": "alienator88/Sentinel", "source": "brew", "cask": "alienator88-sentinel"},
        {"name": "upscayl/upscayl", "source": "brew", "cask": "upscayl"},
        {"name": "jorio/BillyFrontier", "source": "brew", "cask": "billy-frontier"},
        {"name": "Marginal/QLVideo", "source": "brew", "cask": "qlvideo"},
        {"name": "paulpacifico/shutter-encoder", "source": "brew", "cask": "shutter-encoder"},
        {"name": "xbmc/xbmc", "source": "brew", "cask": "kodi"},
        {"name": "ONLYOFFICE/DesktopEditors", "source": "brew", "cask": "onlyoffice"},
        {"name": "HandBrake/HandBrake","source": "brew", "cask": "handbrake-app"},
    ]
    
    def __init__(self):
        # quit_button=None desactiva el elemento "Quit" por defecto de rumps
        # Nosotros agregamos nuestro propio botón traducido en build_menu()
        super(GitHubWatcherApp, self).__init__("", icon="icon.icns", quit_button=None)
        
        # Limpiar el menú por defecto de rumps para evitar elementos duplicados
        self.menu.clear()
        
        self.config_path = Path.home() / ".config" / "GitHubWatcher"
        self.repos_config_path = self.config_path / "repos.json"
        
        self.repo_cache = {}
        self.config = {
            "repos": [], 
            "token": None, 
            "refresh_minutes": const.DEFAULT_REFRESH_INTERVAL_MINUTES,
            "sort_by": "date", # "name" or "date"
            "show_owner": False # True: owner/repo, False: solo repo
        }
        
        self.refresh_lock = threading.Lock()
        self.last_refresh_time = time.time()
        
        # === FLAG PARA EVITAR RECONSTRUCCIONES SIMULTÁNEAS DEL MENÚ ===
        self.menu_building = False
        # === FIN FLAG ===
        
        # === OPTIMIZACIÓN: Regex precompilado para mejor rendimiento ===
        # Formato: "repo (version) · time" con indicador 🟢 opcional
        self.repo_label_regex = re.compile(r'(.+?) \((.+?)\) · (.+?)( 🟢)?$')
        # === FIN OPTIMIZACIÓN ===
        
        # === OPTIMIZACIÓN: Thread Pool y Session ===
        self.executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=const.THREAD_POOL_MAX_WORKERS,
            thread_name_prefix="GitHubWatcherWorker"
        )
        self.session = requests.Session()
        self.session.headers.update({"User-Agent": const.USER_AGENT})
        
        # Configurar adaptadores para retries
        adapter = requests.adapters.HTTPAdapter(max_retries=const.HTTP_MAX_RETRIES)
        self.session.mount("https://", adapter)
        self.session.mount("http://", adapter)
        # === FIN OPTIMIZACIÓN ===
        
        # === OPTIMIZACIÓN: Batch processing de actualizaciones del menú ===
        self._pending_menu_updates = []
        self._menu_update_timer = None
        self._menu_update_delay = const.MENU_UPDATE_BATCH_DELAY_SECONDS
        # === FIN OPTIMIZACIÓN ===
        
        self.launch_agent_label = const.LAUNCH_AGENT_LABEL
        self.launch_agent_path = Path.home() / "Library" / "LaunchAgents" / f"{self.launch_agent_label}.plist"
        
        self.brew_path = self._find_brew_path()

        self._mi_refresh = None
        self._mi_add_manual = None
        self._mi_sort_toggle = None
        self._mi_owner_toggle = None
        
        self.load_config()
        
        # El único timer es el de 60s para el contador y el chequeo de refresh.
        self.countdown_timer = rumps.Timer(
            self.update_countdown,
            const.COUNTDOWN_TIMER_INTERVAL_SECONDS
        )
        
        self.countdown_timer.start()
        
        self.trigger_full_refresh(None)

    def _find_brew_path(self) -> Optional[str]:
        """Locates the Homebrew executable in standard paths."""
        for path in const.HOMEBREW_PATHS:
            if Path(path).exists(): return path
        return None

    def load_config(self) -> None:
        """Loads configuration from JSON file or initializes defaults."""
        config_loaded = False
        if self.repos_config_path.exists():
            with open(self.repos_config_path, "r") as f:
                try:
                    loaded_config = json.load(f)
                    migrated = False
                    new_repos = []
                    for repo in loaded_config.get("repos", []):
                        if isinstance(repo, str):
                            new_repos.append({"name": repo, "source": "manual"})
                            migrated = True
                        else:
                            new_repos.append(repo)
                    loaded_config["repos"] = new_repos
                    self.config.update(loaded_config)
                    if migrated: self.save_config()
                    config_loaded = True
                except json.JSONDecodeError:
                    logging.warning("Could not decode config file, using defaults")
        
        # --- MIGRACIÓN DE TOKEN A KEYCHAIN ---
        # Si el token está en JSON, migrarlo al Keychain y eliminarlo del JSON
        json_token = self.config.get("token")
        if json_token:
            logging.info("Migrating token from JSON to Keychain...")
            if save_token_to_keychain(json_token):
                # Después de guardar exitosamente, eliminar del config y guardar
                self.config["token"] = None
                self.save_config()
                logging.info("Token migrated successfully to Keychain")
            else:
                logging.warning("Failed to migrate token to Keychain, keeping in JSON")
        
        # Cargar token desde Keychain (después de posible migración)
        self.token = get_token_from_keychain()
        # --- FIN MIGRACIÓN DE TOKEN ---
        
        # --- LÓGICA DE INICIALIZACIÓN CON EJEMPLOS ---
        if not config_loaded or not self.config["repos"]:
            if not self.repos_config_path.exists():
                self.config["repos"] = self.DEFAULT_REPOS
                self.save_config() # Guardar la configuración por defecto
        # --- FIN LÓGICA DE EJEMPLOS ---
        
        self.build_menu()

    def save_config(self) -> None:
        """Persists current configuration to disk."""
        try:
            self.config_path.mkdir(parents=True, exist_ok=True)
            # Token nunca debe guardarse en JSON, siempre se guarda en Keychain
            config_to_save = self.config.copy()
            config_to_save["token"] = None  # Asegurar que token siempre sea None en JSON
            
            with open(self.repos_config_path, "w") as f:
                json.dump(config_to_save, f, indent=2)
        except (OSError, IOError) as e:
            logging.error(f"Failed to save config: {e}")
            # Don't show alert here to avoid blocking, just log the error

    def days_since(self, date_string):
        """Mantiene la función para la clave de ordenación (segundos)"""
        _, seconds = self.get_release_age(date_string)
        return seconds
    
    def get_release_age(self, date_string):
        # Wrapper para usar la función importada con el diccionario de traducción actual
        return get_release_age(date_string, t)

    def _get_sort_key_function(self, is_sorted_by_name):
        """Crea una función de ordenación sin closures para evitar fugas de memoria."""
        def sort_key(repo_obj):
            repo_name = repo_obj.get("name", "")
            if is_sorted_by_name:
                return repo_name.split('/')[-1].lower()
            else:
                _, seconds = self.get_release_age(self.repo_cache.get(repo_name, {}).get("date"))
                return seconds
        return sort_key
    
    # === MANEJADORES DE CALLBACKS FIJOS ===
    def handle_open_releases(self, sender):
        webbrowser.open(f"https://github.com/{sender.identifier}/releases")

    def handle_show_notes(self, sender):
        repo_name = sender.identifier
        info = self.repo_cache.get(repo_name, {"name": repo_name, "body": t['noNotes']})
        self.show_release_notes(info)

    def handle_delete_repo(self, sender):
        self.remove_repo(sender.identifier)

    def handle_install_brew_cask(self, sender):
        self.install_brew_cask(sender.identifier)
        
    def show_about(self, sender):
        self.show_alert("GitHub Watcher", t['aboutMsg'])

    def quit_app(self, sender):
        # === LIMPIEZA COMPLETA DE TIMERS Y REFERENCIAS ===
        try:
            # Limpiar countdown timer
            if hasattr(self, 'countdown_timer') and self.countdown_timer:
                self.countdown_timer.stop()
                self.countdown_timer = None
            
            # Limpiar timer de batch processing
            if hasattr(self, '_menu_update_timer') and self._menu_update_timer:
                if self._menu_update_timer.is_alive():
                    self._menu_update_timer.cancel()
                self._menu_update_timer = None
            
            # Limpiar lista de actualizaciones pendientes
            if hasattr(self, '_pending_menu_updates'):
                self._pending_menu_updates.clear()
                
            # === NUEVO: Shutdown Executor y Session ===
            if hasattr(self, 'executor'):
                self.executor.shutdown(wait=False)
            if hasattr(self, 'session'):
                self.session.close()
            # === FIN NUEVO ===
        except Exception as e:
            logging.error(f"Error during quit: {e}")
        # === FIN LIMPIEZA ===
        rumps.quit_application(sender)
    # =================================================================
    
    def fetch_repo_info(self, repo: str) -> Dict[str, Any]: 
        # Headers ya configurados en self.session, solo añadimos Auth si es necesario
        request_headers = {}
        if self.token: 
            request_headers["Authorization"] = f"Bearer {self.token}"
            
        try:
            # Uso de self.session para reutilizar conexiones
            url = f"{const.GITHUB_API_BASE_URL}/repos/{repo}/releases/latest"
            with self.session.get(url, headers=request_headers, timeout=const.HTTP_REQUEST_TIMEOUT_SECONDS) as response:
                if response.status_code == 200:
                    data = response.json()
                    return {"name": repo, "version": data["tag_name"], "date": data["published_at"], "body": data.get("body", "")}
            
            # Intento de commits si no hay releases
            url = f"{const.GITHUB_API_BASE_URL}/repos/{repo}/commits?per_page=1"
            with self.session.get(url, headers=request_headers, timeout=const.HTTP_REQUEST_TIMEOUT_SECONDS) as response:
                if response.status_code == 200:
                    data = response.json()
                    if data:
                        commit = data[0]
                        return {"name": repo, "version": commit["sha"][:7], "date": commit["commit"]["author"]["date"], "body": commit["commit"]["message"]}
                        
            return {"name": repo, "error": "Not Found"}
        except requests.exceptions.RequestException as e:
            logging.error(f"Error fetching {repo}: {e}")
            return {"name": repo, "error": "Request Failed"}

    def _validate_github_token(self, token: str) -> bool:
        """Verifica si el token de GitHub es válido haciendo una petición /user."""
        if not token:
            self.show_alert(t['configureToken'], t['tokenValidationEmpty'])
            return True # Válido para eliminar el token (revertir a no autenticado)

        request_headers = {"Authorization": f"Bearer {token}"}
        try:
            # Endpoint simple para verificar autenticación
            # Usamos self.session pero con headers específicos para esta petición (override)
            url = f"{const.GITHUB_API_BASE_URL}/user"
            with self.session.get(url, headers=request_headers, timeout=const.HTTP_REQUEST_TIMEOUT_SECONDS) as response:
                if response.status_code == 200:
                    self.show_alert(t['configureToken'], t['tokenValidationSuccess'])
                    return True
                elif response.status_code == 401:
                    self.show_alert(t['error'], t['tokenValidationError'])
                    return False
                else:
                    self.show_alert(t['error'], f"{t['tokenValidationError']} (Code: {response.status_code})")
                    return False
                
        except requests.exceptions.RequestException:
            self.show_alert(t['error'], "Network error during token validation.")
            return False # No guardamos el token si hay un error de red
    
    def _get_refresh_title(self, is_refreshing: bool) -> str:
        """Returns the refresh button title with countdown information."""
        if is_refreshing: return t['refreshing']
        
        next_refresh_seconds = (self.last_refresh_time + self.config["refresh_minutes"] * 60) - time.time()
        
        if self.last_refresh_time > 0 and next_refresh_seconds > 0:
            if next_refresh_seconds < 3600: # Si es menos de una hora, muestra en minutos
                next_refresh_minutes = math.ceil(next_refresh_seconds / 60)
                return f"{t['refreshNow']} ({next_refresh_minutes} {t['minutes']})"
            else: # Si es una hora o más, muestra en horas
                next_refresh_hours = math.ceil(next_refresh_seconds / 3600)
                return f"{t['refreshNow']} ({next_refresh_hours} {t['hours']})"
        return t['refreshNow']
    
    def _format_repo_name(self, repo_name: str) -> str:
        """Formatea el nombre del repositorio según la configuración show_owner."""
        show_owner = self.config.get("show_owner", True)
        if show_owner:
            return repo_name
        else:
            # Extraer solo el nombre del repo (después del /)
            return repo_name.split('/')[-1] if '/' in repo_name else repo_name

    def _update_repo_menu_item(self, repo_name: str, info: Dict[str, Any]) -> bool:
        """Actualiza un ítem de menú de repositorio existente sin reconstruirlo."""
        if not self.menu: return False
        
        # Buscar el ítem actual (la clave del diccionario es el label)
        current_label = None
        menu_value = None
        
        # Iterar sobre el menú para encontrar el repositorio por nombre (usando regex en las keys)
        # Necesitamos comparar con el nombre formateado, no con el nombre completo
        formatted_name = self._format_repo_name(repo_name)
        for key, val in self.menu.items():
            if isinstance(val, dict):
                # Chequear si este submenú corresponde al repo
                # La key es el label completo formateado según show_owner
                match = self.repo_label_regex.match(key)
                if match and match.group(1).strip() == formatted_name:
                    current_label = key
                    menu_value = val
                    break
        
        if current_label and menu_value:
            if "version" in info:
                age_text, seconds_diff = self.get_release_age(info.get("date"))
                days_diff = math.floor(seconds_diff / 86400)
                new_indicator = f" {const.NEW_RELEASE_INDICATOR}" if days_diff <= const.NEW_RELEASE_THRESHOLD_DAYS else ""
                formatted_name = self._format_repo_name(repo_name)
                new_label = f"{formatted_name} ({info['version']}) · {age_text}{new_indicator}"
                
                # Verificamos si el título actual del ítem es diferente al nuevo
                # Nota: current_label es la CLAVE en el dict, que puede no coincidir con el título si ya se actualizó.
                # Por eso chequeamos menu_value.title
                if menu_value.title != new_label:
                    menu_value.title = new_label
                
                return True
        return False

    def update_countdown(self, sender: Any) -> None:
        if self.refresh_lock.locked(): return

        # === OPTIMIZACIÓN: Calcular tiempo actual una vez ===
        current_time = time.time()
        # === FIN OPTIMIZACIÓN ===

        # --- LÓGICA DE ACTUALIZACIÓN DEL CONTADOR ---
        refresh_title = self._get_refresh_title(False)
        
        if self.menu and len(self.menu.keys()) > 0:
            # === OPTIMIZACIÓN: Acceso eficiente al primer elemento sin crear lista completa ===
            first_key = next(iter(self.menu.keys()), None)
            # === FIN OPTIMIZACIÓN ===
            
            # 1. Actualiza el título del botón de refresco
            if first_key is not None and isinstance(self.menu[first_key], rumps.MenuItem):
                self.menu[first_key].title = refresh_title
                self.menu[first_key].set_callback(self.trigger_full_refresh) 
            
            # 2. Actualiza los títulos de todos los repositorios (Mitigación)
            for repo_name, info in self.repo_cache.items():
                self._update_repo_menu_item(repo_name, info)

        # 2. Solo llama al full refresh si el tiempo ha expirado.
        if current_time - self.last_refresh_time >= self.config["refresh_minutes"] * 60:
            self.trigger_full_refresh(None)

    def build_menu(self) -> None:
        """
        Constructs the menu bar interface.
        
        Performs the following:
        1. Clears existing menu items and callbacks
        2. Adds refresh and add-repo buttons
        3. Populates repository list (sorted per config)
        4. Adds preferences submenu
        
        Note: Protected by menu_building flag to prevent concurrent builds.
        """
        # === PROTECCIÓN CONTRA RECONSTRUCCIONES SIMULTÁNEAS ===
        if self.menu_building:
            return  # Ya se está construyendo el menú, evitar duplicados
        self.menu_building = True
        # === FIN PROTECCIÓN ===
        
        try:
            # === LIMPIEZA EXPLÍCITA DE REFERENCIAS ANTES DE RECONSTRUIR ===
            # Limpiar callbacks y referencias antes de limpiar el menú para evitar fugas
            if hasattr(self, 'menu') and self.menu:
                for key, value in list(self.menu.items()):
                    if isinstance(value, rumps.MenuItem):
                        # Limpiar callback para liberar referencias circulares
                        try:
                            value.set_callback(None)
                            value.identifier = None
                        except Exception as e:
                            logging.warning(f"Error clearing callback: {e}")
                    elif isinstance(value, dict):
                        # Limpiar submenús recursivamente
                        for sub_key, sub_value in value.items():
                            if isinstance(sub_value, list):
                                for item in sub_value:
                                    if isinstance(item, rumps.MenuItem):
                                        try:
                                            item.set_callback(None)
                                            item.identifier = None
                                        except Exception as e:
                                            logging.warning(f"Error clearing sub-item callback: {e}")
                                    # === NUEVO: Limpiar separadores u otros objetos ===
                                    elif item is not None:
                                        pass 
            # === FIN LIMPIEZA EXPLÍCITA ===
            
            self.menu.clear()
            
            is_refreshing = self.refresh_lock.locked()
            refresh_title = self._get_refresh_title(is_refreshing)

            if not self._mi_refresh:
                self._mi_refresh = rumps.MenuItem(refresh_title, callback=self.trigger_full_refresh)
            else:
                self._mi_refresh.title = refresh_title
                self._mi_refresh.set_callback(self.trigger_full_refresh if not is_refreshing else None)

            # La lista inicial de elementos estáticos, incluyendo el separador
            menu_items = [
                self._mi_refresh,
                (self._mi_add_manual or rumps.MenuItem(t['addRepoUnified'], callback=self.unified_add_repo_dialog)),
            ]
            self._mi_add_manual = menu_items[1]
            
            # El separador es INCONDICIONAL (siempre debe ir después de los botones de añadir)
            menu_items.append(None)
            
            # --- Repositories List ---
            is_sorted_by_name = self.config.get("sort_by", "date") == "name"
            # === CORRECCIÓN: Usar función helper para evitar closures ===
            sorted_repos_config = sorted(self.config.get("repos", []), key=self._get_sort_key_function(is_sorted_by_name))
            # === FIN CORRECCIÓN ===
            
            if not sorted_repos_config:
                menu_items.append(rumps.MenuItem(t['noRepos']))

            for repo_obj in sorted_repos_config:
                repo_name = repo_obj.get("name")
                if not repo_name: continue
                
                info = self.repo_cache.get(repo_name, {"name": repo_name})
                
                label = f"{repo_name} - {t['loading']}"
                if "error" in info:
                    label = f"⚠️ {repo_name} - {t['error']}"
                elif "version" in info:
                    # === Obtener edad de release formateada ===
                    age_text, seconds_diff = self.get_release_age(info.get("date"))
                    days_diff = math.floor(seconds_diff / 86400)
                    new_indicator = f" {const.NEW_RELEASE_INDICATOR}" if days_diff <= const.NEW_RELEASE_THRESHOLD_DAYS else ""
                    formatted_name = self._format_repo_name(repo_name)
                    label = f"{formatted_name} ({info['version']}) · {age_text}{new_indicator}"
                    # === Fin Obtener edad de release formateada ===
                    
                open_item = rumps.MenuItem(t['openReleases'], callback=self.handle_open_releases)
                open_item.identifier = repo_name 
                
                notes_item = rumps.MenuItem(t['releaseNotes'], callback=self.handle_show_notes)
                notes_item.identifier = repo_name 
                
                submenu = [
                    open_item,
                    notes_item,
                ]
                
                # Si es de brew, añadir opción de actualizar
                if self.brew_path and repo_obj.get("source") == "brew":
                    cask_name = repo_obj.get("cask")
                    
                    install_item = rumps.MenuItem(t['installUpdate'], callback=self.handle_install_brew_cask)
                    install_item.identifier = cask_name 
                    
                    submenu.extend([
                        None,
                        install_item
                    ])
                    
                delete_item = rumps.MenuItem(t['deleteRepo'], callback=self.handle_delete_repo)
                delete_item.identifier = repo_name 
                    
                submenu.extend([
                        None,
                        delete_item
                    ])
                
                menu_items.append({label: submenu})
            
            # --- Preferences Submenu ---
            login_item = rumps.MenuItem(t['startAtLogin'], callback=self.toggle_login_item)
            # === CORRECCIÓN: Limpiar state antes de asignar para evitar referencias ===
            try:
                login_item.state = 0  # Reset antes de asignar nuevo valor
            except Exception as e:
                logging.warning(f"Error resetting login item state: {e}")
            login_item.state = self.is_login_item()
            # === FIN CORRECCIÓN ===
            
            # Si está ordenado por NOMBRE, el título debe ser la opción CONTRARIA (FECHA)
            if is_sorted_by_name:
                sort_toggle_title = t.get("sortByDate", "Sort by Date")
            else: # Si está ordenado por FECHA, el título debe ser la opción CONTRARIA (NOMBRE)
                sort_toggle_title = t.get("sortByName", "Sort by Name")
            
            if not self._mi_sort_toggle:
                self._mi_sort_toggle = rumps.MenuItem(sort_toggle_title, callback=self.toggle_sort_order)
            else:
                self._mi_sort_toggle.title = sort_toggle_title
                self._mi_sort_toggle.set_callback(self.toggle_sort_order)
            
            # Toggle para mostrar/ocultar owner
            show_owner = self.config.get("show_owner", True)
            owner_toggle_title = t.get("hideOwner") if show_owner else t.get("showOwner")
            
            if not self._mi_owner_toggle:
                self._mi_owner_toggle = rumps.MenuItem(owner_toggle_title, callback=self.toggle_owner_display)
            else:
                self._mi_owner_toggle.title = owner_toggle_title
                self._mi_owner_toggle.set_callback(self.toggle_owner_display)
            
            preferences_menu = [
                login_item,
                self._mi_sort_toggle,
                self._mi_owner_toggle,
            ]
            
            preferences_menu.extend([
                rumps.MenuItem(t['configureToken'], callback=self.configure_token_dialog),
                rumps.MenuItem(t['changeInterval'], callback=self.change_interval_dialog),
                rumps.MenuItem(t['about'], callback=self.show_about),
            ])
            
            menu_items.extend([
                None,
                {t['preferences']: preferences_menu},
                None,
                rumps.MenuItem(t['quit'], callback=self.quit_app)
            ])
            
            self.menu = menu_items
            
        finally:
            # === LIBERAR EL FLAG ===
            self.menu_building = False
            # === FIN LIBERACIÓN ===

    # --- NUEVA FUNCIÓN: Despacho seguro al hilo principal ---
    def _dispatch_update_to_main_thread(self, update_type, data):
        """Dispatches an update to the main thread to be processed."""
        safe_dispatch_to_main_thread(self._process_update_data, update_type, data)

    # --- NUEVA FUNCIÓN: Procesamiento de datos en el hilo principal ---
    def _process_update_data(self, update_type, data):
        """Processes the received data and rebuilds the menu if necessary. Executed ONLY on main thread."""
        
        if update_type == "repo_fetch_result":
            repo_name, repo_data = data
            # === OPTIMIZACIÓN: Batch processing - agrupar actualizaciones ===
            self._pending_menu_updates.append((repo_name, repo_data))
            
            # Cancelar timer anterior si existe
            if self._menu_update_timer and self._menu_update_timer.is_alive():
                self._menu_update_timer.cancel()
            
            # Programar actualización del menú después de un delay
            # === IMPORTANTE: El timer ejecuta en un thread, pero necesitamos ejecutar en el hilo principal ===
            def schedule_batch_update():
                safe_dispatch_to_main_thread(self._process_batched_updates)
            
            self._menu_update_timer = threading.Timer(self._menu_update_delay, schedule_batch_update)
            self._menu_update_timer.daemon = True
            self._menu_update_timer.start()
            return
            # === FIN OPTIMIZACIÓN ===
        
        elif update_type == "brew_cask_list":
            self._show_brew_selection_dialog(data)
            return
    
    def _process_batched_updates(self):
        """Procesa todas las actualizaciones pendientes en batch."""
        if not self._pending_menu_updates:
            return
        
        needs_rebuild = False
        
        # Procesar todas las actualizaciones pendientes
        for repo_name, repo_data in self._pending_menu_updates:
            old_info = self.repo_cache.get(repo_name)
            
            if repo_data is None:
                # Caso: Eliminación de repo (si falló fetch y decidimos borrarlo, o lógica externa)
                if repo_name in self.repo_cache:
                    del self.repo_cache[repo_name]
                    needs_rebuild = True
            else:
                # Caso: Actualización o Nuevo Repo
                if old_info is None:
                    # Es un repositorio nuevo que no estaba en cache -> Necesita rebuild para añadirlo al menú
                    self.repo_cache[repo_name] = repo_data
                    needs_rebuild = True
                else:
                    # Es un repositorio existente -> Intentamos actualización in-place
                    self.repo_cache[repo_name] = repo_data
                    # Actualizamos el ítem del menú directamente
                    if not self._update_repo_menu_item(repo_name, repo_data):
                        # Si no se pudo actualizar in-place (ej. estaba en "Loading..." y no matcheó el regex), reconstruimos
                        needs_rebuild = True
                    
                    # === CORRECCIÓN: Si ordenamos por fecha, forzar rebuild para reordenar ===
                    if self.config.get("sort_by", "date") == "date":
                        needs_rebuild = True
                    # === FIN CORRECCIÓN ===
        
        # === CORRECCIÓN: Limitar el tamaño del cache para evitar crecimiento indefinido ===
        # Mantener solo los repositorios que están en la configuración actual
        current_repos = {r.get("name") for r in self.config.get("repos", []) if r.get("name")}
        # === OPTIMIZACIÓN: Usar set difference para eliminación eficiente ===
        repos_to_remove = set(self.repo_cache.keys()) - current_repos
        if repos_to_remove:
            for repo in repos_to_remove:
                del self.repo_cache[repo]
            needs_rebuild = True # Si borramos algo, reconstruimos
        # === FIN OPTIMIZACIÓN ===
        # === FIN CORRECCIÓN ===
        
        if needs_rebuild:
            self.build_menu()
            
        self._pending_menu_updates.clear()

    def _background_fetch(self, repos_to_fetch=None):
        if not repos_to_fetch:
            repos_to_fetch = [r.get("name") for r in self.config.get("repos", []) if r.get("name")]
            
        self.refresh_lock.acquire()
        try:
            # === OPTIMIZACIÓN: Ejecución paralela con ThreadPoolExecutor ===
            # Usamos el executor global de la clase
            futures = {self.executor.submit(self.fetch_repo_info, repo): repo for repo in repos_to_fetch}
            
            for future in concurrent.futures.as_completed(futures):
                repo = futures[future]
                try:
                    repo_data = future.result()
                    self._dispatch_update_to_main_thread("repo_fetch_result", (repo, repo_data))
                except Exception as e:
                    logging.error(f"Error fetching {repo}: {e}")
                    self._dispatch_update_to_main_thread("repo_fetch_result", (repo, {"name": repo, "error": "Error"}))
            # === FIN OPTIMIZACIÓN ===
            
            # Si era un refresh completo, actualizamos el timestamp
            if len(repos_to_fetch) == len(self.config.get("repos", [])):
                self.last_refresh_time = time.time()
                
        except Exception as e:
            logging.error(f"Global fetch error: {e}")
        finally:
            self.refresh_lock.release()

    def trigger_full_refresh(self, _):
        if self.refresh_lock.locked(): return
        
        # Actualizar UI inmediatamente para mostrar "Refreshing..."
        if self._mi_refresh:
            self._mi_refresh.title = self._get_refresh_title(True)
            self._mi_refresh.set_callback(None) # Desactivar mientras refresca
            
        # Lanzar en background
        threading.Thread(target=self._background_fetch, daemon=True).start()

    def show_alert(self, title, message, buttons=[t['ok']]):
        NSApp().activateIgnoringOtherApps_(True)
        alert = NSAlert.alloc().init()
        alert.setMessageText_(title)
        # Usamos setInformativeText para el mensaje principal (unificación de diálogos)
        alert.setInformativeText_(message)
        
        for button_title in buttons:
            alert.addButtonWithTitle_(button_title)
        return alert.runModal()

    def remove_repo(self, repo_name_to_delete):
        NSApp().activateIgnoringOtherApps_(True)
        # Diálogo unificado (título y mensaje informativo)
        response = self.show_alert(
            t['deleteRepo'],
            f"{t['confirmDelete']}\n\n'{repo_name_to_delete}'",
            buttons=[t['ok'], t['cancel']]
        )
        if response == 1000:
            self.config["repos"] = [r for r in self.config.get("repos", []) if r.get("name") != repo_name_to_delete]
            if repo_name_to_delete in self.repo_cache:
                del self.repo_cache[repo_name_to_delete]
            self.save_config()
            self.build_menu()

    def show_release_notes(self, info):
        NSApp().activateIgnoringOtherApps_(True)
        repo_name = info['name']
        title = t['releaseNotes'] # Título genérico
        message = info.get("body", t['noNotes'])
        if not message or message.strip() == "": message = t['noNotes']
        
        # Buscar si este repositorio tiene un cask asociado
        cask_name = None
        for repo_obj in self.config.get("repos", []):
            if repo_obj.get("name") == repo_name and repo_obj.get("source") == "brew":
                cask_name = repo_obj.get("cask")
                break
        
        # Construir el mensaje informativo
        informative_text = repo_name
        if cask_name:
            informative_text += f"\nCask: {cask_name}"
        
        alert = NSAlert.alloc().init()
        alert.setMessageText_(title)
        # Mensaje informativo: El nombre del repo y el cask si existe
        alert.setInformativeText_(informative_text)
 
        alert.addButtonWithTitle_(t['ok'])
        
        # Usamos NSScrollView para el cuerpo principal de las notas
        scroll_view_rect = NSMakeRect(0, 0, 450, 250)
        scroll_view = NSScrollView.alloc().initWithFrame_(scroll_view_rect)
        scroll_view.setHasVerticalScroller_(True)
        scroll_view.setAutohidesScrollers_(True)
        
        # Crear NSTextView con un ancho menor para dejar espacio al scroller (20px de margen)
        text_view_width = scroll_view_rect.size.width - 20 # 450 - 20 = 430 de ancho
        text_view_rect = NSMakeRect(0, 0, text_view_width, scroll_view_rect.size.height)
        
        text_view = NSTextView.alloc().initWithFrame_(text_view_rect)
        text_view.setString_(message)
        text_view.setEditable_(False)
        # Restaurado el modo oscuro: El color de texto ya no se establece, hereda el color del sistema
        text_view.setFont_(text_view.font().fontWithSize_(12))
        
        # Ajustar el tamaño del contenedor de texto para que sepa dónde hacer wrap
        text_container = text_view.textContainer()
        text_container.setContainerSize_(NSSize(text_view_width, 100000.0))
        text_container.setWidthTracksTextView_(True)
        
        scroll_view.setDocumentView_(text_view)
        alert.setAccessoryView_(scroll_view)
        alert.runModal()
        
        # === LIBERACIÓN EXPLÍCITA DE OBJETOS OBJECTIVE-C ===
        # Limpiar referencias para ayudar al garbage collector y prevenir fugas
        try:
            scroll_view.setDocumentView_(None)
            alert.setAccessoryView_(None)
        except Exception as e:
            logging.error(f"Error cleaning up release notes view: {e}")
        # === FIN LIBERACIÓN EXPLÍCITA ===
        
    def _add_repo(self, repo_name: str, source: str = "manual", cask: Optional[str] = None):
        if not repo_name or "/" not in repo_name or len(repo_name.split('/')) != 2:
            self.show_alert(t['error'], t['invalidRepoFormat']); return
            
        repo_to_update_index = -1
        for i, repo_obj in enumerate(self.config["repos"]):
            if repo_obj.get("name") == repo_name:
                repo_to_update_index = i
                break
        
        if repo_to_update_index != -1:
            if self.config["repos"][repo_to_update_index].get("source") == "manual" and source == "brew":
                self.config["repos"][repo_to_update_index]["source"] = "brew"
                self.config["repos"][repo_to_update_index]["cask"] = cask
                self.save_config()
                self.build_menu()
            else:
                self.show_alert(t['error'], t['repoExists'])
            return

        try:
            request_headers = {}
            if self.token: request_headers["Authorization"] = f"Bearer {self.token}"
            check_url = f"{const.GITHUB_API_BASE_URL}/repos/{repo_name}"
            
            with self.session.get(check_url, headers=request_headers, timeout=const.HTTP_REQUEST_TIMEOUT_SECONDS) as check_response:
                if check_response.status_code == 200:
                    new_repo_obj = {"name": repo_name, "source": source}
                    if cask: new_repo_obj["cask"] = cask
                    
                    self.config["repos"].append(new_repo_obj)
                    self.save_config()
                    self.repo_cache[repo_name] = {"name": repo_name}
                    self.build_menu()
                    
                    # === CORRECCIÓN: Usar Executor ===
                    self.executor.submit(self._background_fetch, [repo_name])
                    # === FIN CORRECCIÓN ===
                else:
                    self.show_alert(t['error'], t['repoNotFound'])
                
        except requests.exceptions.RequestException:
            self.show_alert(t['error'], "Network error during validation.")

    def _fetch_brew_casks(self):
        try:
            result = subprocess.run([self.brew_path, "list", "--casks"], capture_output=True, text=True, check=True)
            cask_list = sorted(result.stdout.strip().split('\n'))
            self._dispatch_update_to_main_thread("brew_cask_list", cask_list)
        except Exception as e:
            logging.warning(f"Could not get brew cask list: {e}")
            self._dispatch_update_to_main_thread("brew_cask_list", [])

    def _show_brew_selection_dialog(self, brew_casks):
        NSApp().activateIgnoringOtherApps_(True)
        alert = NSAlert.alloc().init()
        alert.setMessageText_(t['addRepoBrew'])
        # Mensaje informativo
        alert.setInformativeText_(t['addFromBrew'])
        
        popup_button = NSPopUpButton.alloc().initWithFrame_(NSMakeRect(0, 0, 300, 24))
        if brew_casks:
            # === CAMBIO CLAVE: Usar la clave de placeholder ===
            popup_button.addItemsWithTitles_([t['selectCaskPlaceholder']] + brew_casks)
            # === FIN CAMBIO CLAVE ===
        else:
            popup_button.addItemsWithTitles_([t['loadingBrew']])
            popup_button.setEnabled_(False)
            
        alert.setAccessoryView_(popup_button)
        alert.addButtonWithTitle_(t['ok'])
        alert.addButtonWithTitle_(t['cancel'])
        
        if alert.runModal() == 1000 and popup_button.indexOfSelectedItem() > 0:
            selected_cask = popup_button.titleOfSelectedItem()
            try:
                api_url = f"https://formulae.brew.sh/api/cask/{selected_cask}.json"
                # Usamos self.session para esta petición también
                with self.session.get(api_url, timeout=10) as response:
                    response.raise_for_status()
                    info_json = response.json()
                
                repo_name = None
                github_regex = re.compile(r'github\.com/([^/]+/[^/\s"]+)')
                
                for key in ["verified", "homepage", "url"]:
                    if repo_name: break
                    url_string = ""
                    if key == "verified":
                        url_string = info_json.get("url_specs", {}).get("verified", "")
                    else:
                        url_string = info_json.get(key, "")
                    if url_string:
                        match = github_regex.search(url_string)
                        if match: repo_name = match.group(1).replace('.git', '')
                
                if repo_name:
                    self._add_repo(repo_name, source="brew", cask=selected_cask)
                else:
                    self.show_alert(t['brewErrorTitle'], t['brewRepoNotFound'].format(app_name=selected_cask))
            except Exception as e:
                self.show_alert(t['error'], f"Could not get info for {selected_cask}: {e}")
        
        # === LIBERACIÓN EXPLÍCITA DE OBJETOS OBJECTIVE-C ===
        try:
            alert.setAccessoryView_(None)
        except Exception as e:
            logging.error(f"Error cleaning up brew selection dialog: {e}")
        # === FIN LIBERACIÓN ===

    def configure_token_dialog(self, _):
        NSApp().activateIgnoringOtherApps_(True)
        
        current_token = self.token
        
        # === SEGURIDAD: No mostrar el token actual, solo indicador enmascarado ===
        if current_token and len(current_token) > 4:
            masked_indicator = f"••••••••{current_token[-4:]}"
        elif current_token:
            masked_indicator = "••••••••"
        else:
            masked_indicator = None
        # === FIN SEGURIDAD ===
        
        # === PEGADO INTELIGENTE: Siempre activo ===
        prefill_from_clipboard = ""
        try:
            clipboard_content = subprocess.run("pbpaste", capture_output=True, text=True, check=True).stdout.strip()
            # Patrón para tokens de GitHub (PATs modernos y viejos)
            token_regex = re.compile(r'((?:gh[ps]_|github_pat_)[a-zA-Z0-9_-]{36,})|([0-9a-fA-F]{40})')
            match = token_regex.search(clipboard_content)
            
            if match:
                prefill_from_clipboard = match.group(1) or match.group(2)
        except Exception as e: 
            logging.debug(f"Clipboard read error: {e}") 
        # === FIN PEGADO INTELIGENTE ===

        alert = NSAlert.alloc().init()
        alert.setMessageText_(t['configureToken'])
        
        # Mensaje informativo según si hay token guardado o no
        if masked_indicator:
            info_msg = f"{t['enterTokenMsg']}\n\n{t.get('currentToken', 'Current token')}: {masked_indicator}"
        else:
            info_msg = t['enterTokenMsg']
        alert.setInformativeText_(info_msg)

        input_field = NSTextField.alloc().initWithFrame_(NSMakeRect(0, 0, 300, 50)) 
        
        # El campo empieza con token del clipboard (si lo hay) o vacío
        input_field.setStringValue_(prefill_from_clipboard)
        input_field.setPlaceholderString_(t.get('tokenPlaceholder', 'Paste new token here...'))
        
        alert.setAccessoryView_(input_field)
        alert.addButtonWithTitle_(t['ok'])
        alert.addButtonWithTitle_(t['cancel'])
        
        # Agregar botón "Borrar Token" solo si hay un token guardado
        if current_token:
            alert.addButtonWithTitle_(t.get('deleteToken', 'Delete Token'))
        
        response = alert.runModal()
        
        # NSAlertFirstButtonReturn = 1000, Second = 1001, Third = 1002
        if response == 1000:  # OK
            new_token = input_field.stringValue().strip()
            
            # Caso 1: Usuario ingresó un nuevo token
            if new_token:
                if self._validate_github_token(new_token):
                    save_token_to_keychain(new_token)
                    self.token = new_token
                    self.trigger_full_refresh(None)
            # Caso 2: Campo vacío -> Mantener el token actual (no hacer nada)
            # No se borra automáticamente, para eso está el botón explícito
            
        elif response == 1002 and current_token:  # Borrar Token (tercer botón)
            delete_token_from_keychain()
            self.token = None
            self.show_alert(
                t['configureToken'], 
                t.get('tokenValidationEmpty', 'Token deleted.')
            )
            self.trigger_full_refresh(None)
        
        # === LIBERACIÓN EXPLÍCITA DE OBJETOS OBJECTIVE-C ===
        try:
            alert.setAccessoryView_(None)
        except Exception as e:
            logging.error(f"Error cleaning up token dialog: {e}")
        # === FIN LIBERACIÓN ===

    def change_interval_dialog(self, _):
        NSApp().activateIgnoringOtherApps_(True)
        
        current_hours = max(1, min(24, round(self.config["refresh_minutes"] / 60))) 
        
        alert = NSAlert.alloc().init()
        alert.setMessageText_(t['changeInterval'])
        alert.setInformativeText_(t['enterIntervalMsg']) # Mensaje informativo
        
        # Contenedor para los controles (aumentamos altura para slider y label)
        custom_view = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 300, 50))
        
        # 1. Crear el Slider
        slider = NSSlider.alloc().initWithFrame_(NSMakeRect(50, 20, 200, 24))
        slider.setMinValue_(1.0)
        slider.setMaxValue_(24.0)
        slider.setNumberOfTickMarks_(24)
        slider.setAllowsTickMarkValuesOnly_(True)
        slider.setIntValue_(current_hours)
        
        # 2. Crear el Label para mostrar el valor
        label = NSTextField.alloc().initWithFrame_(NSMakeRect(0, 0, 300, 20))
        label.setBezeled_(False)
        label.setDrawsBackground_(False)
        label.setEditable_(False)
        label.setAlignment_(2) # Center alignment (NSTextAlignmentCenter = 2 approx or 1 depending on version, 2 is usually center in older docs, let's try 1 if 2 fails, but 2 is standard Center)
        # Actually NSTextAlignmentCenter is 1 in Swift/modern ObjC, but historically 2. Let's stick to default alignment or just center manually if needed.
        label.setAlignment_(1) # 1 = Center
        
        if current_hours == 1:
            label.setStringValue_(f"1 {t['unitHour']}")
        else:
            label.setStringValue_(f"{current_hours} {t['hours']}")
            
        # 3. Handler para actualizar el label al mover el slider
        # Necesitamos mantener una referencia al handler para que no sea recolectado
        # Usamos init estándar y asignamos propiedades para evitar ObjCSuperWarning
        self._slider_handler = SliderHandler.alloc().init()
        self._slider_handler.label = label
        self._slider_handler.t = t
        
        slider.setTarget_(self._slider_handler)
        slider.setAction_("sliderChanged:")
        
        custom_view.addSubview_(slider)
        custom_view.addSubview_(label)
        
        alert.setAccessoryView_(custom_view)
        alert.addButtonWithTitle_(t['ok'])
        alert.addButtonWithTitle_(t['cancel'])
        
        if alert.runModal() == 1000:
            new_hours = slider.intValue()

            self.config["refresh_minutes"] = new_hours * 60
            self.save_config()
            self.last_refresh_time = time.time()
            self.build_menu()
        
        # === LIBERACIÓN EXPLÍCITA DE OBJETOS OBJECTIVE-C ===
        try:
            alert.setAccessoryView_(None)
            self._slider_handler = None # Liberar referencia al handler
        except Exception as e:
            logging.error(f"Error cleaning up interval dialog: {e}")
        # === FIN LIBERACIÓN ===

    def is_login_item(self):
        return self.launch_agent_path.exists()

    def toggle_login_item(self, sender):
        # === LIMPIEZA DEL SENDER PARA EVITAR REFERENCIAS CIRCULARES ===
        if sender:
            try:
                sender.set_callback(None)
            except Exception as e:
                logging.error(f"Error removing login item: {e}")
        # === FIN LIMPIEZA ===
        
        if self.is_login_item():
            # Si ya existe, solo eliminamos el archivo plist
            # NO usamos launchctl unload porque si la app fue lanzada por el LaunchAgent,
            # descargar el agente terminaría el proceso actual, causando un cierre inesperado.
            # El agente simplemente no se cargará en el próximo inicio de sesión.
            if self.launch_agent_path.exists():
                self.launch_agent_path.unlink()
                logging.info("LaunchAgent removed. Will not start on next login.")
        else:
            # Si no existe, lo creamos y cargamos
            # Determinar el path del ejecutable de la app empaquetada
            # sys.executable apunta al binario Python dentro del .app cuando está empaquetado
            # Necesitamos el ejecutable principal de la app (ej: .app/Contents/MacOS/GitHubWatcher)
            
            # En app empaquetada: /path/to/App.app/Contents/MacOS/Python (py2app) o /path/to/App.app/Contents/MacOS/AppName (pyinstaller)
            # Intentamos encontrar el ejecutable correcto
            if '.app/Contents/MacOS/' in sys.executable:
                # Estamos en una app empaquetada
                app_bundle_path = sys.executable.split('/Contents/MacOS/')[0]
                # Buscar el ejecutable principal en Contents/MacOS/
                macos_dir = Path(app_bundle_path) / 'Contents' / 'MacOS'
                
                # Buscar archivos ejecutables que NO sean Python
                executable_path = None
                if macos_dir.exists():
                    for item in macos_dir.iterdir():
                        if item.is_file() and item.name != 'Python' and item.name != 'python':
                            # Verificar si tiene permisos de ejecución
                            if item.stat().st_mode & 0o111:
                                executable_path = str(item)
                                break
                
                # Si no encontramos ejecutable específico, usar el .app con open
                if not executable_path:
                    executable_path = f"{app_bundle_path}"
                    use_open_command = True
                else:
                    use_open_command = False
            else:
                # En desarrollo, apuntar a main.py o al script actual
                executable_path = str(Path(__file__).parent.parent / "main.py")
                use_open_command = False
            
            # Construir el plist según si usamos open o ejecutable directo
            if use_open_command:
                plist_content = f"""
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{self.launch_agent_label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>{executable_path}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
"""
            else:
                # Usar ejecutable directo (mejor para que macOS reconozca la app correctamente)
                plist_content = f"""
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{self.launch_agent_label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{executable_path}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
"""
            
            try:
                self.launch_agent_path.parent.mkdir(parents=True, exist_ok=True)
                with open(self.launch_agent_path, "w") as f:
                    f.write(plist_content.strip())
                
                # NO hacemos launchctl load para evitar lanzar una instancia duplicada
                # El agente se cargará automáticamente en el próximo inicio de sesión
                logging.info("LaunchAgent created. Will start on next login.")
                    
            except Exception as e:
                logging.error(f"Error creating LaunchAgent: {e}")
            
        self.build_menu()
        
    def toggle_sort_order(self, sender):
        # === LIMPIEZA DEL SENDER ===
        if sender:
            try:
                sender.set_callback(None)
            except Exception as e:
                logging.error(f"Error removing launch agent: {e}")
        # === FIN LIMPIEZA ===
        
        current_sort = self.config.get("sort_by", "date")
        self.config["sort_by"] = "name" if current_sort == "date" else "date"
        self.save_config()
        self.build_menu()
    
    def toggle_owner_display(self, sender):
        """Alterna entre mostrar owner/repo o solo repo."""
        # === LIMPIEZA DEL SENDER ===
        if sender:
            try:
                sender.set_callback(None)
            except Exception as e:
                logging.error(f"Error in toggle_owner_display: {e}")
        # === FIN LIMPIEZA ===
        
        current_show_owner = self.config.get("show_owner", True)
        self.config["show_owner"] = not current_show_owner
        self.save_config()
        self.build_menu()

    def unified_add_repo_dialog(self, _):
        NSApp().activateIgnoringOtherApps_(True)
        
        # === Preparar Handler ===
        # Retenemos el handler en self para asegurar su ciclo de vida
        self._add_repo_handler = AddRepoHandler.alloc().init()
        self._add_repo_handler.app_ref = self
        handler = self._add_repo_handler
        
        alert = NSAlert.alloc().init()
        alert.setMessageText_(t['addRepoUnified'])
        alert.setInformativeText_(t['enterRepoMsg']) # Default for Manual
        
        # Configurar handler con alert y traducciones
        handler.alert = alert
        handler.t = t
        
        # Contenedor principal
        main_view = NSView.alloc().initWithFrame_(NSMakeRect(0, 0, 300, 100))
        
        # --- Radio Buttons ---
        radio_manual = NSButton.alloc().initWithFrame_(NSMakeRect(0, 70, 150, 24))
        radio_manual.setButtonType_(4) # NSRadioButton
        radio_manual.setTitle_(t['manualOption'])
        radio_manual.setTag_(1)
        radio_manual.setState_(1) # Selected by default
        radio_manual.setTarget_(handler)
        radio_manual.setAction_("radioChanged:")
        
        radio_brew = NSButton.alloc().initWithFrame_(NSMakeRect(150, 70, 150, 24))
        radio_brew.setButtonType_(4) # NSRadioButton
        radio_brew.setTitle_(t['brewOption'])
        radio_brew.setTag_(2)
        radio_brew.setTarget_(handler)
        radio_brew.setAction_("radioChanged:")
        
        if not self.brew_path:
            radio_brew.setEnabled_(False)
            radio_brew.setTitle_(t['brewOption'])
            
        main_view.addSubview_(radio_manual)
        main_view.addSubview_(radio_brew)
        
        # --- Manual Input Field ---
        prefill_text = ""
        try:
            clipboard_content = subprocess.run("pbpaste", capture_output=True, text=True, check=True).stdout.strip()
            repo_regex = re.compile(r'(?:github\.com/)?([^/\s"]+/[^/\s"]+)')
            match = repo_regex.search(clipboard_content)
            if match:
                repo_candidate = match.group(1).replace('.git', '')
                repo_name = repo_candidate.rstrip('/')
                repo_name = re.sub(r'[\?#].*$', '', repo_name)
                if len(repo_name.split('/')) == 2:
                    prefill_text = repo_name
        except Exception as e: 
            logging.debug(f"Clipboard read error: {e}")
        
        input_field = NSTextField.alloc().initWithFrame_(NSMakeRect(0, 30, 300, 24))
        input_field.setStringValue_(prefill_text)
        input_field.setPlaceholderString_("owner/repo-name")
        
        main_view.addSubview_(input_field)
        handler.input_field = input_field
        
        # --- Brew Popup ---
        popup_button = NSPopUpButton.alloc().initWithFrame_(NSMakeRect(0, 30, 300, 24))
        popup_button.addItemsWithTitles_([t['loadingBrew']])
        popup_button.setEnabled_(False)
        popup_button.setHidden_(True) # Hidden by default
        
        main_view.addSubview_(popup_button)
        handler.brew_popup = popup_button
        
        alert.setAccessoryView_(main_view)
        alert.addButtonWithTitle_(t['ok'])
        alert.addButtonWithTitle_(t['cancel'])
        
        response = alert.runModal()
        
        if response == 1000:
            if radio_manual.state() == 1:
                # Manual Mode
                repo_to_add = input_field.stringValue().strip()
                if repo_to_add:
                    # Usamos _add_repo_smart para detectar automáticamente Casks
                    self._add_repo_smart(repo_to_add)
            else:
                # Brew Mode
                if popup_button.indexOfSelectedItem() > 0:
                    selected_cask = popup_button.titleOfSelectedItem()
                    # Lógica de añadir desde brew (copiada de _show_brew_selection_dialog)
                    self._process_brew_selection(selected_cask)

        # Limpieza
        try:
            alert.setAccessoryView_(None)
            radio_manual.setTarget_(None)
            radio_brew.setTarget_(None)
            
            # Romper ciclo de referencias
            if self._add_repo_handler:
                self._add_repo_handler.app_ref = None
                self._add_repo_handler.alert = None
                self._add_repo_handler.input_field = None
                self._add_repo_handler.brew_popup = None
                
            self._add_repo_handler = None # Liberar referencia
        except Exception as e:
            logging.error(f"Error cleaning up unified dialog: {e}")

    def _add_repo_smart(self, repo_name):
        """
        Intenta añadir un repositorio de forma inteligente.
        Si detecta que existe un Cask de Homebrew asociado, lo añade como Cask.
        Si no, lo añade como repositorio manual.
        """
        # Si no tenemos brew, fallback directo a manual
        if not self.brew_path:
            self._add_repo(repo_name, source="manual")
            return
            
        # Verificar si ya existe en la configuración para evitar comprobaciones innecesarias
        if any(r["name"].lower() == repo_name.lower() for r in self.config["repos"]):
             self._add_repo(repo_name, source="manual") # _add_repo mostrará el mensaje de "ya existe"
             return
            
        # Validación previa del formato (owner/repo) para evitar llamadas API innecesarias
        if len(repo_name.split('/')) != 2:
             # Si el formato es inválido, dejamos que _add_repo maneje el error (mostrará alerta)
             self._add_repo(repo_name, source="manual")
             return
        # Ejecutar la búsqueda en un hilo separado para no bloquear la UI
        # (Aunque runModal ya retornó, es buena práctica si tarda unos segundos)
        def worker():
            # 1. Verificar si el repo existe realmente en GitHub (HEAD request)
            try:
                api_url = f"https://api.github.com/repos/{repo_name}"
                headers = {}
                if self.config.get("token"):
                    headers["Authorization"] = f"token {self.config['token']}"
                
                response = requests.head(api_url, headers=headers, timeout=5)
                if response.status_code == 404:
                    logging.info(f"Smart add: Repo '{repo_name}' not found on GitHub.")
                    # Dejamos que _add_repo maneje el error de UI
                    safe_dispatch_to_main_thread(self._add_repo, repo_name, "manual")
                    return
                elif response.status_code != 200:
                    logging.error(f"Smart add: Error checking repo existence: {response.status_code}")
            except Exception as e:
                logging.error(f"Smart add: Exception checking repo existence: {e}")

            # 2. Si existe, buscamos el Cask
            found_cask = self._find_cask_for_repo(repo_name)
            if found_cask:
                logging.info(f"Smart add: Found cask '{found_cask}' for repo '{repo_name}'")
                safe_dispatch_to_main_thread(self._add_repo, repo_name, "brew", found_cask)
            else:
                logging.info(f"Smart add: No cask found for '{repo_name}'. Adding manually.")
                safe_dispatch_to_main_thread(self._add_repo, repo_name, "manual")
        
        threading.Thread(target=worker, daemon=True).start()

    def _find_cask_for_repo(self, repo_name):
        """
        Busca si un repositorio tiene un Cask asociado usando comandos locales de brew.
        Esto evita descargar el JSON masivo de la API, previniendo picos de memoria.
        """
        if not self.brew_path:
            return None

        repo_url_pattern = f"github.com/{repo_name}".lower()
        short_name = repo_name.split('/')[-1]

        try:
            # 1. Buscar posibles candidatos con `brew search`
            # Usamos --cask para limitar a casks y el nombre corto del repo
            cmd_search = [self.brew_path, "search", "--cask", short_name]
            result_search = subprocess.run(cmd_search, capture_output=True, text=True)
            
            if result_search.returncode != 0:
                return None
                
            candidates = result_search.stdout.strip().split()
            
            # Filtrar candidatos vacíos o irrelevantes
            candidates = [c for c in candidates if c]
            
            if not candidates:
                return None

            # 2. Inspeccionar cada candidato con `brew info` para ver si coincide la URL
            # Hacemos esto en batch si es posible, o uno a uno. `brew info --json=v2` acepta múltiples args.
            cmd_info = [self.brew_path, "info", "--cask", "--json=v2"] + candidates
            result_info = subprocess.run(cmd_info, capture_output=True, text=True)
            
            if result_info.returncode != 0:
                return None
                
            info_data = json.loads(result_info.stdout)
            casks_data = info_data.get("casks", [])
            
            for cask in casks_data:
                homepage = (cask.get("homepage") or "").lower()
                url = (cask.get("url") or "").lower()
                token = cask.get("token")
                
                # Comprobamos si la URL del repo está en la homepage o en la url de descarga
                if repo_url_pattern in homepage or repo_url_pattern in url:
                    return token
                    
            return None
            
        except Exception as e:
            logging.error(f"Error finding cask for repo {repo_name} (local brew): {e}")
            return None

    def _process_brew_selection(self, selected_cask):
         try:
            api_url = f"https://formulae.brew.sh/api/cask/{selected_cask}.json"
            with self.session.get(api_url, timeout=10) as response:
                response.raise_for_status()
                info_json = response.json()
            
            repo_name = None
            github_regex = re.compile(r'github\.com/([^/]+/[^/\s"]+)')
            
            for key in ["verified", "homepage", "url"]:
                if repo_name: break
                url_string = ""
                if key == "verified":
                    url_string = info_json.get("url_specs", {}).get("verified", "")
                else:
                    url_string = info_json.get(key, "")
                if url_string:
                    match = github_regex.search(url_string)
                    if match: repo_name = match.group(1).replace('.git', '')
            
            if repo_name:
                self._add_repo(repo_name, source="brew", cask=selected_cask)
            else:
                self.show_alert(t['brewErrorTitle'], t['brewRepoNotFound'].format(app_name=selected_cask))
         except Exception as e:
            self.show_alert(t['error'], f"Could not get info for {selected_cask}: {e}")

    def _fetch_brew_casks_for_dialog(self, handler):
        try:
            result = subprocess.run([self.brew_path, "list", "--casks"], capture_output=True, text=True, check=True)
            cask_list = sorted(result.stdout.strip().split('\n'))
            safe_dispatch_to_main_thread(handler.updateBrewList_, cask_list)
        except Exception as e:
            logging.error(f"Could not get brew cask list: {e}")
            safe_dispatch_to_main_thread(handler.updateBrewList_, [])

    def install_brew_cask(self, cask_name):
        # 1. Mostrar notificación de inicio
        rumps.notification(
            title=t['installingTitle'],
            subtitle=t['installingMsg'].format(cask_name=cask_name),
            message="",
            sound=False
        )
        
        def worker():
            try:
                # 2. Ejecutar brew install --cask <name>
                # Usamos 'upgrade' por si ya está instalado pero desactualizado, o install si no.
                # 'brew install' también actualiza si está instalado.
                cmd = [self.brew_path, "install", "--cask", cask_name]
                
                # Ejecutamos y capturamos salida por si hay error
                result = subprocess.run(cmd, capture_output=True, text=True)
                
                if result.returncode == 0:
                    # Éxito
                    already_installed = "already installed" in result.stderr.lower() or "already installed" in result.stdout.lower()
                    
                    if already_installed:
                         msg = t['alreadyInstalled'].format(cask_name=cask_name)
                    else:
                         msg = t['installComplete'].format(cask_name=cask_name)
                         
                    rumps.notification(
                        title="GitHub Watcher",
                        subtitle=msg,
                        message="",
                    )
                    
                    # 3. Revelar la aplicación en Finder (solo si fue instalada/actualizada)
                    try:
                        # Obtener información del cask para conocer la aplicación instalada
                        info_cmd = [self.brew_path, "info", "--cask", cask_name, "--json=v2"]
                        info_result = subprocess.run(info_cmd, capture_output=True, text=True)
                        
                        if info_result.returncode == 0:
                            cask_info = json.loads(info_result.stdout)
                            
                            # Buscar el nombre de la aplicación en los artifacts
                            if cask_info and "casks" in cask_info and len(cask_info["casks"]) > 0:
                                artifacts = cask_info["casks"][0].get("artifacts", [])
                                
                                # Buscar el primer artifact de tipo "app"
                                for artifact in artifacts:
                                    if isinstance(artifact, dict) and "app" in artifact:
                                        app_names = artifact["app"]
                                        if isinstance(app_names, list) and len(app_names) > 0:
                                            app_name = app_names[0]
                                        elif isinstance(app_names, str):
                                            app_name = app_names
                                        else:
                                            continue
                                        
                                        # Construir la ruta de la aplicación
                                        app_path = f"/Applications/{app_name}"
                                        
                                        # Revelar la aplicación en Finder (sin abrirla)
                                        subprocess.run(["open", "-R", app_path], check=False)
                                        break
                    except Exception as reveal_error:
                        logging.warning(f"Could not reveal app in Finder: {reveal_error}")
                    
                else:
                    # Fallo
                    logging.error(f"Brew install failed: {result.stderr}")
                    rumps.notification(
                        title=t['error'],
                        subtitle=t['installFailed'].format(cask_name=cask_name),
                        message=result.stderr[:100], # Mostrar parte del error
                    )
            except Exception as e:
                logging.error(f"Exception installing cask: {e}")
                rumps.notification(
                    title=t['error'],
                    subtitle=t['installFailed'].format(cask_name=cask_name),
                    message=str(e),
                )
                
        threading.Thread(target=worker, daemon=True).start()
