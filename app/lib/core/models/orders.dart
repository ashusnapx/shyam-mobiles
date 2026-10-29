import 'shopping.dart';

enum OrderStatus {
  pendingPayment('pending_payment', 'Awaiting payment'),
  confirmed('confirmed', 'Confirmed'),
  packed('packed', 'Packed'),
  shipped('shipped', 'Shipped'),
  delivered('delivered', 'Delivered'),
  cancelled('cancelled', 'Cancelled'),
  refunded('refunded', 'Refunded');

  const OrderStatus(this.value, this.label);
  final String value;
  final String label;

  static OrderStatus parse(String v) => values.firstWhere((s) => s.value == v);
}

enum PaymentMethod {
  razorpay('razorpay', 'Pay online'),
  cod('cod', 'Cash on delivery');

  const PaymentMethod(this.value, this.label);
  final String value;
  final String label;

  static PaymentMethod parse(String v) => values.firstWhere((s) => s.value == v);
}

enum PaymentStatus {
  pending('pending', 'Pending'),
  paid('paid', 'Paid'),
  failed('failed', 'Failed'),
  refunded('refunded', 'Refunded');

  const PaymentStatus(this.value, this.label);
  final String value;
  final String label;

  static PaymentStatus parse(String v) => values.firstWhere((s) => s.value == v);
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.productName,
    required this.variantName,
    required this.unitPricePaise,
    required this.qty,
    this.productId,
    this.variantId,
    this.imagePath,
    this.imeis = const [],
  });

  final String id;
  final String? productId;
  final String? variantId;
  final String productName;
  final String variantName;
  final String? imagePath;
  final int unitPricePaise;
  final int qty;
  final List<String> imeis;

  int get lineTotalPaise => unitPricePaise * qty;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        id: j['id'],
        productId: j['product_id'],
        variantId: j['variant_id'],
        productName: j['product_name'],
        variantName: j['variant_name'],
        imagePath: j['image_path'],
        unitPricePaise: j['unit_price_paise'],
        qty: j['qty'],
        imeis: [...(j['imeis'] as List? ?? const [])].cast<String>(),
      );
}

class OrderEvent {
  const OrderEvent({required this.status, required this.createdAt, this.note});

  final OrderStatus status;
  final String? note;
  final DateTime createdAt;

  factory OrderEvent.fromJson(Map<String, dynamic> j) => OrderEvent(
        status: OrderStatus.parse(j['status']),
        note: j['note'],
        createdAt: DateTime.parse(j['created_at']),
      );
}

/// Loaded by `orders.select('*, items:order_items(*), events:order_events(*)')`.
/// `items`/`events` are empty when the query didn't embed them.
class Order {
  const Order({
    required this.id,
    required this.number,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.subtotalPaise,
    required this.deliveryFeePaise,
    required this.totalPaise,
    required this.address,
    required this.createdAt,
    this.userId,
    this.razorpayOrderId,
    this.courier,
    this.trackingNumber,
    this.reservedUntil,
    this.items = const [],
    this.events = const [],
  });

  final String id;
  final String number;
  final String? userId;
  final OrderStatus status;
  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final int subtotalPaise;
  final int deliveryFeePaise;
  final int totalPaise;
  final Address address; // snapshot; its id is null
  final String? razorpayOrderId;
  final String? courier;
  final String? trackingNumber;
  final DateTime? reservedUntil;
  final DateTime createdAt;
  final List<OrderItem> items;
  final List<OrderEvent> events; // oldest first

  bool get canCancel => status == OrderStatus.pendingPayment || status == OrderStatus.confirmed;

  /// Unpaid online order still inside its stock hold: the customer can retry payment.
  bool get canRetryPayment =>
      status == OrderStatus.pendingPayment &&
      paymentMethod == PaymentMethod.razorpay &&
      (reservedUntil?.isAfter(DateTime.now()) ?? false);

  bool get needsRefund => status == OrderStatus.cancelled && paymentStatus == PaymentStatus.paid;

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id'],
        number: j['number'],
        userId: j['user_id'],
        status: OrderStatus.parse(j['status']),
        paymentMethod: PaymentMethod.parse(j['payment_method']),
        paymentStatus: PaymentStatus.parse(j['payment_status']),
        subtotalPaise: j['subtotal_paise'],
        deliveryFeePaise: j['delivery_fee_paise'],
        totalPaise: j['total_paise'],
        address: Address.fromJson(Map<String, dynamic>.from(j['address'])),
        razorpayOrderId: j['razorpay_order_id'],
        courier: j['courier'],
        trackingNumber: j['tracking_number'],
        reservedUntil: j['reserved_until'] == null ? null : DateTime.parse(j['reserved_until']),
        createdAt: DateTime.parse(j['created_at']),
        items: [for (final i in (j['items'] as List? ?? const [])) OrderItem.fromJson(i)],
        events: [for (final e in (j['events'] as List? ?? const [])) OrderEvent.fromJson(e)]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );
}

enum RepairStatus {
  requested('requested', 'Requested'),
  confirmed('confirmed', 'Confirmed'),
  inProgress('in_progress', 'In repair'),
  ready('ready', 'Ready for pickup'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const RepairStatus(this.value, this.label);
  final String value;
  final String label;

  bool get isOpen => this != completed && this != cancelled;

  static RepairStatus parse(String v) => values.firstWhere((s) => s.value == v);
}

enum RepairSlot {
  morning('morning', 'Morning', '10 am – 1 pm'),
  afternoon('afternoon', 'Afternoon', '1 pm – 5 pm'),
  evening('evening', 'Evening', '5 pm – 9 pm');

  const RepairSlot(this.value, this.label, this.hours);
  final String value;
  final String label;
  final String hours;

  static RepairSlot parse(String v) => values.firstWhere((s) => s.value == v);
}

enum RepairIssue {
  screen('screen', 'Screen'),
  battery('battery', 'Battery'),
  charging('charging', 'Charging'),
  camera('camera', 'Camera'),
  audio('audio', 'Speaker / mic'),
  waterDamage('water_damage', 'Water damage'),
  software('software', 'Software'),
  other('other', 'Other');

  const RepairIssue(this.value, this.label);
  final String value;
  final String label;

  static RepairIssue parse(String v) => values.firstWhere((s) => s.value == v);
}

class RepairBooking {
  const RepairBooking({
    required this.id,
    required this.number,
    required this.deviceBrand,
    required this.deviceModel,
    required this.issue,
    required this.preferredDate,
    required this.slot,
    required this.contactPhone,
    required this.status,
    required this.createdAt,
    this.userId,
    this.description = '',
    this.quotePaise,
    this.adminNote,
  });

  final String id;
  final String number;
  final String? userId;
  final String deviceBrand;
  final String deviceModel;
  final RepairIssue issue;
  final String description;
  final DateTime preferredDate; // date only
  final RepairSlot slot;
  final String contactPhone;
  final RepairStatus status;
  final int? quotePaise;
  final String? adminNote;
  final DateTime createdAt;

  bool get canCancel => status == RepairStatus.requested || status == RepairStatus.confirmed;

  factory RepairBooking.fromJson(Map<String, dynamic> j) => RepairBooking(
        id: j['id'],
        number: j['number'],
        userId: j['user_id'],
        deviceBrand: j['device_brand'],
        deviceModel: j['device_model'],
        issue: RepairIssue.parse(j['issue']),
        description: j['description'] ?? '',
        preferredDate: DateTime.parse(j['preferred_date']),
        slot: RepairSlot.parse(j['slot']),
        contactPhone: j['contact_phone'],
        status: RepairStatus.parse(j['status']),
        quotePaise: j['quote_paise'],
        adminNote: j['admin_note'],
        createdAt: DateTime.parse(j['created_at']),
      );
}
