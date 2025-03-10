import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:openfoodfacts/model/Product.dart';
import 'package:smooth_app/data_models/product_list.dart';
import 'package:smooth_app/database/abstract_dao.dart';
import 'package:smooth_app/database/dao_product.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/services/smooth_services.dart';

/// "Total size" fake value for lists that are not partial/paged.
const int _uselessTotalSizeValue = 0;

/// An immutable barcode list; e.g. my search yesterday about "Nutella"
class _BarcodeList {
  const _BarcodeList(
    this.timestamp,
    this.barcodes,
    this.totalSize,
  );

  _BarcodeList.now(final List<String> barcodes)
      : this(
          LocalDatabase.nowInMillis(),
          barcodes,
          _uselessTotalSizeValue,
        );

  _BarcodeList.fromProductList(final ProductList productList)
      : this(
          LocalDatabase.nowInMillis(),
          productList.barcodes,
          productList.totalSize,
        );

  /// Freshness indicator: last time the list was updated.
  ///
  /// In milliseconds since epoch.
  /// Can be used to decide if the data is recent enough or deprecated.
  final int timestamp;
  final List<String> barcodes;

  /// Total size of server query results (or 0).
  final int totalSize;
}

/// Hive type adapter for [_BarcodeList]
class _BarcodeListAdapter extends TypeAdapter<_BarcodeList> {
  @override
  final int typeId = 0;

  @override
  _BarcodeList read(BinaryReader reader) {
    final int timestamp = reader.readInt();
    final List<String> barcodes = reader.readStringList();
    late int totalSize;
    try {
      totalSize = reader.readInt();
    } catch (e) {
      totalSize = _uselessTotalSizeValue;
    }
    return _BarcodeList(timestamp, barcodes, totalSize);
  }

  @override
  void write(BinaryWriter writer, _BarcodeList obj) {
    writer.writeInt(obj.timestamp);
    writer.writeStringList(obj.barcodes);
    writer.writeInt(obj.totalSize);
  }
}

class DaoProductList extends AbstractDao {
  DaoProductList(final LocalDatabase localDatabase) : super(localDatabase);

  static const String _hiveBoxName = 'barcodeLists';
  static const String _keySeparator = '::';

  @override
  Future<void> init() async => Hive.openBox<_BarcodeList>(_hiveBoxName);

  @override
  void registerAdapter() => Hive.registerAdapter(_BarcodeListAdapter());

  Box<_BarcodeList> _getBox() => Hive.box<_BarcodeList>(_hiveBoxName);

  _BarcodeList? _get(final ProductList productList) =>
      _getBox().get(_getKey(productList));

  int? getTimestamp(final ProductList productList) =>
      _get(productList)?.timestamp;

  // Why the "base64" part? Because of #753!
  // "HiveError: String keys need to be ASCII Strings with a max length of 255"
  // Encoding the parameter part in base64 makes us safe regarding ASCII.
  // As it's a list of keywords, there's a fairly high probability
  // that we'll be under the 255 character length.
  String _getKey(final ProductList productList) => '${productList.listType.key}'
      '$_keySeparator'
      '${base64.encode(utf8.encode(productList.getParametersKey()))}';

  static String getProductListParameters(final String key) {
    final int pos = key.indexOf(_keySeparator);
    if (pos < 0) {
      throw Exception('Unknown key format without "$_keySeparator": $key');
    }
    if (pos + _keySeparator.length == key.length) {
      return '';
    }
    final String tmp = key.substring(pos + _keySeparator.length);
    return utf8.decode(base64.decode(tmp));
  }

  static ProductListType getProductListType(final String key) {
    final int pos = key.indexOf(_keySeparator);
    if (pos < 0) {
      throw Exception('Unknown key format without "$_keySeparator": $key');
    }
    final String value = key.substring(0, pos);
    for (final ProductListType productListType in ProductListType.values) {
      if (productListType.key == value) {
        return productListType;
      }
    }
    throw Exception('Unknown product list type: "$value" from "$key"');
  }

  void _put(final String key, final _BarcodeList barcodeList) =>
      _getBox().put(key, barcodeList);

  void put(final ProductList productList) =>
      _put(_getKey(productList), _BarcodeList.fromProductList(productList));

  Future<bool> delete(final ProductList productList) async {
    final Box<_BarcodeList> box = _getBox();
    final String key = _getKey(productList);
    if (!box.containsKey(key)) {
      return false;
    }
    await box.delete(key);
    return true;
  }

  /// Loads the barcodes AND all the products.
  Future<void> get(final ProductList productList) async {
    final _BarcodeList? list = _get(productList);
    final List<String> barcodes = <String>[];
    final Map<String, Product> products = <String, Product>{};
    productList.totalSize = list?.totalSize ?? 0;
    if (list == null || list.barcodes.isEmpty) {
      productList.set(barcodes, products);
      return;
    }
    final DaoProduct daoProduct = DaoProduct(localDatabase);
    for (final String barcode in list.barcodes) {
      try {
        final Product? product = await daoProduct.get(barcode);
        if (product != null) {
          barcodes.add(barcode);
          products[barcode] = product;
        } else {
          Logs.e('unexpected: unknown product for $barcode');
        }
      } catch (e) {
        Logs.e('unexpected: unknown product for $barcode', ex: e);
      }
    }
    productList.set(barcodes, products);
  }

  /// Returns the number of barcodes quickly but without product check.
  int getLength(final ProductList productList) {
    final _BarcodeList? list = _get(productList);
    if (list == null || list.barcodes.isEmpty) {
      return 0;
    }
    return list.barcodes.length;
  }

  /// Moves a barcode to the end of the list.
  ///
  /// One barcode duplicate is potentially removed:
  /// * If the barcode was already there, it's moved to the end of the list.
  /// * If the barcode wasn't there, it's added to the end of the list.
  void push(
    final ProductList productList,
    final String barcode,
  ) {
    final _BarcodeList? list = _get(productList);
    final List<String> barcodes;
    if (list == null) {
      barcodes = <String>[];
    } else {
      barcodes = _getSafeBarcodeListCopy(list.barcodes);
    }
    barcodes.remove(barcode); // removes a potential duplicate
    barcodes.add(barcode);
    final _BarcodeList newList = _BarcodeList.now(barcodes);
    _put(_getKey(productList), newList);
  }

  void clear(final ProductList productList) {
    final _BarcodeList newList = _BarcodeList.now(<String>[]);
    _put(_getKey(productList), newList);
  }

  /// Adds or removes a barcode within a product list (depending on [include])
  ///
  /// Returns true if there was a change in the list.
  bool set(
    final ProductList productList,
    final String barcode,
    final bool include,
  ) {
    final _BarcodeList? list = _get(productList);
    final List<String> barcodes;
    if (list == null) {
      barcodes = <String>[];
    } else {
      barcodes = _getSafeBarcodeListCopy(list.barcodes);
    }
    if (barcodes.contains(barcode)) {
      if (include) {
        return false;
      }
      barcodes.remove(barcode);
    } else {
      if (!include) {
        return false;
      }
      barcodes.add(barcode);
    }
    final _BarcodeList newList = _BarcodeList.now(barcodes);
    _put(_getKey(productList), newList);
    return true;
  }

  Future<ProductList> rename(
    final ProductList initialList,
    final String newName,
  ) async {
    final ProductList newList = ProductList.user(newName);
    final _BarcodeList list = _get(initialList) ?? _BarcodeList.now(<String>[]);
    _put(_getKey(newList), list);
    await delete(initialList);
    await get(newList);
    return newList;
  }

  /// Exports a list - typically for debug purposes
  Future<Map<String, dynamic>> export(final ProductList productList) async {
    final Map<String, dynamic> result = <String, dynamic>{};
    final _BarcodeList? list = _get(productList);
    if (list == null) {
      return result;
    }
    final DaoProduct daoProduct = DaoProduct(localDatabase);
    for (final String barcode in list.barcodes) {
      late bool? present;
      try {
        final Product? product = await daoProduct.get(barcode);
        present = product != null;
      } catch (e) {
        present = null;
      }
      result[barcode] = present;
    }
    return result;
  }

  /// Returns the names of the user lists.
  ///
  /// Possibly restricted to the user lists that contain the given barcode.
  List<String> getUserLists({String? withBarcode}) {
    final List<String> result = <String>[];
    for (final dynamic key in _getBox().keys) {
      final String tmp = key.toString();
      final ProductListType productListType = getProductListType(tmp);
      if (productListType != ProductListType.USER) {
        continue;
      }
      if (withBarcode != null) {
        final _BarcodeList? barcodeList = _getBox().get(key);
        if (barcodeList == null ||
            !barcodeList.barcodes.contains(withBarcode)) {
          continue;
        }
      }
      result.add(getProductListParameters(tmp));
    }
    return result;
  }

  /// Returns a write-safe copy of [_BarcodeList] barcodes.
  ///
  /// cf. https://github.com/openfoodfacts/smooth-app/issues/1786
  /// As we're using hive, all the data are loaded at init time. And not
  /// systematically refreshed at each [get] call.
  /// Therefore, when we need a barcode list from [_BarcodeList] with the intent
  /// to add/remove a barcode to/from that list, we can avoid concurrency issues
  /// by copying the barcode list instead of reusing it.
  /// Example:
  /// BAD
  /// ```dart
  /// List<String> barcodes = _barcodeList.barcodes;
  /// barcodes.add('1234'); // dangerous if somewhere else we parse the list
  /// ```
  /// GOOD
  /// ```dart
  /// List<String> barcodes = _getSafeBarcodeListCopy(_barcodeList.barcodes);
  /// barcodes.add('1234'); // no risk at all
  /// ```
  List<String> _getSafeBarcodeListCopy(final List<String> barcodes) =>
      List<String>.from(barcodes);
}
