const supportUpiId = 'ddumka102@okhdfcbank';
const supportPayeeName = 'Deepak Dumka';

/// A static UPI request: the supporter chooses the amount in their payment app.
Uri coffeePaymentUri() {
  const parameters = {
    'pa': supportUpiId,
    'pn': supportPayeeName,
    'cu': 'INR',
    'tn': 'Support Vybe',
  };
  return Uri(
    scheme: 'upi',
    host: 'pay',
    query: parameters.entries
        .map(
          (entry) =>
              '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
        )
        .join('&'),
  );
}
