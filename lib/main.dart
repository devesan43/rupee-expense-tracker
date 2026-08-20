import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExpenseTrackerApp());
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.light,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class TransactionModel {
  final int? id;
  final double amount;
  final String type;
  final String account;
  final String? toAccount;
  final String category;
  final String subCategory;
  final String date;
  final String description;

  TransactionModel({
    this.id,
    required this.amount,
    required this.type,
    required this.account,
    this.toAccount,
    required this.category,
    required this.subCategory,
    required this.date,
    required this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type,
      'account': account,
      'toAccount': toAccount,
      'category': category,
      'subCategory': subCategory,
      'date': date,
      'description': description,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      amount: map['amount'],
      type: map['type'],
      account: map['account'],
      toAccount: map['toAccount'],
      category: map['category'] ?? '',
      subCategory: map['subCategory'] ?? '',
      date: map['date'],
      description: map['description'] ?? '',
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('expenses_v4.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            account TEXT NOT NULL,
            toAccount TEXT,
            category TEXT,
            subCategory TEXT,
            date TEXT NOT NULL,
            description TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<int> insertTransaction(TransactionModel tx) async {
    final db = await instance.database;
    return await db.insert('transactions', tx.toMap());
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions', orderBy: 'id DESC');
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> addCustomCategory(String name, String type) async {
    final db = await instance.database;
    return await db.insert('categories', {'name': name, 'type': type});
  }

  Future<List<String>> getCustomCategories(String type) async {
    final db = await instance.database;
    final result = await db.query('categories', where: 'type = ?', whereArgs: [type]);
    return result.map((row) => row['name'] as String).toList();
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<TransactionModel> _allTransactions = [];
  List<TransactionModel> _filteredTransactions = [];

  String _timeframe = 'Daily';
  String _filterAccount = 'All';

  double _totalIncome = 0;
  double _totalExpense = 0;
  double _totalSavings = 0;
  double _totalCredit = 0;

  final List<String> _accounts = ['Cash', 'Bank Account', 'Credit Card'];
  final List<String> _types = ['Expense', 'Income', 'Savings', 'Credit', 'Transfer'];

  Map<String, List<String>> _categories = {
    'Expense': ['Food', 'Bills', 'Travel', 'Shopping', 'Health', 'Other'],
    'Income': ['Salary', 'Business', 'Investment', 'Gift', 'Other'],
    'Savings': ['Emergency Fund', 'FD', 'Mutual Funds', 'Gold'],
    'Credit': ['Personal Loan', 'Borrowed', 'Lent', 'Credit Card Debt'],
    'Transfer': ['Account Transfer'],
  };

  @override
  void initState() {
    super.initState();
    _loadCustomCategories();
    _refreshData();
  }

  Future<void> _loadCustomCategories() async {
    for (var type in ['Expense', 'Income', 'Savings', 'Credit']) {
      final custom = await DatabaseHelper.instance.getCustomCategories(type);
      if (custom.isNotEmpty) {
        setState(() {
          _categories[type]!.addAll(custom);
          _categories[type] = _categories[type]!.toSet().toList();
        });
      }
    }
  }

  Future<void> _refreshData() async {
    final data = await DatabaseHelper.instance.getAllTransactions();
    setState(() {
      _allTransactions = data;
      _applyFilters();
    });
  }

  void _applyFilters() {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final monthStr = DateFormat('yyyy-MM').format(now);
    final yearStr = DateFormat('yyyy').format(now);

    double inc = 0, exp = 0, sav = 0, cred = 0;

    List<TransactionModel> list = _allTransactions.where((tx) {
      if (_filterAccount != 'All' && tx.account != _filterAccount) return false;

      if (_timeframe == 'Daily' && !tx.date.startsWith(todayStr)) return false;
      if (_timeframe == 'Monthly' && !tx.date.startsWith(monthStr)) return false;
      if (_timeframe == 'Yearly' && !tx.date.startsWith(yearStr)) return false;

      return true;
    }).toList();

    for (var tx in list) {
      if (tx.type == 'Expense') exp += tx.amount;
      if (tx.type == 'Income') inc += tx.amount;
      if (tx.type == 'Savings') sav += tx.amount;
      if (tx.type == 'Credit') cred += tx.amount;
    }

    setState(() {
      _filteredTransactions = list;
      _totalIncome = inc;
      _totalExpense = exp;
      _totalSavings = sav;
      _totalCredit = cred;
    });
  }

  Future<void> _requestSMSPermissionAndScan() async {
    PermissionStatus status = await Permission.sms.status;

    if (!status.isGranted) {
      status = await Permission.sms.request();
    }

    if (status.isPermanentlyDenied) {
      if (mounted) {
        openAppSettings();
      }
      return;
    }

    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS permission denied. Enable it in App Info Settings.')),
        );
      }
      return;
    }

    // Permission granted - Query SMS
    final SmsQuery query = SmsQuery();
    final messages = await query.querySms(kinds: [SmsQueryKind.inbox], count: 50);

    final txRegex = RegExp(
      r'(?:debited|spent|paid|credited|received|sent)\s*(?:by|for|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]+)?)',
      caseSensitive: false,
    );

    int countParsed = 0;

    for (var msg in messages) {
      final body = msg.body ?? '';
      final match = txRegex.firstMatch(body);

      if (match != null) {
        final amtString = match.group(1)?.replaceAll(',', '') ?? '0';
        final amount = double.tryParse(amtString) ?? 0.0;

        if (amount > 0) {
          final isCredit = body.toLowerCase().contains('credited') || body.toLowerCase().contains('received');
          final autoType = isCredit ? 'Income' : 'Expense';

          String autoCat = 'Other';
          if (body.toLowerCase().contains('swiggy') || body.toLowerCase().contains('zomato')) {
            autoCat = 'Food';
          } else if (body.toLowerCase().contains('bill') || body.toLowerCase().contains('recharge')) {
            autoCat = 'Bills';
          } else if (body.toLowerCase().contains('uber') || body.toLowerCase().contains('ola')) {
            autoCat = 'Travel';
          }

          if (mounted) {
            countParsed++;
            bool shouldContinue = await _showSmsParsedDialog(amount, autoType, autoCat, body);
            if (!shouldContinue) break;
          }
        }
      }
    }

    if (countParsed == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bank transaction SMS found in recent inbox.')),
      );
    }

    await _refreshData();
  }

  Future<bool> _showSmsParsedDialog(double amount, String autoType, String autoCat, String rawText) async {
    String selectedType = autoType;
    String selectedCat = autoCat;
    String selectedAccount = 'Bank Account';

    final subCatController = TextEditingController();

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => StatefulBuilder(
            builder: (context, setDialogState) {
              List<String> currentCats = _categories[selectedType] ?? ['Other'];
              if (!currentCats.contains(selectedCat)) selectedCat = currentCats.first;

              return AlertDialog(
                title: const Text('Transaction Detected'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Amount: ₹$amount', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                      const SizedBox(height: 8),
                      Text(rawText, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const Divider(),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        onChanged: (val) => setDialogState(() => selectedType = val!),
                      ),
                      DropdownButtonFormField<String>(
                        value: selectedAccount,
                        decoration: const InputDecoration(labelText: 'Destination Account'),
                        items: _accounts.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                        onChanged: (val) => setDialogState(() => selectedAccount = val!),
                      ),
                      DropdownButtonFormField<String>(
                        value: selectedCat,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: currentCats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        onChanged: (val) => setDialogState(() => selectedCat = val!),
                      ),
                      TextField(
                        controller: subCatController,
                        decoration: const InputDecoration(labelText: 'Sub-Category (Optional)'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Skip / Ignore', style: TextStyle(color: Colors.red)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      await DatabaseHelper.instance.insertTransaction(
                        TransactionModel(
                          amount: amount,
                          type: selectedType,
                          account: selectedAccount,
                          category: selectedCat,
                          subCategory: subCatController.text.trim(),
                          date: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                          description: 'SMS Sync',
                        ),
                      );
                      if (mounted) Navigator.pop(ctx, true);
                    },
                    child: const Text('Add Entry'),
                  ),
                ],
              );
            },
          ),
        ) ??
        true;
  }

  void _showAddCategoryDialog() {
    final catController = TextEditingController();
    String targetType = 'Expense';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Add Custom Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: targetType,
                decoration: const InputDecoration(labelText: 'Module Type'),
                items: ['Expense', 'Income', 'Savings', 'Credit'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (val) => setModalState(() => targetType = val!),
              ),
              TextField(
                controller: catController,
                decoration: const InputDecoration(labelText: 'Category Name'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final text = catController.text.trim();
                if (text.isNotEmpty) {
                  await DatabaseHelper.instance.addCustomCategory(text, targetType);
                  await _loadCustomCategories();
                  if (mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Save Category'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTransactionDialog() {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final subCatController = TextEditingController();

    String selectedType = 'Expense';
    String selectedAccount = 'Cash';
    String selectedToAccount = 'Bank Account';
    String selectedCat = _categories['Expense']!.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          List<String> currentCats = _categories[selectedType] ?? ['General'];
          if (!currentCats.contains(selectedCat)) selectedCat = currentCats.first;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New Entry', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                    items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) {
                      setModalState(() {
                        selectedType = val!;
                        selectedCat = _categories[selectedType]!.first;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedAccount,
                          decoration: InputDecoration(
                            labelText: selectedType == 'Transfer' ? 'From' : 'Account',
                            border: const OutlineInputBorder(),
                          ),
                          items: _accounts.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                          onChanged: (val) => setModalState(() => selectedAccount = val!),
                        ),
                      ),
                      if (selectedType == 'Transfer') ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedToAccount,
                            decoration: const InputDecoration(labelText: 'To', border: OutlineInputBorder()),
                            items: _accounts.where((a) => a != selectedAccount).map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                            onChanged: (val) => setModalState(() => selectedToAccount = val!),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (selectedType != 'Transfer') ...[
                    DropdownButtonFormField<String>(
                      value: selectedCat,
                      decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                      items: currentCats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) => setModalState(() => selectedCat = val!),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: subCatController,
                      decoration: const InputDecoration(labelText: 'Sub-Category (Optional)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount (₹)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor),
                      onPressed: () async {
                        final amt = double.tryParse(amountController.text) ?? 0.0;
                        if (amt > 0) {
                          await DatabaseHelper.instance.insertTransaction(
                            TransactionModel(
                              amount: amt,
                              type: selectedType,
                              account: selectedAccount,
                              toAccount: selectedType == 'Transfer' ? selectedToAccount : null,
                              category: selectedType == 'Transfer' ? 'Transfer' : selectedCat,
                              subCategory: subCatController.text.trim(),
                              date: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                              description: descController.text.trim(),
                            ),
                          );
                          await _refreshData();
                          if (mounted) Navigator.pop(ctx);
                        }
                      },
                      child: const Text('Save Entry', style: TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(String title, String amount, Color color, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 4),
              Text('₹$amount', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Expense': return Colors.red;
      case 'Income': return Colors.green;
      case 'Savings': return Colors.blue;
      case 'Credit': return Colors.orange;
      default: return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.sms),
            tooltip: 'Fetch SMS Transactions',
            onPressed: _requestSMSPermissionAndScan,
          ),
          IconButton(
            icon: const Icon(Icons.category),
            tooltip: 'Add Custom Category',
            onPressed: _showAddCategoryDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['Daily', 'Monthly', 'Yearly', 'All'].map((t) {
                final isSelected = _timeframe == t;
                return ChoiceChip(
                  label: Text(t),
                  selected: isSelected,
                  onSelected: (val) {
                    setState(() {
                      _timeframe = t;
                      _applyFilters();
                    });
                  },
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _buildSummaryCard('Income (+)', _totalIncome.toStringAsFixed(0), Colors.green, Icons.arrow_downward),
                _buildSummaryCard('Expense (-)', _totalExpense.toStringAsFixed(0), Colors.red, Icons.arrow_upward),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _buildSummaryCard('Savings', _totalSavings.toStringAsFixed(0), Colors.blue, Icons.savings),
                _buildSummaryCard('Credit / Loans', _totalCredit.toStringAsFixed(0), Colors.orange, Icons.credit_card),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                const Text('Account Filter: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _filterAccount,
                    items: ['All', 'Cash', 'Bank Account', 'Credit Card'].map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                    onChanged: (val) {
                      setState(() {
                        _filterAccount = val!;
                        _applyFilters();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _filteredTransactions.isEmpty
                ? const Center(child: Text('No transactions match current filters.'))
                : ListView.builder(
                    itemCount: _filteredTransactions.length,
                    itemBuilder: (ctx, index) {
                      final tx = _filteredTransactions[index];
                      final isTransfer = tx.type == 'Transfer';
                      final color = _getTypeColor(tx.type);

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.1),
                            child: Icon(
                              isTransfer ? Icons.swap_horiz : Icons.account_balance_wallet,
                              color: color,
                            ),
                          ),
                          title: Text(
                            isTransfer
                                ? 'Transfer: ${tx.account} ➔ ${tx.toAccount}'
                                : '${tx.category}${tx.subCategory.isNotEmpty ? ' (${tx.subCategory})' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('${tx.account} • ${tx.date}\n${tx.description}'),
                          isThreeLine: tx.description.isNotEmpty,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₹${tx.amount.toStringAsFixed(2)}',
                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.grey, size: 20),
                                onPressed: () async {
                                  if (tx.id != null) {
                                    await DatabaseHelper.instance.deleteTransaction(tx.id!);
                                    await _refreshData();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTransactionDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Entry'),
      ),
    );
  }
}
