import 'package:flutter/material.dart';

import '../../../models/app_user.dart';
import '../../../models/leave_request.dart';
import '../../../repositories/leave_repository.dart';
import '../../../theme/app_colors.dart';

class LeaveManagementPanel extends StatefulWidget {
  final AppUser profile;

  const LeaveManagementPanel({super.key, required this.profile});

  @override
  State<LeaveManagementPanel> createState() => _LeaveManagementPanelState();
}

class _LeaveManagementPanelState extends State<LeaveManagementPanel> {
  LeaveBalance? _balance;
  List<LeaveRequest> _requests = const [];
  bool _loading = true;
  bool _working = false;
  String? _error;

  bool get _isOwner => widget.profile.isOwner;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final requests = _isOwner
          ? await LeaveRepository.instance.ownerRequests()
          : await LeaveRepository.instance.myRequests();
      final balance = _isOwner
          ? null
          : await LeaveRepository.instance.myBalance();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _balance = balance;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Leave information could not be loaded.';
      });
    }
  }

  Future<void> _applyForLeave() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final range = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: DateTime(now.year, 12, 31),
      initialDateRange: DateTimeRange(start: firstDate, end: firstDate),
      helpText: 'SELECT LEAVE DATES',
      saveText: 'CONTINUE',
    );
    if (range == null || !mounted) return;

    final workingDays = _workingDays(range.start, range.end);
    if (workingDays == 0) {
      _message('The selected dates contain only Saturday and Sunday.');
      return;
    }

    var reason = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apply for Leave'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F7FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_date(range.start)} – ${_date(range.end)}\n'
                  '$workingDays working ${workingDays == 1 ? 'day' : 'days'} '
                  '(Saturday and Sunday excluded)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                minLines: 3,
                maxLines: 5,
                autofocus: true,
                onChanged: (value) => reason = value.trim(),
                decoration: const InputDecoration(
                  labelText: 'Reason for leave',
                  hintText: 'Enter a clear reason for the request',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.length < 3) return;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );
    if (confirmed != true || reason.length < 3 || !mounted) return;

    setState(() => _working = true);
    try {
      await LeaveRepository.instance.apply(
        startDate: range.start,
        endDate: range.end,
        reason: reason,
      );
      if (!mounted) return;
      _message('Leave request submitted to the owner for approval.');
      await _load();
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _review(LeaveRequest request, bool approve) async {
    var reviewNote = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve Leave' : 'Reject Leave'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${request.employeeName}\n'
                '${_date(request.startDate)} – ${_date(request.endDate)} '
                '• ${request.workingDays} working days',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(request.reason),
              const SizedBox(height: 16),
              TextField(
                minLines: 2,
                maxLines: 4,
                onChanged: (value) => reviewNote = value.trim(),
                decoration: InputDecoration(
                  labelText: approve
                      ? 'Approval note (optional)'
                      : 'Rejection reason (recommended)',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: approve
                  ? const Color(0xFF16845B)
                  : const Color(0xFFBE3347),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    try {
      await LeaveRepository.instance.review(
        requestId: request.id,
        approve: approve,
        reviewNote: reviewNote,
      );
      if (!mounted) return;
      _message(approve ? 'Leave approved.' : 'Leave rejected.');
      await _load();
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE6EC)),
      ),
      child: Padding(
        padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 18),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _errorPanel()
            else if (_isOwner)
              _ownerContent()
            else
              _employeeContent(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Row(
          children: [
            const _IconBox(icon: Icons.event_available_rounded),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Leave Management',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  SizedBox(height: 3),
                  Text('21 paid working days per calendar year',
                      style: TextStyle(color: Color(0xFF64748B))),
                ],
              ),
            ),
          ],
        );
        final action = !_isOwner
            ? FilledButton.icon(
                onPressed: _working ? null : _applyForLeave,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Apply for Leave'),
              )
            : IconButton.filledTonal(
                onPressed: _working ? null : _load,
                tooltip: 'Refresh leave requests',
                icon: const Icon(Icons.refresh_rounded),
              );
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          );
        }
        return Row(children: [Expanded(child: title), const SizedBox(width: 16), action]);
      },
    );
  }

  Widget _employeeContent() {
    final balance = _balance!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final count = constraints.maxWidth >= 800 ? 4 : 2;
            final width = (constraints.maxWidth - ((count - 1) * 10)) / count;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _balanceCard(width, 'Annual Leave', balance.annualAllowance,
                    Icons.calendar_month_rounded, AppColors.primary),
                _balanceCard(width, 'Approved Used', balance.approvedDays,
                    Icons.task_alt_rounded, const Color(0xFF6B5DD3)),
                _balanceCard(width, 'Pending', balance.pendingDays,
                    Icons.hourglass_top_rounded, const Color(0xFFD68115)),
                _balanceCard(width, 'Remaining', balance.remainingDays,
                    Icons.savings_outlined, const Color(0xFF16845B)),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        const Text(
          'My Leave Requests',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        if (_requests.isEmpty)
          _empty('No leave requests have been submitted.')
        else
          _employeeRequestTable(),
      ],
    );
  }

  Widget _employeeRequestTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: _requests.map(_mobileLeaveRequestCard).toList(),
          );
        }
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
          headingTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
          columnSpacing: 28,
          columns: const [
            DataColumn(label: Text('Applied On')),
            DataColumn(label: Text('Leave Applied For')),
            DataColumn(label: Text('Working Days')),
            DataColumn(label: Text('Reason')),
            DataColumn(label: Text('Approval Status')),
          ],
          rows: _requests.map((request) {
            final note = request.reviewNote.isEmpty
                ? request.reason
                : '${request.reason}\nOwner note: ${request.reviewNote}';
            return DataRow(
              cells: [
                DataCell(Text(_date(request.createdAt))),
                DataCell(
                  Text(
                    '${_date(request.startDate)} – ${_date(request.endDate)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                DataCell(Text('${request.workingDays}')),
                DataCell(
                  SizedBox(
                    width: 280,
                    child: Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(_requestStatusChip(request)),
              ],
            );
          }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _mobileLeaveRequestCard(LeaveRequest request) {
    final note = request.reviewNote.isEmpty
        ? request.reason
        : '${request.reason}\nOwner note: ${request.reviewNote}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${_date(request.startDate)} – ${_date(request.endDate)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: _requestStatusChip(request)),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            '${request.workingDays} working days • Applied ${_date(request.createdAt)}',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(note),
        ],
      ),
    );
  }

  Widget _requestStatusChip(LeaveRequest request) {
    final color = request.isApproved
        ? const Color(0xFF16845B)
        : request.isRejected
        ? const Color(0xFFBE3347)
        : const Color(0xFFD68115);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(request.status),
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _ownerContent() {
    final pending = _requests.where((item) => item.isPending).toList();
    final decided = _requests.where((item) => !item.isPending).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Pending Approval',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE7D1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${pending.length}',
                style: const TextStyle(
                  color: Color(0xFF9A5500),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (pending.isEmpty)
          _empty('There are no leave requests awaiting approval.')
        else
          ...pending.map(_approvalCard),
        if (decided.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text(
            'Recent Decisions',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ...decided.take(12).map(_employeeRequestCard),
        ],
      ],
    );
  }

  Widget _balanceCard(
    double width,
    String label,
    int value,
    IconData icon,
    Color color,
  ) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.11),
            foregroundColor: color,
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF64748B))),
                const SizedBox(height: 2),
                Text(
                  '$value days',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _approvalCard(LeaveRequest request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1DDC2)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 570),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.employeeName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_date(request.startDate)} – ${_date(request.endDate)}  •  '
                  '${request.workingDays} working days',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(request.reason, style: const TextStyle(color: Color(0xFF475569))),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _working ? null : () => _review(request, false),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Reject'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16845B),
                ),
                onPressed: _working ? null : () => _review(request, true),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Approve'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _employeeRequestCard(LeaveRequest request) {
    final color = request.isApproved
        ? const Color(0xFF16845B)
        : request.isRejected
        ? const Color(0xFFBE3347)
        : const Color(0xFFD68115);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.11),
            foregroundColor: color,
            child: Icon(
              request.isApproved
                  ? Icons.check_rounded
                  : request.isRejected
                  ? Icons.close_rounded
                  : Icons.schedule_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isOwner
                      ? request.employeeName
                      : '${_date(request.startDate)} – ${_date(request.endDate)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  _isOwner
                      ? '${_date(request.startDate)} – ${_date(request.endDate)} • '
                            '${request.workingDays} working days'
                      : '${request.workingDays} working days • ${request.reason}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                if (request.reviewNote.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('Owner note: ${request.reviewNote}'),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _statusLabel(request.status),
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF64748B)),
      ),
    );
  }

  Widget _errorPanel() {
    return Center(
      child: Column(
        children: [
          Text(_error!, style: const TextStyle(color: Color(0xFFBE3347))),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  int _workingDays(DateTime start, DateTime end) {
    var days = 0;
    var cursor = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!cursor.isAfter(last)) {
      if (cursor.weekday != DateTime.saturday &&
          cursor.weekday != DateTime.sunday) {
        days++;
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return days;
  }

  String _date(DateTime date) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  String _statusLabel(String status) {
    if (status == 'approved') return 'Approved';
    if (status == 'rejected') return 'Rejected';
    return 'Waiting for Approval';
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    final messageMatch = RegExp(r'message:\s*([^,}\)]+)').firstMatch(text);
    final message = messageMatch?.group(1)?.trim();
    return message?.isNotEmpty == true
        ? message!
        : 'The leave request could not be processed.';
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;

  const _IconBox({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFE9F4FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.primary),
    );
  }
}
