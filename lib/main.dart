import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExpenseTrackerApp());
}

// ============================================================
// APP
// ============================================================

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
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

// ============================================================
// MODEL
// ============================================================

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
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      type: map['type']?.toString() ?? 'Expense',
      account: map['account']?.toString() ?? 'Cash',
      toAccount: map['toAccount']?.toString(),
      category: map['category']?.toString() ?? '',
      subCategory: map['subCategory']?.toString() ?? '',
      date: map['date']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
    );
  }
}

// ============================================================
// DATABASE
// ============================================================

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('expenses_v4.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, fileName);

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
    final db = await database;

    return await db.insert(
      'transactions',
      tx.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateTransaction(TransactionModel tx) async {
    if (tx.id == null) return 0;

    final db = await database;

    return await db.update(
      'transactions',
      tx.toMap(),
      where: 'id = ?',
      whereArgs: [tx.id],
    );
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final db = await database;

    final result = await db.query(
      'transactions',
      orderBy: 'date DESC, id DESC',
    );

    return result
        .map((json) => TransactionModel.fromMap(json))
        .toList();
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;

    return await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> addCustomCategory(String name, String type) async {
    final db = await database;

    return await db.insert(
      'categories',
      {
        'name': name,
        'type': type,
      },
    );
  }

  Future<List<String>> getCustomCategories(String type) async {
    final db = await database;

    final result = await db.query(
      'categories',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'name ASC',
    );

    return result
        .map((row) => row['name'].toString())
        .toList();
  }

  // ==========================================================
  // BACKUP
  // ==========================================================

  Future<String?> exportDatabase() async {
    try {
      final db = await database;

      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');

      final dbPath = await getDatabasesPath();

      final sourceFile = File(
        p.join(dbPath, 'expenses_v4.db'),
      );

      if (!await sourceFile.exists()) {
        return null;
      }

      final selectedDirectory =
          await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        return null;
      }

      final date =
          DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

      final targetPath = p.join(
        selectedDirectory,
        'expense_tracker_backup_$date.db',
      );

      await sourceFile.copy(targetPath);

      return targetPath;
    } catch (e) {
      return null;
    }
  }

  // ==========================================================
  // RESTORE
  // ==========================================================

  Future<bool> importDatabase() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null ||
          result.files.single.path == null) {
        return false;
      }

      final backupFile =
          File(result.files.single.path!);

      if (!await backupFile.exists()) {
        return false;
      }

      final dbPath = await getDatabasesPath();

      final targetPath =
          p.join(dbPath, 'expenses_v4.db');

      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      await backupFile.copy(targetPath);

      return true;
    } catch (e) {
      return false;
    }
  }
}

// ============================================================
// DASHBOARD
// ============================================================

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() =>
      _DashboardScreenState();
}

class _DashboardScreenState
    extends State<DashboardScreen> {

  List<TransactionModel> _allTransactions = [];
  List<TransactionModel> _filteredTransactions = [];

  String _timeframe = 'Monthly';
  String _filterAccount = 'All';
  String _searchText = '';

  int _selectedPage = 0;

  double _totalIncome = 0;
  double _totalExpense = 0;
  double _totalSavings = 0;
  double _totalCredit = 0;

  final List<String> _accounts = [
    'Cash',
    'Bank Account',
    'Credit Card',
  ];

  final List<String> _types = [
    'Expense',
    'Income',
    'Savings',
    'Credit',
    'Transfer',
  ];

  final Map<String, List<String>> _categories = {
    'Expense': [
      'Food',
      'Grocery',
      'Bills',
      'Travel',
      'Shopping',
      'Health',
      'Education',
      'EMI',
      'Rent',
      'Fuel',
      'Other',
    ],
    'Income': [
      'Salary',
      'Business',
      'Investment',
      'Gift',
      'Other',
    ],
    'Savings': [
      'Emergency Fund',
      'FD',
      'Mutual Funds',
      'Gold',
      'Other',
    ],
    'Credit': [
      'Personal Loan',
      'Borrowed',
      'Lent',
      'Credit Card Debt',
      'Other',
    ],
    'Transfer': [
      'Account Transfer',
    ],
  };

  @override
  void initState() {
    super.initState();

    _loadCustomCategories();
    _refreshData();
  }

  // ==========================================================
  // DATA
  // ==========================================================

  Future<void> _refreshData() async {
    final data =
        await DatabaseHelper.instance.getAllTransactions();

    if (!mounted) return;

    setState(() {
      _allTransactions = data;
    });

    _applyFilters();
  }

  void _applyFilters() {
    final now = DateTime.now();

    final today =
        DateFormat('yyyy-MM-dd').format(now);

    final month =
        DateFormat('yyyy-MM').format(now);

    final year =
        DateFormat('yyyy').format(now);

    double income = 0;
    double expense = 0;
    double savings = 0;
    double credit = 0;

    final list =
        _allTransactions.where((tx) {

      if (_filterAccount != 'All') {
        if (tx.type == 'Transfer') {
          if (tx.account != _filterAccount &&
              tx.toAccount != _filterAccount) {
            return false;
          }
        } else if (tx.account != _filterAccount) {
          return false;
        }
      }

      if (_timeframe == 'Daily' &&
          !tx.date.startsWith(today)) {
        return false;
      }

      if (_timeframe == 'Monthly' &&
          !tx.date.startsWith(month)) {
        return false;
      }

      if (_timeframe == 'Yearly' &&
          !tx.date.startsWith(year)) {
        return false;
      }

      if (_searchText.isNotEmpty) {
        final search =
            _searchText.toLowerCase();

        final text =
            '${tx.category} '
            '${tx.subCategory} '
            '${tx.description} '
            '${tx.account} '
            '${tx.type}'
            .toLowerCase();

        if (!text.contains(search)) {
          return false;
        }
      }

      return true;
    }).toList();

    for (final tx in list) {
      if (tx.type == 'Income') {
        income += tx.amount;
      }

      if (tx.type == 'Expense') {
        expense += tx.amount;
      }

      if (tx.type == 'Savings') {
        savings += tx.amount;
      }

      if (tx.type == 'Credit') {
        credit += tx.amount;
      }
    }

    if (!mounted) return;

    setState(() {
      _filteredTransactions = list;

      _totalIncome = income;
      _totalExpense = expense;
      _totalSavings = savings;
      _totalCredit = credit;
    });
  }

  // ==========================================================
  // CUSTOM CATEGORIES
  // ==========================================================

  Future<void> _loadCustomCategories() async {
    for (final type in [
      'Expense',
      'Income',
      'Savings',
      'Credit',
    ]) {
      final custom =
          await DatabaseHelper.instance
              .getCustomCategories(type);

      if (custom.isNotEmpty && mounted) {
        setState(() {
          _categories[type] = [
            ..._categories[type]!,
            ...custom,
          ].toSet().toList();
        });
      }
    }
  }

  // ==========================================================
  // ADD CATEGORY
  // ==========================================================

  void _showAddCategoryDialog() {
    final controller =
        TextEditingController();

    String selectedType = 'Expense';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text(
                'Add Custom Category',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration:
                        const InputDecoration(
                      labelText: 'Type',
                    ),
                    items: [
                      'Expense',
                      'Income',
                      'Savings',
                      'Credit',
                    ]
                        .map(
                          (type) =>
                              DropdownMenuItem(
                            value: type,
                            child: Text(type),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setModalState(() {
                          selectedType = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration:
                        const InputDecoration(
                      labelText: 'Category Name',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name =
                        controller.text.trim();

                    if (name.isEmpty) return;

                    await DatabaseHelper.instance
                        .addCustomCategory(
                      name,
                      selectedType,
                    );

                    if (!mounted) return;

                    if (!_categories[selectedType]!
                        .contains(name)) {
                      setState(() {
                        _categories[selectedType]!
                            .add(name);
                      });
                    }

                    Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================================
  // ADD / EDIT TRANSACTION
  // ==========================================================

  Future<void> _showTransactionDialog({
    TransactionModel? transaction,
  }) async {

    final amountController =
        TextEditingController(
      text: transaction == null
          ? ''
          : transaction.amount.toString(),
    );

    final descriptionController =
        TextEditingController(
      text: transaction?.description ?? '',
    );

    final subCategoryController =
        TextEditingController(
      text: transaction?.subCategory ?? '',
    );

    String selectedType =
        transaction?.type ?? 'Expense';

    String selectedAccount =
        transaction?.account ?? 'Cash';

    String selectedToAccount =
        transaction?.toAccount ?? 'Bank Account';

    String selectedCategory =
        transaction?.category ??
            _categories['Expense']!.first;

    DateTime selectedDate =
        transaction != null
            ? _parseDate(transaction.date)
            : DateTime.now();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {

            final categories =
                _categories[selectedType] ??
                    ['Other'];

            if (!categories
                .contains(selectedCategory)) {
              selectedCategory =
                  categories.first;
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 20,
                bottom:
                    MediaQuery.of(context)
                            .viewInsets
                            .bottom +
                        20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [

                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment
                              .spaceBetween,
                      children: [
                        Text(
                          transaction == null
                              ? 'Add Transaction'
                              : 'Edit Transaction',
                          style:
                              const TextStyle(
                            fontSize: 21,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              Navigator.pop(ctx),
                          icon: const Icon(
                              Icons.close),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // TYPE
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration:
                          const InputDecoration(
                        labelText: 'Transaction Type',
                      ),
                      items: _types
                          .map(
                            (type) =>
                                DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;

                        setModalState(() {
                          selectedType = value;

                          selectedCategory =
                              _categories[value]!
                                  .first;
                        });
                      },
                    ),

                    const SizedBox(height: 12),

                    // ACCOUNT
                    Row(
                      children: [
                        Expanded(
                          child:
                              DropdownButtonFormField<
                                  String>(
                            value:
                                selectedAccount,
                            decoration:
                                InputDecoration(
                              labelText:
                                  selectedType ==
                                          'Transfer'
                                      ? 'From Account'
                                      : 'Account',
                            ),
                            items: _accounts
                                .map(
                                  (account) =>
                                      DropdownMenuItem(
                                    value: account,
                                    child:
                                        Text(account),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null)
                                return;

                              setModalState(() {
                                selectedAccount =
                                    value;

                                if (selectedToAccount ==
                                    selectedAccount) {
                                  selectedToAccount =
                                      _accounts.firstWhere(
                                    (a) =>
                                        a !=
                                        selectedAccount,
                                  );
                                }
                              });
                            },
                          ),
                        ),

                        if (selectedType ==
                            'Transfer') ...[
                          const SizedBox(width: 10),

                          Expanded(
                            child:
                                DropdownButtonFormField<
                                    String>(
                              value:
                                  selectedToAccount,
                              decoration:
                                  const InputDecoration(
                                labelText:
                                    'To Account',
                              ),
                              items: _accounts
                                  .where(
                                    (a) =>
                                        a !=
                                        selectedAccount,
                                  )
                                  .map(
                                    (account) =>
                                        DropdownMenuItem(
                                      value: account,
                                      child:
                                          Text(account),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null)
                                  return;

                                setModalState(() {
                                  selectedToAccount =
                                      value;
                                });
                              },
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 12),

                    // CATEGORY
                    if (selectedType !=
                        'Transfer') ...[
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration:
                            const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: categories
                            .map(
                              (category) =>
                                  DropdownMenuItem(
                                value: category,
                                child:
                                    Text(category),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;

                          setModalState(() {
                            selectedCategory =
                                value;
                          });
                        },
                      ),

                      const SizedBox(height: 12),

                      TextField(
                        controller:
                            subCategoryController,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Sub-category',
                        ),
                      ),

                      const SizedBox(height: 12),
                    ],

                    // AMOUNT
                    TextField(
                      controller:
                          amountController,
                      keyboardType:
                          const TextInputType
                              .numberWithOptions(
                        decimal: true,
                      ),
                      decoration:
                          const InputDecoration(
                        labelText: 'Amount (₹)',
                        prefixText: '₹ ',
                      ),
                    ),

                    const SizedBox(height: 12),

                    // DATE
                    InkWell(
                      onTap: () async {
                        final picked =
                            await showDatePicker(
                          context: context,
                          initialDate:
                              selectedDate,
                          firstDate:
                              DateTime(2000),
                          lastDate:
                              DateTime(2100),
                        );

                        if (picked != null) {
                          setModalState(() {
                            selectedDate =
                                DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              selectedDate.hour,
                              selectedDate.minute,
                            );
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration:
                            const InputDecoration(
                          labelText: 'Date',
                          suffixIcon: Icon(
                            Icons.calendar_month,
                          ),
                        ),
                        child: Text(
                          DateFormat(
                            'dd-MM-yyyy',
                          ).format(selectedDate),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // DESCRIPTION
                    TextField(
                      controller:
                          descriptionController,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Description',
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: Icon(
                          transaction == null
                              ? Icons.save
                              : Icons.update,
                        ),
                        label: Text(
                          transaction == null
                              ? 'Save Transaction'
                              : 'Update Transaction',
                          style:
                              const TextStyle(
                            fontSize: 16,
                          ),
                        ),
                        onPressed: () async {

                          final amount =
                              double.tryParse(
                            amountController.text
                                .trim()
                                .replaceAll(',', ''),
                          ) ??
                                  0;

                          if (amount <= 0) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please enter a valid amount.',
                                ),
                              ),
                            );
                            return;
                          }

                          final tx =
                              TransactionModel(
                            id: transaction?.id,
                            amount: amount,
                            type: selectedType,
                            account:
                                selectedAccount,
                            toAccount:
                                selectedType ==
                                        'Transfer'
                                    ? selectedToAccount
                                    : null,
                            category:
                                selectedType ==
                                        'Transfer'
                                    ? 'Account Transfer'
                                    : selectedCategory,
                            subCategory:
                                subCategoryController
                                    .text
                                    .trim(),
                            date: DateFormat(
                              'yyyy-MM-dd HH:mm',
                            ).format(selectedDate),
                            description:
                                descriptionController
                                    .text
                                    .trim(),
                          );

                          if (transaction == null) {
                            await DatabaseHelper
                                .instance
                                .insertTransaction(tx);
                          } else {
                            await DatabaseHelper
                                .instance
                                .updateTransaction(tx);
                          }

                          if (!mounted) return;

                          Navigator.pop(ctx);

                          await _refreshData();

                          if (!mounted) return;

                          ScaffoldMessenger.of(
                            this.context,
                          ).showSnackBar(
                            SnackBar(
                              content: Text(
                                transaction == null
                                    ? 'Transaction saved.'
                                    : 'Transaction updated.',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    amountController.dispose();
    descriptionController.dispose();
    subCategoryController.dispose();
  }

  DateTime _parseDate(String value) {
    try {
      return DateFormat(
        'yyyy-MM-dd HH:mm',
      ).parse(value);
    } catch (_) {
      return DateTime.now();
    }
  }

  // ==========================================================
  // DELETE
  // ==========================================================

  Future<void> _deleteTransaction(
    TransactionModel tx,
  ) async {
    if (tx.id == null) return;

    final confirm =
        await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title:
              const Text('Delete Transaction?'),
          content: Text(
            'Delete ${tx.category} transaction of ₹${tx.amount.toStringAsFixed(2)}?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () =>
                  Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await DatabaseHelper.instance
        .deleteTransaction(tx.id!);

    await _refreshData();
  }

  // ==========================================================
  // SMS
  // ==========================================================

  Future<void> _requestSMSPermissionAndScan() async {
    PermissionStatus status =
        await Permission.sms.status;

    if (!status.isGranted) {
      status =
          await Permission.sms.request();
    }

    if (status.isPermanentlyDenied) {
      if (mounted) {
        await openAppSettings();
      }
      return;
    }

    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content:
                Text('SMS permission denied.'),
          ),
        );
      }
      return;
    }

    try {
      final SmsQuery query = SmsQuery();

      final messages = await query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 100,
      );

      final existing =
          await DatabaseHelper.instance
              .getAllTransactions();

      int found = 0;

      for (final msg in messages) {
        final body = msg.body ?? '';

        final parsed =
            _parseBankSms(body);

        if (parsed == null) continue;

        final amount =
            parsed['amount'] as double;

        final type =
            parsed['type'] as String;

        final category =
            parsed['category'] as String;

        final date =
            msg.date ?? DateTime.now();

        final formattedDate =
            DateFormat(
          'yyyy-MM-dd HH:mm',
        ).format(date);

        final duplicate =
            existing.any(
          (tx) =>
              tx.amount == amount &&
              tx.date == formattedDate &&
              tx.description ==
                  'SMS Sync',
        );

        if (duplicate) continue;

        found++;

        if (!mounted) break;

        final shouldAdd =
            await _showSmsConfirmation(
          amount: amount,
          type: type,
          category: category,
          body: body,
          date: formattedDate,
        );

        if (!shouldAdd) continue;
      }

      if (!mounted) return;

      if (found == 0) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'No new bank transactions found.',
            ),
          ),
        );
      }

      await _refreshData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'SMS scan failed: $e',
          ),
        ),
      );
    }
  }

  Map<String, dynamic>? _parseBankSms(
    String body,
  ) {
    final text = body.toLowerCase();

    final amountPatterns = [
      RegExp(
        r'(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]+)?)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:debited|credited|spent|paid|received|sent)[^0-9]{0,30}([0-9,]+(?:\.[0-9]+)?)',
        caseSensitive: false,
      ),
    ];

    double? amount;

    for (final regex in amountPatterns) {
      final match = regex.firstMatch(body);

      if (match != null) {
        amount = double.tryParse(
          match.group(1)!
              .replaceAll(',', ''),
        );

        if (amount != null &&
            amount > 0) {
          break;
        }
      }
    }

    if (amount == null || amount <= 0) {
      return null;
    }

    final isCredit =
        text.contains('credited') ||
        text.contains('received') ||
        text.contains('credit of');

    final isDebit =
        text.contains('debited') ||
        text.contains('spent') ||
        text.contains('paid') ||
        text.contains('sent') ||
        text.contains('withdrawn');

    if (!isCredit && !isDebit) {
      return null;
    }

    final type =
        isCredit ? 'Income' : 'Expense';

    String category = 'Other';

    if (text.contains('swiggy') ||
        text.contains('zomato') ||
        text.contains('restaurant') ||
        text.contains('food')) {
      category = 'Food';
    } else if (text.contains('grocery') ||
        text.contains('supermarket') ||
        text.contains('bigbasket')) {
      category = 'Grocery';
    } else if (text.contains('uber') ||
        text.contains('ola') ||
        text.contains('rapido') ||
        text.contains('fuel') ||
        text.contains('petrol')) {
      category = 'Travel';
    } else if (text.contains('recharge') ||
        text.contains('electricity') ||
        text.contains('bill') ||
        text.contains('broadband')) {
      category = 'Bills';
    } else if (text.contains('amazon') ||
        text.contains('flipkart') ||
        text.contains('shopping')) {
      category = 'Shopping';
    } else if (text.contains('hospital') ||
        text.contains('medical') ||
        text.contains('pharmacy')) {
      category = 'Health';
    }

    return {
      'amount': amount,
      'type': type,
      'category': category,
    };
  }

  Future<bool> _showSmsConfirmation({
    required double amount,
    required String type,
    required String category,
    required String body,
    required String date,
  }) async {
    String selectedType = type;
    String selectedCategory = category;
    String selectedAccount = 'Bank Account';

    final result =
        await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder:
              (dialogContext, setDialogState) {

            final categories =
                _categories[selectedType] ??
                    ['Other'];

            if (!categories
                .contains(selectedCategory)) {
              selectedCategory =
                  categories.first;
            }

            return AlertDialog(
              title: const Text(
                'Bank Transaction Detected',
              ),
              content:
                  SingleChildScrollView(
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [

                    Text(
                      '₹${amount.toStringAsFixed(2)}',
                      style:
                          const TextStyle(
                        fontSize: 24,
                        fontWeight:
                            FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      body,
                      style:
                          const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),

                    const Divider(),

                    DropdownButtonFormField<
                        String>(
                      value: selectedType,
                      decoration:
                          const InputDecoration(
                        labelText: 'Type',
                      ),
                      items: _types
                          .map(
                            (type) =>
                                DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;

                        setDialogState(() {
                          selectedType =
                              value;

                          selectedCategory =
                              _categories[value]!
                                  .first;
                        });
                      },
                    ),

                    const SizedBox(height: 10),

                    DropdownButtonFormField<
                        String>(
                      value: selectedAccount,
                      decoration:
                          const InputDecoration(
                        labelText: 'Account',
                      ),
                      items: _accounts
                          .map(
                            (account) =>
                                DropdownMenuItem(
                              value: account,
                              child:
                                  Text(account),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null)
                          return;

                        setDialogState(() {
                          selectedAccount =
                              value;
                        });
                      },
                    ),

                    const SizedBox(height: 10),

                    DropdownButtonFormField<
                        String>(
                      value: selectedCategory,
                      decoration:
                          const InputDecoration(
                        labelText: 'Category',
                      ),
                      items: (_categories[
                                  selectedType] ??
                              ['Other'])
                          .map(
                            (category) =>
                                DropdownMenuItem(
                              value: category,
                              child:
                                  Text(category),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null)
                          return;

                        setDialogState(() {
                          selectedCategory =
                              value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(
                    ctx,
                    false,
                  ),
                  child: const Text(
                    'Ignore',
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await DatabaseHelper
                        .instance
                        .insertTransaction(
                      TransactionModel(
                        amount: amount,
                        type: selectedType,
                        account:
                            selectedAccount,
                        category:
                            selectedCategory,
                        subCategory: '',
                        date: date,
                        description:
                            'SMS Sync',
                      ),
                    );

                    if (dialogContext.mounted) {
                      Navigator.pop(
                        ctx,
                        true,
                      );
                    }
                  },
                  child: const Text(
                    'Add Transaction',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }

  // ==========================================================
  // BACKUP
  // ==========================================================

  Future<void> _handleExportBackup() async {
    final path =
        await DatabaseHelper.instance
            .exportDatabase();

    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          path == null
              ? 'Backup export failed or canceled.'
              : 'Backup saved successfully.',
        ),
      ),
    );
  }

  Future<void> _handleImportBackup() async {
    final success =
        await DatabaseHelper.instance
            .importDatabase();

    if (!mounted) return;

    if (success) {
      await _refreshData();

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Database restored successfully.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content:
              Text('Restore failed.'),
        ),
      );
    }
  }

  // ==========================================================
  // ACCOUNT BALANCE
  // ==========================================================

  double _getAccountBalance(
    String account,
  ) {
    double balance = 0;

    for (final tx in _allTransactions) {

      if (tx.type == 'Income' &&
          tx.account == account) {
        balance += tx.amount;
      }

      if (tx.type == 'Expense' &&
          tx.account == account) {
        balance -= tx.amount;
      }

      if (tx.type == 'Savings' &&
          tx.account == account) {
        balance -= tx.amount;
      }

      if (tx.type == 'Credit' &&
          tx.account == account) {
        balance += tx.amount;
      }

      if (tx.type == 'Transfer') {

        if (tx.account == account) {
          balance -= tx.amount;
        }

        if (tx.toAccount == account) {
          balance += tx.amount;
        }
      }
    }

    return balance;
  }

  // ==========================================================
  // UI HELPERS
  // ==========================================================

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Expense':
        return Colors.red;

      case 'Income':
        return Colors.green;

      case 'Savings':
        return Colors.blue;

      case 'Credit':
        return Colors.orange;

      case 'Transfer':
        return Colors.purple;

      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'Expense':
        return Icons.arrow_upward;

      case 'Income':
        return Icons.arrow_downward;

      case 'Savings':
        return Icons.savings;

      case 'Credit':
        return Icons.credit_card;

      case 'Transfer':
        return Icons.swap_horiz;

      default:
        return Icons.account_balance_wallet;
    }
  }

  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Card(
        elevation: 1,
        child: Padding(
          padding:
              const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(
                icon,
                color: color,
                size: 24,
              ),
              const SizedBox(height: 5),
              Text(
                title,
                style:
                    const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(
                  '₹${amount.toStringAsFixed(0)}',
                  style:
                      TextStyle(
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // DASHBOARD PAGE
  // ==========================================================

  Widget _buildDashboard() {

    final net =
        _totalIncome -
            _totalExpense -
            _totalSavings;

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView(
        padding:
            const EdgeInsets.only(
          bottom: 100,
        ),
        children: [

          // NET POSITION
          Card(
            margin:
                const EdgeInsets.all(12),
            child: Padding(
              padding:
                  const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Text(
                    'Net Position',
                    style:
                        TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '₹${net.toStringAsFixed(2)}',
                    style:
                        TextStyle(
                      fontSize: 30,
                      fontWeight:
                          FontWeight.bold,
                      color: net >= 0
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeframe,
                    style:
                        const TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 10,
            ),
            child: Row(
              children: [
                _buildSummaryCard(
                  title: 'Income',
                  amount: _totalIncome,
                  color: Colors.green,
                  icon:
                      Icons.arrow_downward,
                ),
                _buildSummaryCard(
                  title: 'Expense',
                  amount: _totalExpense,
                  color: Colors.red,
                  icon:
                      Icons.arrow_upward,
                ),
              ],
            ),
          ),

          Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 10,
            ),
            child: Row(
              children: [
                _buildSummaryCard(
                  title: 'Savings',
                  amount: _totalSavings,
                  color: Colors.blue,
                  icon: Icons.savings,
                ),
                _buildSummaryCard(
                  title: 'Credit',
                  amount: _totalCredit,
                  color: Colors.orange,
                  icon:
                      Icons.credit_card,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          const Padding(
            padding:
                EdgeInsets.symmetric(
              horizontal: 16,
            ),
            child: Text(
              'Accounts',
              style:
                  TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 5),

          ..._accounts.map(
            (account) {
              final balance =
                  _getAccountBalance(
                account,
              );

              IconData icon;

              if (account == 'Cash') {
                icon = Icons.payments;
              } else if (account ==
                  'Credit Card') {
                icon = Icons.credit_card;
              } else {
                icon =
                    Icons.account_balance;
              }

              return Card(
                margin:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(icon),
                  ),
                  title: Text(
                    account,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  trailing: Text(
                    '₹${balance.toStringAsFixed(2)}',
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 16,
                      color: balance >= 0
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 10),

          const Padding(
            padding:
                EdgeInsets.symmetric(
              horizontal: 16,
            ),
            child: Text(
              'Expense by Category',
              style:
                  TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 5),

          _buildCategoryAnalysis(),
        ],
      ),
    );
  }

  Widget _buildCategoryAnalysis() {
    final Map<String, double>
        categoryTotals = {};

    for (final tx
        in _filteredTransactions) {
      if (tx.type != 'Expense') {
        continue;
      }

      categoryTotals[tx.category] =
          (categoryTotals[tx.category] ??
                  0) +
              tx.amount;
    }

    if (categoryTotals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text(
            'No expense data available.',
          ),
        ),
      );
    }

    final sorted =
        categoryTotals.entries.toList()
          ..sort(
            (a, b) =>
                b.value.compareTo(a.value),
          );

    final maxValue =
        sorted.first.value;

    return Column(
      children: sorted
          .take(8)
          .map(
            (entry) {
              final percentage =
                  maxValue == 0
                      ? 0.0
                      : entry.value /
                          maxValue;

              return Card(
                margin:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 12,
                  vertical: 3,
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    10,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                        children: [
                          Text(
                            entry.key,
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .bold,
                            ),
                          ),
                          Text(
                            '₹${entry.value.toStringAsFixed(0)}',
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 6,
                      ),
                      LinearProgressIndicator(
                        value: percentage,
                        minHeight: 7,
                        borderRadius:
                            BorderRadius
                                .circular(
                          10,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          )
          .toList(),
    );
  }

  // ==========================================================
  // TRANSACTION PAGE
  // ==========================================================

  Widget _buildTransactionsPage() {
    return Column(
      children: [

        Padding(
          padding:
              const EdgeInsets.all(10),
          child: TextField(
            decoration:
                const InputDecoration(
              hintText:
                  'Search transactions...',
              prefixIcon:
                  Icon(Icons.search),
            ),
            onChanged: (value) {
              setState(() {
                _searchText =
                    value.trim();
              });

              _applyFilters();
            },
          ),
        ),

        SingleChildScrollView(
          scrollDirection:
              Axis.horizontal,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 10,
          ),
          child: Row(
            children: [
              ...[
                'Daily',
                'Monthly',
                'Yearly',
                'All',
              ].map(
                (value) {
                  return Padding(
                    padding:
                        const EdgeInsets
                            .only(
                      right: 6,
                    ),
                    child: ChoiceChip(
                      label:
                          Text(value),
                      selected:
                          _timeframe ==
                              value,
                      onSelected:
                          (_) {
                        setState(() {
                          _timeframe =
                              value;
                        });

                        _applyFilters();
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 5,
          ),
          child:
              DropdownButtonFormField<
                  String>(
            value: _filterAccount,
            decoration:
                const InputDecoration(
              labelText:
                  'Account Filter',
            ),
            items: [
              'All',
              ..._accounts,
            ]
                .map(
                  (account) =>
                      DropdownMenuItem(
                    value: account,
                    child:
                        Text(account),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;

              setState(() {
                _filterAccount =
                    value;
              });

              _applyFilters();
            },
          ),
        ),

        const Divider(),

        Expanded(
          child: _filteredTransactions
                  .isEmpty
              ? const Center(
                  child: Text(
                    'No transactions found.',
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets
                          .only(
                    bottom: 100,
                  ),
                  itemCount:
                      _filteredTransactions
                          .length,
                  itemBuilder:
                      (context, index) {

                    final tx =
                        _filteredTransactions[
                            index];

                    return _buildTransactionTile(
                      tx,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTransactionTile(
    TransactionModel tx,
  ) {
    final color =
        _getTypeColor(tx.type);

    final icon =
        _getTypeIcon(tx.type);

    return Card(
      margin:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              color.withOpacity(0.12),
          child: Icon(
            icon,
            color: color,
          ),
        ),
        title: Text(
          tx.type == 'Transfer'
              ? '${tx.account} → ${tx.toAccount}'
              : tx.category,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            if (tx.subCategory.isNotEmpty)
              Text(
                tx.subCategory,
              ),
            Text(
              '${tx.account} • ${_displayDate(tx.date)}',
            ),
            if (tx.description.isNotEmpty)
              Text(
                tx.description,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
              ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<
            String>(
          onSelected: (value) {
            if (value == 'edit') {
              _showTransactionDialog(
                transaction: tx,
              );
            }

            if (value == 'delete') {
              _deleteTransaction(tx);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(
                    Icons.delete,
                    color: Colors.red,
                  ),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _displayDate(String value) {
    final date = _parseDate(value);

    return DateFormat(
      'dd-MM-yyyy HH:mm',
    ).format(date);
  }

  // ==========================================================
  // REPORT PAGE
  // ==========================================================

  Widget _buildReportsPage() {

    final income =
        _totalIncome;

    final expense =
        _totalExpense;

    final savings =
        _totalSavings;

    final credit =
        _totalCredit;

    return ListView(
      padding:
          const EdgeInsets.only(
        bottom: 100,
      ),
      children: [

        const Padding(
          padding:
              EdgeInsets.all(16),
          child: Text(
            'Financial Report',
            style:
                TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ),

        Card(
          margin:
              const EdgeInsets.symmetric(
            horizontal: 12,
          ),
          child: Column(
            children: [
              _reportRow(
                'Income',
                income,
                Colors.green,
              ),
              _reportRow(
                'Expense',
                expense,
                Colors.red,
              ),
              _reportRow(
                'Savings',
                savings,
                Colors.blue,
              ),
              _reportRow(
                'Credit',
                credit,
                Colors.orange,
              ),
            ],
          ),
        ),

        const SizedBox(height: 15),

        const Padding(
          padding:
              EdgeInsets.symmetric(
            horizontal: 16,
          ),
          child: Text(
            'Expense Categories',
            style:
                TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(height: 5),

        _buildCategoryAnalysis(),
      ],
    );
  }

  Widget _reportRow(
    String title,
    double amount,
    Color color,
  ) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            color.withOpacity(0.12),
        child: Icon(
          Icons.currency_rupee,
          color: color,
        ),
      ),
      title: Text(title),
      trailing: Text(
        '₹${amount.toStringAsFixed(2)}',
        style:
            TextStyle(
          color: color,
          fontWeight:
              FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  // ==========================================================
  // SETTINGS
  // ==========================================================

  Widget _buildSettingsPage() {
    return ListView(
      padding:
          const EdgeInsets.only(
        bottom: 100,
      ),
      children: [

        const Padding(
          padding:
              EdgeInsets.all(16),
          child: Text(
            'Settings',
            style:
                TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ),

        Card(
          margin:
              const EdgeInsets.symmetric(
            horizontal: 12,
          ),
          child: Column(
            children: [

              ListTile(
                leading:
                    const Icon(Icons.sms),
                title:
                    const Text(
                  'Scan Bank SMS',
                ),
                subtitle:
                    const Text(
                  'Detect bank and UPI transactions',
                ),
                trailing:
                    const Icon(
                  Icons.chevron_right,
                ),
                onTap:
                    _requestSMSPermissionAndScan,
              ),

              const Divider(height: 1),

              ListTile(
                leading:
                    const Icon(
                  Icons.category,
                ),
                title:
                    const Text(
                  'Add Custom Category',
                ),
                trailing:
                    const Icon(
                  Icons.chevron_right,
                ),
                onTap:
                    _showAddCategoryDialog,
              ),

              const Divider(height: 1),

              ListTile(
                leading:
                    const Icon(
                  Icons.backup,
                ),
                title:
                    const Text(
                  'Backup Database',
                ),
                subtitle:
                    const Text(
                  'Save your transactions',
                ),
                trailing:
                    const Icon(
                  Icons.chevron_right,
                ),
                onTap:
                    _handleExportBackup,
              ),

              const Divider(height: 1),

              ListTile(
                leading:
                    const Icon(
                  Icons.restore,
                ),
                title:
                    const Text(
                  'Restore Database',
                ),
                subtitle:
                    const Text(
                  'Restore from backup',
                ),
                trailing:
                    const Icon(
                  Icons.chevron_right,
                ),
                onTap:
                    _handleImportBackup,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        const Center(
          child: Text(
            'Rupee Expense Tracker',
            style:
                TextStyle(
              color: Colors.grey,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ),

        const Center(
          child: Text(
            'Version 1.1',
            style:
                TextStyle(
              color: Colors.grey,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // MAIN BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {

    Widget body;

    switch (_selectedPage) {
      case 0:
        body = _buildDashboard();
        break;

      case 1:
        body = _buildTransactionsPage();
        break;

      case 2:
        body = _buildReportsPage();
        break;

      case 3:
        body = _buildSettingsPage();
        break;

      default:
        body = _buildDashboard();
    }

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          'Rupee Expense Tracker',
          style:
              TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        actions: [

          if (_selectedPage == 0 ||
              _selectedPage == 1)
            IconButton(
              icon:
                  const Icon(Icons.sms),
              tooltip:
                  'Scan SMS',
              onPressed:
                  _requestSMSPermissionAndScan,
            ),

          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'category') {
                _showAddCategoryDialog();
              }

              if (value == 'backup') {
                _handleExportBackup();
              }

              if (value == 'restore') {
                _handleImportBackup();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'category',
                child: Row(
                  children: [
                    Icon(Icons.category),
                    SizedBox(width: 8),
                    Text(
                      'Add Category',
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'backup',
                child: Row(
                  children: [
                    Icon(Icons.backup),
                    SizedBox(width: 8),
                    Text(
                      'Backup Database',
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'restore',
                child: Row(
                  children: [
                    Icon(Icons.restore),
                    SizedBox(width: 8),
                    Text(
                      'Restore Database',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),

      body: body,

      bottomNavigationBar:
          NavigationBar(
        selectedIndex:
            _selectedPage,
        onDestinationSelected:
            (index) {
          setState(() {
            _selectedPage =
                index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon:
                Icon(Icons.dashboard_outlined),
            selectedIcon:
                Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon:
                Icon(Icons.receipt_long_outlined),
            selectedIcon:
                Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon:
                Icon(Icons.bar_chart_outlined),
            selectedIcon:
                Icon(Icons.bar_chart),
            label: 'Reports',
          ),
          NavigationDestination(
            icon:
                Icon(Icons.settings_outlined),
            selectedIcon:
                Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),

      floatingActionButton:
          _selectedPage == 3
              ? null
              : FloatingActionButton.extended(
                  onPressed:
                      () =>
                          _showTransactionDialog(),
                  icon:
                      const Icon(Icons.add),
                  label:
                      const Text(
                    'Add Entry',
                  ),
                ),
    );
  }
}
