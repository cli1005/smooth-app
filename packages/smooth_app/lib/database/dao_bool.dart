import 'package:hive_flutter/hive_flutter.dart';
import 'package:smooth_app/database/abstract_dao.dart';
import 'package:smooth_app/database/local_database.dart';

/// Where we store boolean.
class DaoBool extends AbstractDao {
  DaoBool(final LocalDatabase localDatabase) : super(localDatabase);

  static const String _hiveBoxName = 'boolean';

  @override
  Future<void> init() async => Hive.openBox<bool>(_hiveBoxName);

  @override
  void registerAdapter() {}

  Box<bool> _getBox() => Hive.box<bool>(_hiveBoxName);

  bool? get(final String key) => _getBox().get(key);

  Future<void> put(final String key, final bool? value) async =>
      value == null ? _getBox().delete(key) : _getBox().put(key, value);
}
