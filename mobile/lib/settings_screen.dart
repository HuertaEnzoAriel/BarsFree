import 'package:flutter/material.dart';

import 'settings_service.dart';

/// Pantalla de configuracion. Para sumar una opcion, agrega otra fila a la lista.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuracion')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (_, _) => ListView(
          children: [
            const _Section('Al leer un codigo'),
            SwitchListTile(
              secondary: const Icon(Icons.vibration),
              title: const Text('Vibracion'),
              subtitle: const Text('Vibra al leer un codigo'),
              value: settings.vibration,
              onChanged: (v) => settings.vibrationEnabled = v,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.volume_up),
              title: const Text('Sonido'),
              subtitle: const Text('Reproduce un beep al leer un codigo'),
              value: settings.sound,
              onChanged: (v) => settings.soundEnabled = v,
            ),
            const _Section('Envio a la PC'),
            SwitchListTile(
              secondary: const Icon(Icons.keyboard_return),
              title: const Text('Enviar (Enter)'),
              subtitle: const Text(
                'Pulsa Enter en la PC despues de escribir el codigo. '
                'Si lo desactivas, solo se escribe el codigo.',
              ),
              value: settings.sendKey,
              onChanged: (v) => settings.sendKeyEnabled = v,
            ),
            // Nuevas opciones: agregalas aqui, por ejemplo otra seccion
            // const _Section('Otra seccion'), SwitchListTile(...)
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
