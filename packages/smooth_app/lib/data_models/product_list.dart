import 'package:openfoodfacts/model/Product.dart';

enum ProductListType {
  /// API search by [SearchTerms] keywords
  HTTP_SEARCH_KEYWORDS,

  /// API search for [CategoryProductQuery] category
  HTTP_SEARCH_CATEGORY,

  /// Current scan session; can be easily cleared by the end-user
  SCAN_SESSION,

  /// History of products seen by the end-user
  HISTORY,

  /// End-user product list
  USER,

  /// End-user as a contributor
  HTTP_USER_CONTRIBUTOR,

  /// End-user as an informer
  HTTP_USER_INFORMER,

  /// End-user as a photographer
  HTTP_USER_PHOTOGRAPHER,

  /// End-user for products to be completed
  HTTP_USER_TO_BE_COMPLETED,

  /// For products to be completed, all of them.
  HTTP_ALL_TO_BE_COMPLETED,
}

extension ProductListTypeExtension on ProductListType {
  String get key {
    switch (this) {
      case ProductListType.HTTP_SEARCH_KEYWORDS:
        return 'http/search/keywords';
      case ProductListType.HTTP_SEARCH_CATEGORY:
        return 'http/search/category';
      case ProductListType.SCAN_SESSION:
        return 'scan_session';
      case ProductListType.HTTP_USER_CONTRIBUTOR:
        return 'http/user/contributor';
      case ProductListType.HTTP_USER_INFORMER:
        return 'http/user/informer';
      case ProductListType.HTTP_USER_PHOTOGRAPHER:
        return 'http/user/photographer';
      case ProductListType.HTTP_USER_TO_BE_COMPLETED:
        return 'http/user/to_be_completed';
      case ProductListType.HTTP_ALL_TO_BE_COMPLETED:
        return 'http/all/to_be_completed';
      case ProductListType.HISTORY:
        return 'history';
      case ProductListType.USER:
        return 'user';
    }
  }
}

class ProductList {
  ProductList._({
    required this.listType,
    this.parameters = '',
    this.pageSize = 0,
    this.pageNumber = 0,
  });

  ProductList.keywordSearch(
    final String keywords, {
    required int pageSize,
    required int pageNumber,
  }) : this._(
          listType: ProductListType.HTTP_SEARCH_KEYWORDS,
          parameters: keywords,
          pageSize: pageSize,
          pageNumber: pageNumber,
        );

  ProductList.categorySearch(
    final String category, {
    required int pageSize,
    required int pageNumber,
  }) : this._(
          listType: ProductListType.HTTP_SEARCH_CATEGORY,
          parameters: category,
          pageSize: pageSize,
          pageNumber: pageNumber,
        );

  ProductList.contributor(
    final String userId, {
    required int pageSize,
    required int pageNumber,
  }) : this._(
          listType: ProductListType.HTTP_USER_CONTRIBUTOR,
          parameters: userId,
          pageSize: pageSize,
          pageNumber: pageNumber,
        );

  ProductList.informer(
    final String userId, {
    required int pageSize,
    required int pageNumber,
  }) : this._(
          listType: ProductListType.HTTP_USER_INFORMER,
          parameters: userId,
          pageSize: pageSize,
          pageNumber: pageNumber,
        );

  ProductList.photographer(
    final String userId, {
    required int pageSize,
    required int pageNumber,
  }) : this._(
          listType: ProductListType.HTTP_USER_PHOTOGRAPHER,
          parameters: userId,
          pageSize: pageSize,
          pageNumber: pageNumber,
        );

  ProductList.toBeCompleted(
    final String userId, {
    required int pageSize,
    required int pageNumber,
  }) : this._(
          listType: ProductListType.HTTP_USER_TO_BE_COMPLETED,
          parameters: userId,
          pageSize: pageSize,
          pageNumber: pageNumber,
        );

  ProductList.allToBeCompleted({
    required int pageSize,
    required int pageNumber,
  }) : this._(
          listType: ProductListType.HTTP_ALL_TO_BE_COMPLETED,
          pageSize: pageSize,
          pageNumber: pageNumber,
        );

  ProductList.history() : this._(listType: ProductListType.HISTORY);

  ProductList.scanSession() : this._(listType: ProductListType.SCAN_SESSION);

  ProductList.user(final String name)
      : this._(
          listType: ProductListType.USER,
          parameters: name,
        );

  final ProductListType listType;
  final String parameters;

  /// Page size at query time.
  final int? pageSize;

  /// Page number at query time.
  final int? pageNumber;

  /// "Total size" returned by the query.
  int totalSize = 0;

  final List<String> _barcodes = <String>[];
  final Map<String, Product> _products = <String, Product>{};

  List<String> get barcodes => _barcodes;

  bool isEmpty() => _barcodes.isEmpty;

  Product getProduct(final String barcode) => _products[barcode]!;

  void refresh(final Product product) {
    final String? barcode = product.barcode;
    if (barcode == null) {
      throw Exception('null barcode');
    }
    _products[barcode] = product;
  }

  /// Removes a barcode from the list
  ///
  /// Returns false if not already in the list
  /// Don't forget to update the database afterwards
  bool remove(final String barcode) {
    if (!_barcodes.contains(barcode)) {
      return false;
    }
    _barcodes.remove(barcode);
    _products.remove(barcode);
    return true;
  }

  /// Sets all products with the same order as the input list
  void setAll(final List<Product> products) {
    final List<String> barcodes = <String>[];
    final Map<String, Product> productMap = <String, Product>{};
    for (final Product product in products) {
      final String barcode = product.barcode!;
      barcodes.add(barcode);
      productMap[barcode] = product;
    }
    set(barcodes, productMap);
  }

  void set(
    final List<String> barcodes,
    final Map<String, Product> products,
  ) {
    _barcodes.clear();
    _products.clear();
    _products.addAll(products);
    _barcodes.addAll(barcodes);
  }

  List<Product> getList() {
    final List<Product> result = <Product>[];
    final Iterable<String> barcodes =
        _isReversed() ? _barcodes.reversed : _barcodes;
    for (final String barcode in barcodes) {
      final Product? product = _products[barcode];
      if (product == null) {
        throw Exception('no product for barcode $barcode');
      }
      result.add(product);
    }
    return result;
  }

  bool _isReversed() {
    switch (listType) {
      case ProductListType.HTTP_SEARCH_KEYWORDS:
      case ProductListType.HTTP_SEARCH_CATEGORY:
      case ProductListType.HTTP_USER_CONTRIBUTOR:
      case ProductListType.HTTP_USER_INFORMER:
      case ProductListType.HTTP_USER_PHOTOGRAPHER:
      case ProductListType.HTTP_USER_TO_BE_COMPLETED:
      case ProductListType.HTTP_ALL_TO_BE_COMPLETED:
      case ProductListType.USER:
        return false;
      case ProductListType.SCAN_SESSION:
      case ProductListType.HISTORY:
        return true;
    }
  }

  String getParametersKey() {
    switch (listType) {
      case ProductListType.SCAN_SESSION:
      case ProductListType.HISTORY:
      case ProductListType.USER:
        return parameters;
      case ProductListType.HTTP_SEARCH_KEYWORDS:
      case ProductListType.HTTP_SEARCH_CATEGORY:
      case ProductListType.HTTP_USER_CONTRIBUTOR:
      case ProductListType.HTTP_USER_INFORMER:
      case ProductListType.HTTP_USER_PHOTOGRAPHER:
      case ProductListType.HTTP_USER_TO_BE_COMPLETED:
      case ProductListType.HTTP_ALL_TO_BE_COMPLETED:
        return '$parameters,$pageSize,$pageNumber';
    }
  }
}
