import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/// All students with search/filter for admin.
class AdminStudentsListScreen extends ConsumerStatefulWidget {
  const AdminStudentsListScreen({super.key});

  @override
  ConsumerState<AdminStudentsListScreen> createState() => _AdminStudentsListScreenState();
}

class _AdminStudentsListScreenState extends ConsumerState<AdminStudentsListScreen> {
  final _searchController = TextEditingController();
  var _filterStatus = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // In production, use a student list provider with filters
    // For now, mock data from the students available

    return Scaffold(
      appBar: AppBar(
        title: const Text('الطلاب'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'البحث عن الاسم أو الملف...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('الكل'),
                        selected: _filterStatus.isEmpty,
                        onSelected: (_) => setState(() => _filterStatus = ''),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('نشط'),
                        selected: _filterStatus == 'active',
                        onSelected: (_) => setState(() => _filterStatus = 'active'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('مؤرشف'),
                        selected: _filterStatus == 'archived',
                        onSelected: (_) => setState(() => _filterStatus = 'archived'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // Placeholder: in production, iterate over students list
                StudentListItem(
                  name: 'محمد أحمد',
                  fileNumber: '001',
                  status: 'نشط',
                  specialty: 'النطق',
                  onTap: () {},
                ),
                StudentListItem(
                  name: 'فاطمة علي',
                  fileNumber: '002',
                  status: 'نشط',
                  specialty: 'العلاج الوظيفي',
                  onTap: () {},
                ),
                StudentListItem(
                  name: 'ياسين محمود',
                  fileNumber: '003',
                  status: 'نشط',
                  specialty: 'تعديل السلوك',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One student row.
class StudentListItem extends StatelessWidget {
  const StudentListItem({
    super.key,
    required this.name,
    required this.fileNumber,
    required this.status,
    required this.specialty,
    required this.onTap,
  });

  final String name;
  final String fileNumber;
  final String status;
  final String specialty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Avatar(name: name, seed: int.tryParse(fileNumber) ?? 0, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: text.titleSmall),
                Text('الملف #$fileNumber', style: text.bodySmall?.copyWith(color: AppColors.muted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ToneChip(status, tone: 'good', icon: Icons.check_circle_rounded),
              SpecialtyTag(specialty),
            ],
          ),
        ],
      ),
    );
  }
}
