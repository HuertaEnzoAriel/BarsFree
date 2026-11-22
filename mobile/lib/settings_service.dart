import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ajustes del usuario, guardados en el telefono.
///
/// Para agregar una opcion nueva:
///   1. Declarala aqui como un campo con su valor por defecto (ver [vibration]).
///   2. Cargala en [load] y guardala en un setter con [_setBool].
///   3. Agrega su fila en `settings_screen.dart`.
class SettingsService extends ChangeNotifier {
  SharedPreferences? _prefs;

  // --- Opciones ---------------------------------------------------------
  bool vibration = true;
  bool sound = true;
  bool sendKey = true; // pulsar Enter en la PC despues del codigo

  set vibrationEnabled(bool v) => _setBool('vibration', v, () => vibration = v);
  set soundEnabled(bool v) => _setBool('sound', v, () => sound = v);
  set sendKeyEnabled(bool v) => _setBool('sendKey', v, () => sendKey = v);

  // --- Persistencia -----------------------------------------------------
  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    vibration = p.getBool('vibration') ?? vibration;
    sound = p.getBool('sound') ?? sound;
    sendKey = p.getBool('sendKey') ?? sendKey;
    notifyListeners();
  }

  void _setBool(String key, bool value, VoidCallback apply) {
    apply();
    notifyListeners();
    _prefs?.setBool(key, value);
  }
}
