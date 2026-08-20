  Future<void> _requestSMSPermissionAndScan() async {
    PermissionStatus status = await Permission.sms.status;

    if (!status.isGranted) {
      status = await Permission.sms.request();
    }

    if (status.isPermanentlyDenied) {
      if (mounted) openAppSettings();
      return;
    }

    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS permission denied.')),
        );
      }
      return;
    }

    final SmsQuery query = SmsQuery();
    final messages = await query.querySms(kinds: [SmsQueryKind.inbox], count: 50);

    final txRegex = RegExp(
      r'(?:debited|spent|paid|credited|received|sent)\s*(?:by|for|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]+)?)',
      caseSensitive: false,
    );

    // Get existing database transactions to prevent duplicates
    final existingTxList = await DatabaseHelper.instance.getAllTransactions();

    int countParsed = 0;

    for (var msg in messages) {
      final body = msg.body ?? '';
      final match = txRegex.firstMatch(body);

      if (match != null) {
        final amtString = match.group(1)?.replaceAll(',', '') ?? '0';
        final amount = double.tryParse(amtString) ?? 0.0;

        if (amount > 0) {
          final msgDate = msg.date != null 
              ? DateFormat('yyyy-MM-dd HH:mm').format(msg.date!) 
              : DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

          // Deduplication: Skip if amount and date already exist in DB
          bool alreadyExists = existingTxList.any(
            (tx) => tx.amount == amount && tx.date == msgDate,
          );

          if (alreadyExists) continue;

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
            bool shouldContinue = await _showSmsParsedDialog(amount, autoType, autoCat, body, msgDate);
            if (!shouldContinue) break;
          }
        }
      }
    }

    if (countParsed == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No new bank transaction SMS found.')),
      );
    }

    await _refreshData();
  }

  Future<bool> _showSmsParsedDialog(
    double amount, 
    String autoType, 
    String autoCat, 
    String rawText, 
    String formattedDate
  ) async {
    String selectedType = autoType;
    String selectedCat = autoCat;
    String selectedAccount = 'Bank Account';

    final subCatController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          List<String> currentCats = _categories[selectedType] ?? ['Other'];
          if (!currentCats.contains(selectedCat)) selectedCat = currentCats.first;

          return AlertDialog(
            title: const Text('Transaction Detected'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Amount: ₹$amount',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
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
                onPressed: () => Navigator.of(dialogCtx).pop(true),
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
                      date: formattedDate,
                      description: 'SMS Sync',
                    ),
                  );
                  if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(true);
                },
                child: const Text('Add Entry'),
              ),
            ],
          );
        },
      ),
    );

    return result ?? true;
  }
