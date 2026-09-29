import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/protocol_config.dart';
import '../models/bluetooth_models.dart';

/// Persistencia local: protocolo, transporte elegido y último asador.
class SettingsRepository {
  SettingsRepository([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const _kProtocol = 'protocol_config_v1';
  static const _kTransport = 'transport_kind';
  static const _kLastId = 'last_device_id';
  static const _kLastName = 'last_device_name';
  static const _kDirFlip = 'direction_label_flipped';

  Future<ProtocolConfig> loadProtocol() async {
    final raw = await _prefs.getString(_kProtocol);
    if (raw == null) return const ProtocolConfig();
    try {
      return ProtocolConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ProtocolConfig();
    }
  }

  Future<void> saveProtocol(ProtocolConfig c) =>
      _prefs.setString(_kProtocol, jsonEncode(c.toJson()));

  Future<TransportKind?> loadTransport() async {
    final raw = await _prefs.getString(_kTransport);
    for (final k in TransportKind.values) {
      if (k.name == raw) return k;
    }
    return null;
  }

  Future<void> saveTransport(TransportKind k) => _prefs.setString(_kTransport, k.name);

  Future<BtDevice?> loadLastDevice(TransportKind kind) async {
    final id = await _prefs.getString('${_kLastId}_${kind.name}');
    if (id == null) return null;
    final name = await _prefs.getString('${_kLastName}_${kind.name}');
    return BtDevice(id: id, name: name, kind: kind, bonded: true);
  }

  Future<void> saveLastDevice(BtDevice d) async {
    await _prefs.setString('${_kLastId}_${d.kind.name}', d.id);
    if (d.name != null) await _prefs.setString('${_kLastName}_${d.kind.name}', d.name!);
  }

  Future<bool> loadDirectionFlipped() async => await _prefs.getBool(_kDirFlip) ?? false;

  Future<void> saveDirectionFlipped(bool v) => _prefs.setBool(_kDirFlip, v);
}
