import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExpenseTrackerApp());
}

class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rupee Expense Tracker',
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
  final String type; // Expense, Income, Savings, Credit, Transfer
  final String account; // Bank, Credit Card, Cash
  final String? toAccount; // For transfers
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
    _database = await _initDB('expenses_v2.db');
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
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<TransactionModel> _allTransactions = [];
  List<TransactionModel> _filteredTransactions = [];

  String _filterTimeframe = 'All'; // All, Daily, Monthly, Yearly
  String _filterAccount = 'All'; // All, Bank, Credit Card, Cash
  String _filterType = 'All'; // All, Expense, Income, Savings, Credit, Transfer

  double _totalExpense = 0.0;
  double _totalIncome = 0.0;
  double _totalSavings = 0.0;
  double _totalCredit = 0.0;

  final List<String> _accounts = ['Bank', 'Credit Card', 'Cash'];
  final List<String> _types = ['Expense', 'Income', 'Savings', 'Credit', 'Transfer'];

  final Map<String, List<String>> _defaultCategories = {
    'Expense': ['Food', 'Bills', 'Travel', 'Shopping', 'Health', 'Other'],
    'Income': ['Salary', 'Business', 'Investment', 'Gift', 'Other'],
    'Savings': ['Fixed Deposit', 'Mutual Funds', 'Gold', 'Emergency Fund'],
    'Credit': ['Personal Loan', 'Credit Card Bill', 'Borrowed', 'Lent'],
    'Transfer': ['Account Transfer'],
  };

  @override
  void initState() {
    super.initState();
    _refreshData();
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

    double exp = 0, inc = 0, sav = 0, cred = 0;

    List<TransactionModel> list = _allTransactions.where((tx) {
      if (_filterAccount != 'All' && tx.account != _filterAccount) return false;
      if (_filterType != 'All' && tx.type != _filterType) return false;

      if (_filterTimeframe == 'Daily' && !tx.date.startsWith(todayStr)) return false;
      if (_filterTimeframe == 'Monthly' && !tx.date.startsWith(monthStr)) return false;
      if (_filterTimeframe == 'Yearly' && !tx.date.startsWith(yearStr)) return false;

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
      _totalExpense = exp;
      _totalIncome = inc;
      _totalSavings = sav;
      _totalCredit = cred;
    });
  }

  void _showAddTransactionDialog() {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final subCatController = TextEditingController();

    String selectedType = 'Expense';
    String selectedAccount = 'Bank';
    String selectedToAccount = 'Cash';
    String selectedCategory = 'Food';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          List<String> categories = _defaultCategories[selectedType] ?? ['General'];
          if (!categories.contains(selectedCategory)) {
            selectedCategory = categories.first;
          }

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
                  const Text('Add Transaction', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                    items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) {
                      setModalState(() {
                        selectedType = val!;
                        selectedCategory = _defaultCategories[selectedType]!.first;
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
                            labelText: selectedType == 'Transfer' ? 'From Account' : 'Account',
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
                            decoration: const InputDecoration(labelText: 'To Account', border: OutlineInputBorder()),
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
                      value: selectedCategory,
                      decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                      items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (val) => setModalState(() => selectedCategory = val!),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: subCatController,
                      decoration: const InputDecoration(labelText: 'Sub Category (Optional)', border: OutlineInputBorder()),
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
                              category: selectedType == 'Transfer' ? 'Transfer' : selectedCategory,
                              subCategory: subCatController.text.trim(),
                              date: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                              description: descController.text.trim(),
                            ),
                          );
                          await _refreshData();
                          if (mounted) Navigator.pop(ctx);
                        }
                      },
                      child: const Text('Save Transaction', style: TextStyle(color: Colors.white, fontSize: 16)),
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
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 5),
              Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 5),
              Text('₹$amount', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
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

  @style
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
        title: const Text('Rupee Expense Tracker', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Summary Cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                _buildSummaryCard('Income', _totalIncome.toStringAsFixed(0), Colors.green, Icons.arrow_downward),
                _buildSummaryCard('Expense', _totalExpense.toStringAsFixed(0), Colors.red, Icons.arrow_upward),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _buildSummaryCard('Savings', _totalSavings.toStringAsFixed(0), Colors.blue, Icons.savings),
                _buildSummaryCard('Credit/Loans', _totalCredit.toStringAsFixed(0), Colors.orange, Icons.credit_card),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Filters Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _filterTimeframe,
                    items: ['All', 'Daily', 'Monthly', 'Yearly']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) {
                      _filterTimeframe = val!;
                      _applyFilters();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _filterAccount,
                    items: ['All', 'Bank', 'Credit Card', 'Cash']
                        .map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                    onChanged: (val) {
                      _filterAccount = val!;
                      _applyFilters();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _filterType,
                    items: ['All', 'Expense', 'Income', 'Savings', 'Credit', 'Transfer']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) {
                      _filterType = val!;
                      _applyFilters();
                    },
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // Transactions List
          Expanded(
            child: _filteredTransactions.isEmpty
                ? const Center(child: Text('No transactions match the selected filters.'))
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
