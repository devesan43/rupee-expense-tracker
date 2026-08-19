import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:telephony/telephony.dart';

// Background SMS Handler
@pragma('vm:entry-point')
void backgrounSmsHandler(SmsMessage message) {
  debugPrint("Background SMS Received: ${message.body}");
  // Background processing logic handles auto-parsing when app is closed
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RupeeExpenseTrackerApp());
}

class RupeeExpenseTrackerApp extends StatelessWidget {
  const RupeeExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rupee Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final Telephony telephony = Telephony.instance;
  Database? _db;

  // Operational Balances
  double cashBalance = 3500.0;
  double bankBalance = 85000.0;
  double creditCardBalance = -12400.0;

  // Cumulative Categories
  Map<String, Map<String, double>> savingsCategories = {
    'Fixed Deposits': {'FD 1': 10.0, 'FD 2': 30.0},
    'Mutual Funds': {'Equity Fund A': 1000.0},
  };

  Map<String, Map<String, double>> liabilityCategories = {
    'Personal Loans': {'Loan 1': 30000.0, 'Friend Loan': 10000.0},
  };

  List<Map<String, dynamic>> transactions = [];

  @override
  void initState() {
    super.initState();
    _initDatabase();
    _initSmsListener();
  }

  Future<void> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'rupee_tracker.db'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount REAL,
            type TEXT,
            account TEXT,
            category TEXT,
            subCategory TEXT,
            date TEXT
          )
        ''');
      },
      version: 1,
    );
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    if (_db == null) return;
    final List<Map<String, dynamic>> maps = await _db!.query('transactions', orderBy: 'id DESC');
    setState(() {
      transactions = maps;
    });
  }

  void _initSmsListener() async {
    bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
    if (permissionsGranted == true) {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) {
          _processIncomingSms(message.body ?? "");
        },
        onBackgroundMessage: backgrounSmsHandler,
      );
    }
  }

  void _processIncomingSms(String smsBody) {
    // Regex matching Indian Rs / INR amounts
    final regExp = RegExp(r'(?:rs\.?|inr|₹)\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false);
    final match = regExp.firstMatch(smsBody);

    if (match != null) {
      String rawAmount = match.group(1)!.replaceAll(',', '');
      double amount = double.tryParse(rawAmount) ?? 0.0;
      bool isDebit = smsBody.toLowerCase().contains("debited") || smsBody.toLowerCase().contains("spent");

      _showTransactionPopup(amount, isDebit, smsBody);
    }
  }

  void _showTransactionPopup(double amount, bool isDebit, String rawSms) {
    String selectedCategory = isDebit ? 'Food & Dining' : 'Salary';
    String selectedSubCategory = isDebit ? 'Restaurant' : 'Monthly Credit';
    String selectedAccount = 'Bank Account';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(isDebit ? Icons.remove_circle : Icons.add_circle, color: isDebit ? Colors.red : Colors.green),
              const SizedBox(width: 8),
              Text(isDebit ? 'Debit Alert Detected' : 'Credit Alert Detected'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Amount: ₹${amount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text("SMS: \"$rawSms\"", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const Divider(),
                DropdownButtonFormField<String>(
                  value: selectedAccount,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: ['Cash', 'Bank Account', 'Credit Card'].map((acc) => DropdownMenuItem(value: acc, child: Text(acc))).toList(),
                  onChanged: (val) => selectedAccount = val!,
                ),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: (isDebit ? ['Food & Dining', 'Utilities', 'Shopping'] : ['Salary', 'Freelance', 'Dividends'])
                      .map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                  onChanged: (val) => selectedCategory = val!,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ignore / Skip', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                await _saveTransaction(amount, isDebit ? 'EXPENSE' : 'INCOME', selectedAccount, selectedCategory, selectedSubCategory);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Save Transaction'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveTransaction(double amount, String type, String account, String category, String subCategory) async {
    if (_db == null) return;
    await _db!.insert('transactions', {
      'amount': amount,
      'type': type,
      'account': account,
      'category': category,
      'subCategory': subCategory,
      'date': DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now()),
    });

    setState(() {
      if (type == 'EXPENSE') {
        if (account == 'Bank Account') bankBalance -= amount;
        if (account == 'Cash') cashBalance -= amount;
        if (account == 'Credit Card') creditCardBalance -= amount;
      } else {
        if (account == 'Bank Account') bankBalance += amount;
        if (account == 'Cash') cashBalance += amount;
      }
    });

    _loadTransactions();
  }

  double _getSavingsTotal() {
    double total = 0;
    savingsCategories.forEach((_, subMap) {
      subMap.forEach((_, val) => total += val);
    });
    return total;
  }

  double _getLiabilityTotal() {
    double total = 0;
    liabilityCategories.forEach((_, subMap) {
      subMap.forEach((_, val) => total += val);
    });
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rupee Expense Tracker', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E3A8A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Operational Overview Card
            Card(
              color: Colors.blue.shade50,
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Operational Balances', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Cash: ₹${cashBalance.toStringAsFixed(0)}'),
                        Text('Bank: ₹${bankBalance.toStringAsFixed(0)}'),
                        Text('CC Debt: ₹${creditCardBalance.abs().toStringAsFixed(0)}', style: const TextStyle(color: Colors.red)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Cumulative Separated Accounts
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cumulative Savings', style: TextStyle(fontSize: 12, color: Colors.green)),
                          Text('₹${_getSavingsTotal().toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cumulative Liabilities', style: TextStyle(fontSize: 12, color: Colors.orange)),
                          Text('₹${_getLiabilityTotal().toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Test Controls
            ElevatedButton.icon(
              onPressed: () => _processIncomingSms("Debited by Rs. 850.00 from Bank A/C XX4821 for Swiggy Food Order"),
              icon: const Icon(Icons.sms),
              label: const Text('Simulate Incoming Bank SMS'),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(45)),
            ),
            const SizedBox(height: 20),

            const Text('Recent Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            transactions.isEmpty
                ? const Center(child: Text('No transactions recorded yet.'))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final item = transactions[index];
                      bool isExpense = item['type'] == 'EXPENSE';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isExpense ? Colors.red.shade100 : Colors.green.shade100,
                          child: Icon(isExpense ? Icons.arrow_downward : Icons.arrow_upward, color: isExpense ? Colors.red : Colors.green),
                        ),
                        title: Text("${item['category']} (${item['account']})"),
                        subtitle: Text(item['date'] ?? ''),
                        trailing: Text(
                          "${isExpense ? '-' : '+'} ₹${item['amount']}",
                          style: TextStyle(fontWeight: FontWeight.bold, color: isExpense ? Colors.red : Colors.green),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
