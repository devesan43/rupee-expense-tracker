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
      title: 'Rupee Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green,
      ),
      home: const HomeScreen(),
    );
  }
}

class TransactionModel {
  final int? id;
  final double amount;
  final String category;
  final String date;
  final String description;
  final String type; // 'expense' or 'savings'

  TransactionModel({
    this.id,
    required this.amount,
    required this.category,
    required this.date,
    required this.description,
    required this.type,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'category': category,
      'date': date,
      'description': description,
      'type': type,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      amount: map['amount'],
      category: map['category'],
      date: map['date'],
      description: map['description'],
      type: map['type'],
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('expenses.db');
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
            category TEXT NOT NULL,
            date TEXT NOT NULL,
            description TEXT NOT NULL,
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
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SmsQuery _query = SmsQuery();
  List<TransactionModel> _transactions = [];
  double _totalExpenses = 0.0;
  double _totalSavings = 0.0;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    final data = await DatabaseHelper.instance.getAllTransactions();
    double expenses = 0.0;
    double savings = 0.0;

    for (var tx in data) {
      if (tx.type == 'expense') {
        expenses += tx.amount;
      } else {
        savings += tx.amount;
      }
    }

    setState(() {
      _transactions = data;
      _totalExpenses = expenses;
      _totalSavings = savings;
    });
  }

  Future<void> _scanSMS() async {
    var status = await Permission.sms.request();
    if (status.isGranted) {
      final messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 50,
      );

      final debitRegex = RegExp(
        r'(?:debited|spent|paid|sent)\s*(?:by|for|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]+)?)',
        caseSensitive: false,
      );

      int addedCount = 0;
      for (var msg in messages) {
        final body = msg.body ?? '';
        final match = debitRegex.firstMatch(body);
        if (match != null) {
          final amtString = match.group(1)?.replaceAll(',', '') ?? '0';
          final amount = double.tryParse(amtString) ?? 0.0;
          if (amount > 0) {
            final dateStr = DateFormat('dd MMM yyyy')
                .format(msg.date ?? DateTime.now());
            await DatabaseHelper.instance.insertTransaction(
              TransactionModel(
                amount: amount,
                category: 'SMS Auto',
                date: dateStr,
                description: body.length > 30 ? body.substring(0, 30) : body,
                type: 'expense',
              ),
            );
            addedCount++;
          }
        }
      }

      await _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-detected $addedCount expenses from SMS')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS permission denied')),
        );
      }
    }
  }

  void _showAddDialog() {
    final amountController = TextEditingController();
    final descController = TextEditingController();
    String category = 'Food';
    String type = 'expense';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Transaction'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount (₹)'),
              ),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: type,
                items: const [
                  DropdownMenuItem(value: 'expense', child: Text('Expense')),
                  DropdownMenuItem(value: 'savings', child: Text('Savings')),
                ],
                onChanged: (val) => type = val!,
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              DropdownButtonFormField<String>(
                value: category,
                items: ['Food', 'Bills', 'Travel', 'Shopping', 'Other']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) => category = val!,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amountController.text) ?? 0.0;
              if (amt > 0) {
                await DatabaseHelper.instance.insertTransaction(
                  TransactionModel(
                    amount: amt,
                    category: category,
                    date: DateFormat('dd MMM yyyy').format(DateTime.now()),
                    description: descController.text.isEmpty
                        ? category
                        : descController.text,
                    type: type,
                  ),
                );
                await _refreshData();
                if (mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rupee Expense Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sms),
            tooltip: 'Sync SMS Expenses',
            onPressed: _scanSMS,
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Total Expenses',
                          style: TextStyle(color: Colors.red)),
                      Text('₹${_totalExpenses.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Total Savings',
                          style: TextStyle(color: Colors.green)),
                      Text('₹${_totalSavings.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _transactions.isEmpty
                ? const Center(child: Text('No transactions added yet.'))
                : ListView.builder(
                    itemCount: _transactions.length,
                    itemBuilder: (ctx, index) {
                      final tx = _transactions[index];
                      final isExpense = tx.type == 'expense';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              isExpense ? Colors.red[100] : Colors.green[100],
                          child: Icon(
                            isExpense
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: isExpense ? Colors.red : Colors.green,
                          ),
                        ),
                        title: Text(tx.description),
                        subtitle: Text('${tx.category} • ${tx.date}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${isExpense ? '-' : '+'}₹${tx.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: isExpense ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.grey),
                              onPressed: () async {
                                if (tx.id != null) {
                                  await DatabaseHelper.instance
                                      .deleteTransaction(tx.id!);
                                  await _refreshData();
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
