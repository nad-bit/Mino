import threading
from AppKit import NSObject

# =========================================================================
# Clase Handler para el Slider (NUEVO)
# =========================================================================
class SliderHandler(NSObject):
    # Eliminamos init personalizado para evitar problemas con super() y objc.super
    # Configuramos las propiedades manualmente después de la instanciación
    
    def sliderChanged_(self, sender):
        value = int(sender.intValue())
        if value == 1:
            self.label.setStringValue_(f"1 {self.t['unitHour']}")
        else:
            self.label.setStringValue_(f"{value} {self.t['hours']}")

# =========================================================================
# Clase Handler para el Diálogo Unificado de Añadir Repo (NUEVO)
# =========================================================================
class AddRepoHandler(NSObject):
    # Propiedades que se asignarán manualmente
    # self.input_field
    # self.brew_popup
    # self.app_ref (referencia a la app para llamar a fetch)
    # self.alert (referencia al NSAlert)
    # self.t (diccionario de traducciones)
    
    def radioChanged_(self, sender):
        selected_tag = sender.tag()
        if selected_tag == 1: # Manual
            self.input_field.setHidden_(False)
            self.brew_popup.setHidden_(True)
            if hasattr(self, 'alert') and hasattr(self, 't'):
                self.alert.setInformativeText_(self.t['enterRepoMsg'])
        elif selected_tag == 2: # Brew
            self.input_field.setHidden_(True)
            self.brew_popup.setHidden_(False)
            if hasattr(self, 'alert') and hasattr(self, 't'):
                self.alert.setInformativeText_(self.t['addFromBrew'])
            # Trigger fetch si está vacío y es la primera vez que se muestra
            if self.brew_popup.numberOfItems() <= 1: # Solo tiene el placeholder o loading
                 # Lanzamos el fetch en background
                 threading.Thread(target=self.app_ref._fetch_brew_casks_for_dialog, args=(self,), daemon=True).start()

    def updateBrewList_(self, cask_list):
        # Este método será llamado desde el hilo principal
        self.brew_popup.removeAllItems()
        if cask_list:
            # Usamos self.t para obtener la traducción correcta
            placeholder = self.t.get('selectCaskPlaceholder', "--- Select ---") if hasattr(self, 't') else "--- Select ---"
            self.brew_popup.addItemsWithTitles_([placeholder] + cask_list)
            self.brew_popup.setEnabled_(True)
        else:
            self.brew_popup.addItemsWithTitles_(["No casks found"])
            self.brew_popup.setEnabled_(False)
