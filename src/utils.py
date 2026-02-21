import subprocess
import math
from datetime import datetime, timezone
from typing import Optional, Tuple
from AppKit import NSObject

# =========================================================================
# Dispatcher de Obj-C (Mantenido)
# =========================================================================
class MainThreadDispatcher(NSObject):
    def execute_(self, *args): 
        obj = args[-1]
        function, f_args = obj
        function(*f_args)

_dispatcher_instance = MainThreadDispatcher.alloc().init()

def safe_dispatch_to_main_thread(function, *args):
    """Utiliza performSelector para ejecutar la función en el hilo principal."""
    data = (function, args)
    _dispatcher_instance.performSelectorOnMainThread_withObject_waitUntilDone_(
        'execute:', 
        data,
        False
    )

def get_macos_language():
    # === VERSIÓN LIMPIA DE get_macos_language (Mantenida) ===
    try:
        cmd = ["defaults", "read", "-g", "AppleLanguages"]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        lang_code = result.stdout.strip().split(',')[0].strip('(" \n').split('-')[0]
        return lang_code
    except (FileNotFoundError, subprocess.CalledProcessError, IndexError):
        return "en"

def get_release_age(date_string: Optional[str], t: dict) -> Tuple[str, float]:
    """Devuelve la edad de la release en el formato más apropiado (min, hr, días)."""
    if not date_string: 
        return "N/A", float('inf') 
        
    dt_object = datetime.fromisoformat(date_string.replace("Z", "+00:00"))
    release_timestamp = dt_object.timestamp()
    now_timestamp = datetime.now(timezone.utc).timestamp()
    seconds_diff = now_timestamp - release_timestamp
    
    if seconds_diff < 0:
        return "0 " + t['unitMin'], 0
    
    # Límite de 1 hora (3600 segundos)
    if seconds_diff < 3600:
        minutes = max(1, round(seconds_diff / 60))
        return f"{minutes} {t['unitMin']}", seconds_diff
    
    # Límite de 1 día (86400 segundos)
    elif seconds_diff < 86400:
        hours = max(1, math.floor(seconds_diff / 3600))
        hours_label = t['unitHour'] if hours == 1 else t.get('unitHoursPlural', t['unitHour'])
        return f"{hours} {hours_label}", seconds_diff
        
    # Un día o más (86400 segundos o más)
    else:
        days_float = seconds_diff / 86400
        days_count = max(1, math.floor(days_float)) # Trunca a 1, 2, 3... días
        
        # Lógica para singular/plural: si es 1 día, usa la clave unitDay.
        if days_count == 1:
            days_label = t['unitDay']
        else:
            days_label = t['days'] 
        
        return f"{days_count} {days_label}", seconds_diff

# =========================================================================
# Keychain Token Management
# =========================================================================
KEYCHAIN_SERVICE = "GitHub Watcher"
KEYCHAIN_ACCOUNT = "github_token"

def save_token_to_keychain(token: str) -> bool:
    """
    Save GitHub token to macOS Keychain securely.
    
    Args:
        token: The GitHub personal access token to save
        
    Returns:
        True if successful, False otherwise
    """
    try:
        import keyring
        keyring.set_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT, token)
        return True
    except Exception as e:
        import logging
        logging.error(f"Failed to save token to Keychain: {e}")
        return False

def get_token_from_keychain() -> Optional[str]:
    """
    Retrieve GitHub token from macOS Keychain.
    
    Returns:
        Token string if found, None otherwise
    """
    try:
        import keyring
        token = keyring.get_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT)
        return token
    except Exception as e:
        import logging
        logging.error(f"Failed to retrieve token from Keychain: {e}")
        return None

def delete_token_from_keychain() -> bool:
    """
    Remove GitHub token from macOS Keychain.
    
    Returns:
        True if successful, False otherwise
    """
    try:
        import keyring
        keyring.delete_password(KEYCHAIN_SERVICE, KEYCHAIN_ACCOUNT)
        return True
    except Exception as e:
        import logging
        logging.error(f"Failed to delete token from Keychain: {e}")
        return False
