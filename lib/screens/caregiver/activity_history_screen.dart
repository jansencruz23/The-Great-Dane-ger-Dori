import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/database_service.dart';
import '../../models/activity_log_model.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';

class ActivityHistoryScreen extends StatefulWidget {
  final String patientId;
  final String patientName;

  const ActivityHistoryScreen({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
