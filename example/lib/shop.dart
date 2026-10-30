import 'package:deepdots_popups/deepdots_popups.dart';
import 'package:flutter/material.dart';

import 'lab.dart';
import 'main.dart';

const ink = Color(0xFF121726);
const labBg = Color(0xFF0F1214);
const labText = Color(0xFFC9CCD4);
const _swatch = Color(0xFFD6D4C9);

class Product {
  const Product(this.id, this.name, this.detail, this.price);

  final String id, name, detail;
  final int price;
}

const products = [
  Product('fjell-jacket', 'Fjell Jacket', 'Waterproof · M · Green', 89),
  Product('wool-beanie', 'Wool Beanie', 'One size · Grey', 24),
  Product('ull-socks', 'Ull Socks', '39–42', 12),
];

/// The shop: routes, cart and screens. Each screen is a named route; its name is what the plugin's
/// DeepdotsNavigatorObserver passes to setPath() (segments.path in DEV matches on it):
/// `/`, `/shop`, `/product/<id>`, `/cart`, `/checkout`, `/account`.
class Shop {
  Shop({required this.host, required this.navigator, required this.flash});

  final SdkHost host;
  final GlobalKey<NavigatorState> navigator;
  final void Function(String message) flash;
  final cart = ValueNotifier<List<Product>>([products[0], products[1]]);

  static String startRoute(String start) => switch (start) {
    'shop' => '/shop',
    'cart' => '/cart',
    'checkout' => '/checkout',
    'account' => '/account',
    _ => '/',
  };

  Route<void> route(String name) {
    final product = products.where((p) => '/product/${p.id}' == name).firstOrNull;
    const screens = {'/shop', '/cart', '/checkout', '/account'};
    final path = product != null ? name : (screens.contains(name) ? name : '/');
    final (title, body) = switch (path) {
      _ when product != null => (product.name, _ProductScreen(shop: this, product: product)),
      '/shop' => ('Shop', _ShopScreen(shop: this)),
      '/cart' => ('Cart', _CartScreen(shop: this)),
      '/checkout' => ('Checkout', _CheckoutScreen(shop: this)),
      '/account' => ('Account', _AccountScreen(shop: this)),
      _ => ('NORDLY', _HomeScreen(shop: this)),
    };
    return PageRouteBuilder<void>(
      settings: RouteSettings(name: path),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: Navigator.of(context).canPop() ? 4 : 16,
          title: Row(
            children: [
              if (Navigator.of(context).canPop())
                Semantics(
                  identifier: 'back',
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              Text(
                title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: ink),
              ),
            ],
          ),
        ),
        body: body,
      ),
    );
  }

  void push(String name) => navigator.currentState?.pushNamed(name);
  void tab(String name) => navigator.currentState?.pushNamedAndRemoveUntil(name, (_) => false);

  Widget tabBar(String current) {
    final root = _rootOf(current);
    Widget item(String label, IconData icon, String id, String route) {
      final selected = root == route;
      final color = selected ? Colors.blue : const Color(0xFF595959);
      return Expanded(
        child: Semantics(
          identifier: id,
          button: true,
          child: InkWell(
            onTap: () => tab(route),
            child: SizedBox(
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color),
                  Text(label, style: TextStyle(fontSize: 11, color: color)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFFF7F7F7),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder(
          valueListenable: cart,
          builder: (_, items, _) => Row(
            children: [
              item('Home', Icons.home, 'tab-home', '/'),
              item('Shop', Icons.shopping_bag, 'tab-shop', '/shop'),
              item('Cart (${items.length})', Icons.shopping_cart, 'tab-cart', '/cart'),
              item('Account', Icons.account_circle, 'tab-account', '/account'),
            ],
          ),
        ),
      ),
    );
  }

  String _rootOf(String route) => route.startsWith('/product/') ? '/shop' : (route == '/checkout' ? '/cart' : route);

  int get total => cart.value.fold(0, (sum, p) => sum + p.price);

  Future<void> rate(BuildContext context, Product product) async {
    final stars = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => _RateSheet(product: product),
    );
    if (stars == null) return;
    Lab.log('host', 'rate ${product.id} stars=$stars → triggerEvent(rate_product)');
    host.triggerEvent('rate_product');
  }
}

Widget primaryButton(String title, String id, VoidCallback? onPressed) => Semantics(
  identifier: id,
  child: FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(backgroundColor: ink, minimumSize: const Size.fromHeight(48)),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
  ),
);

Widget secondaryButton(String title, String id, VoidCallback onPressed) => Semantics(
  identifier: id,
  child: OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(foregroundColor: ink, minimumSize: const Size.fromHeight(48)),
    child: Text(title),
  ),
);

Widget _productRow(Product p, VoidCallback? onTap) => Semantics(
  identifier: 'product-${p.id}',
  child: InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: _swatch, borderRadius: BorderRadius.circular(8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(color: ink)),
                Text(p.detail, style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ),
          ),
          Text('${p.price},00 €', style: const TextStyle(color: ink)),
        ],
      ),
    ),
  ),
);

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('New season, same rain.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      const Text('Free shipping over 60 € · 30-day returns', style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 12),
      primaryButton('Shop new arrivals', 'home-shop', () => shop.tab('/shop')),
      const SizedBox(height: 20),
      const Text('Featured', style: TextStyle(fontWeight: FontWeight.w600)),
      for (final p in products.take(2)) _productRow(p, () => shop.push('/product/${p.id}')),
    ],
  );
}

class _ShopScreen extends StatelessWidget {
  const _ShopScreen({required this.shop});

  final Shop shop;

  // DeepdotsScrollListener reports the list's scroll % to the SDK (popups with a scroll trigger).
  @override
  Widget build(BuildContext context) => DeepdotsScrollListener(
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final p in products) _productRow(p, () => shop.push('/product/${p.id}'))],
    ),
  );
}

class _ProductScreen extends StatelessWidget {
  const _ProductScreen({required this.shop, required this.product});

  final Shop shop;
  final Product product;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Container(height: 240, color: _swatch),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(product.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            Text('${product.price},00 €'),
            Text(product.detail, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: primaryButton('Add to cart', 'add-to-cart', () {
                    shop.cart.value = [...shop.cart.value, product];
                    Lab.log('host', 'add to cart ${product.id} (cart ${shop.cart.value.length})');
                    shop.flash('Added to cart');
                  }),
                ),
                Expanded(child: secondaryButton('Rate', 'rate-product', () => shop.rate(context, product))),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

class _CartScreen extends StatelessWidget {
  const _CartScreen({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: shop.cart,
    builder: (_, items, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          identifier: 'cart-count',
          child: Text('${items.length} items', style: const TextStyle(color: Colors.black54)),
        ),
        for (final p in items) _productRow(p, null),
        const SizedBox(height: 12),
        primaryButton('Go to checkout', 'go-checkout', items.isEmpty ? null : () => shop.push('/checkout')),
      ],
    ),
  );
}

class _CheckoutScreen extends StatelessWidget {
  const _CheckoutScreen({required this.shop});

  final Shop shop;

  Future<void> _placeOrder(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Place order?'),
        content: Text('Total ${shop.total},00 €'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;
    shop.cart.value = [];
    Lab.log('host', 'order placed');
    shop.flash('Order placed');
    shop.tab('/');
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('Cart › Shipping › Payment', style: TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 12),
      Semantics(
        identifier: 'checkout-email',
        child: TextFormField(
          initialValue: 'qa+flutter@deepdots.dev',
          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        initialValue: '1 Test Street',
        decoration: const InputDecoration(labelText: 'Address', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('${shop.total},00 €', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      const SizedBox(height: 12),
      primaryButton('Place order', 'place-order', () => _placeOrder(context)),
    ],
  );
}

class _AccountScreen extends StatelessWidget {
  const _AccountScreen({required this.shop});

  final Shop shop;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        const Text('Test User', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ValueListenableBuilder(
          valueListenable: shop.host.initialized,
          builder: (_, initialized, _) => FutureBuilder(
            future: initialized ? DeepdotsPopups.getUserId() : Future.value(null),
            builder: (_, user) => Semantics(
              identifier: 'account-user-id',
              child: Text(
                'SDK user id: ${user.data ?? '—'}',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          ),
        ),
        const Divider(),
        const Text('Orders'),
        const Text('Addresses'),
        const Divider(),
        secondaryButton('Help', 'help-button', () {
          Lab.log('host', 'click help-button');
          shop.host.triggerClick('help-button');
        }),
      ],
    ),
  );
}

class _RateSheet extends StatefulWidget {
  const _RateSheet({required this.product});

  final Product product;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  int _stars = 4;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 14,
      children: [
        Text('Rate the ${widget.product.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        Row(
          spacing: 8,
          children: [
            for (var n = 1; n <= 5; n++)
              Semantics(
                identifier: 'star-$n',
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _stars = n),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: n == _stars ? ink : Colors.white,
                      foregroundColor: n == _stars ? Colors.white : ink,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('$n'),
                  ),
                ),
              ),
          ],
        ),
        primaryButton('Submit rating', 'submit-rating', () => Navigator.pop(context, _stars)),
        const SizedBox(height: 8),
      ],
    ),
  );
}
