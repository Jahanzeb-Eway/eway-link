import 'package:flutter/material.dart';

import '../../models/employee_account.dart';
import '../../repositories/employee_repository.dart';
import '../../services/auth_service.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  final _repository = EmployeeRepository();
  final _searchController = TextEditingController();
  List<EmployeeAccount> _employees = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final employees = await _repository.fetchEmployees();
      if (!mounted) return;
      setState(() => _employees = employees);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('PostgrestException(message: ', '');

  List<EmployeeAccount> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _employees;
    return _employees.where((employee) {
      return employee.fullName.toLowerCase().contains(query) ||
          employee.username.toLowerCase().contains(query) ||
          employee.roleLabel.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _createEmployee() async {
    final request = await showDialog<_CreateEmployeeRequest>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateEmployeeDialog(),
    );
    if (request == null) return;
    await _run(
      () => _repository.createEmployee(
        fullName: request.fullName,
        username: request.username,
        role: request.role,
        temporaryPassword: request.password,
      ),
      'Employee account created. The employee can now sign in with the username.',
    );
  }

  Future<void> _changeActive(EmployeeAccount employee) async {
    final action = employee.isActive ? 'deactivate' : 'reactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${action[0].toUpperCase()}${action.substring(1)} account?'),
        content: Text(
          employee.isActive
              ? '${employee.fullName} will be signed out and unable to access EWAY LINK. Historical records will remain available.'
              : '${employee.fullName} will be able to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(employee.isActive ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => _repository.setActive(
        employeeId: employee.id,
        isActive: !employee.isActive,
      ),
      employee.isActive ? 'Employee account deactivated.' : 'Employee account reactivated.',
    );
  }

  Future<void> _resetPassword(EmployeeAccount employee) async {
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResetPasswordDialog(employeeName: employee.fullName),
    );
    if (password == null) return;
    await _run(
      () => _repository.resetPassword(
        employeeId: employee.id,
        password: password,
      ),
      'Password reset. The employee must sign in again.',
    );
  }

  Future<void> _run(Future<void> Function() operation, String success) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await operation();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success), backgroundColor: const Color(0xFF15805D)),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_message(error)), backgroundColor: const Color(0xFFB4233A)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = AuthService.instance.cachedProfile;
    if (profile?.isOwner != true) {
      return const _AccessDenied();
    }
    final active = _employees.where((employee) => employee.isActive).length;
    final coordinators = _employees
        .where((employee) => employee.role == 'coordinator' && employee.isActive)
        .length;

    return ColoredBox(
      color: const Color(0xFFF4F7FB),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 42),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 18,
              runSpacing: 14,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Employees', style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900, color: Color(0xFF142033))),
                    SizedBox(height: 6),
                    Text('Secure account access, roles and employment status.', style: TextStyle(color: Color(0xFF60738E), fontSize: 14)),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _createEmployee,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
                  label: const Text('New Employee'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0B88C4),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 760
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(width: width, icon: Icons.groups_2_rounded, label: 'Total Accounts', value: '${_employees.length}', color: const Color(0xFF0789C5)),
                    _MetricCard(width: width, icon: Icons.verified_user_rounded, label: 'Active Employees', value: '$active', color: const Color(0xFF159B70)),
                    _MetricCard(width: width, icon: Icons.support_agent_rounded, label: 'Coordinators', value: '$coordinators', color: const Color(0xFF7A5AF8)),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: _cardDecoration(),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search employee, username or role',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD8E1EB))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD8E1EB))),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(padding: EdgeInsets.all(50), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              _ErrorPanel(message: _error!, onRetry: _load)
            else if (_filtered.isEmpty)
              const _EmptyPanel()
            else
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 820
                    ? _EmployeeTable(
                        employees: _filtered,
                        currentUserId: profile!.id,
                        onActiveChanged: _changeActive,
                        onResetPassword: _resetPassword,
                      )
                    : Column(
                        children: _filtered
                            .map((employee) => _EmployeeCard(
                                  employee: employee,
                                  isCurrentUser: employee.id == profile!.id,
                                  onActiveChanged: _changeActive,
                                  onResetPassword: _resetPassword,
                                ))
                            .toList(),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFFDDE5EE)),
      boxShadow: const [BoxShadow(color: Color(0x0D102A43), blurRadius: 18, offset: Offset(0, 7))],
    );

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.width, required this.icon, required this.label, required this.value, required this.color});
  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(),
        child: Row(children: [
          Container(width: 43, height: 43, decoration: BoxDecoration(color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 22)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Color(0xFF60738E), fontSize: 13, fontWeight: FontWeight.w600)), const SizedBox(height: 3), Text(value, style: const TextStyle(color: Color(0xFF142033), fontSize: 22, fontWeight: FontWeight.w900))])),
        ]),
      );
}

class _EmployeeTable extends StatelessWidget {
  const _EmployeeTable({required this.employees, required this.currentUserId, required this.onActiveChanged, required this.onResetPassword});
  final List<EmployeeAccount> employees;
  final String currentUserId;
  final ValueChanged<EmployeeAccount> onActiveChanged;
  final ValueChanged<EmployeeAccount> onResetPassword;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: _cardDecoration(),
        child: Column(children: [
          const _EmployeeRow(header: true),
          for (final employee in employees)
            _EmployeeRow(
              employee: employee,
              isCurrentUser: employee.id == currentUserId,
              onActiveChanged: onActiveChanged,
              onResetPassword: onResetPassword,
            ),
        ]),
      );
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({this.header = false, this.employee, this.isCurrentUser = false, this.onActiveChanged, this.onResetPassword});
  final bool header;
  final EmployeeAccount? employee;
  final bool isCurrentUser;
  final ValueChanged<EmployeeAccount>? onActiveChanged;
  final ValueChanged<EmployeeAccount>? onResetPassword;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: header ? Colors.white : const Color(0xFF25364A), fontWeight: header ? FontWeight.w800 : FontWeight.w600, fontSize: 13);
    Widget cell(String text, int flex) => Expanded(flex: flex, child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style));
    return Container(
      height: header ? 56 : 66,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: header ? const Color(0xFF17263B) : Colors.white, border: header ? null : const Border(top: BorderSide(color: Color(0xFFE5EAF0)))),
      child: Row(children: [
        cell(header ? 'Employee Name' : employee!.fullName, 3),
        cell(header ? 'Username' : employee!.username, 2),
        cell(header ? 'Role' : employee!.roleLabel, 2),
        Expanded(flex: 2, child: header ? Text('Status', style: style) : _StatusChip(active: employee!.isActive)),
        Expanded(
          flex: 2,
          child: header
              ? Text('Actions', textAlign: TextAlign.right, style: style)
              : Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  IconButton(tooltip: 'Reset password', onPressed: () => onResetPassword!(employee!), icon: const Icon(Icons.password_rounded, color: Color(0xFF2875D0))),
                  IconButton(tooltip: employee!.isActive ? 'Deactivate' : 'Reactivate', onPressed: isCurrentUser || employee!.role == 'owner' ? null : () => onActiveChanged!(employee!), icon: Icon(employee!.isActive ? Icons.block_rounded : Icons.replay_circle_filled_rounded, color: employee!.isActive ? const Color(0xFFCF3349) : const Color(0xFF16875F))),
                ]),
        ),
      ]),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee, required this.isCurrentUser, required this.onActiveChanged, required this.onResetPassword});
  final EmployeeAccount employee;
  final bool isCurrentUser;
  final ValueChanged<EmployeeAccount> onActiveChanged;
  final ValueChanged<EmployeeAccount> onResetPassword;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [CircleAvatar(backgroundColor: const Color(0xFFE0F2FE), child: Text(employee.fullName.isEmpty ? '?' : employee.fullName[0].toUpperCase(), style: const TextStyle(color: Color(0xFF087FB9), fontWeight: FontWeight.w900))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(employee.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)), Text('@${employee.username}', style: const TextStyle(color: Color(0xFF64748B)))])), _StatusChip(active: employee.isActive)]),
          const SizedBox(height: 14),
          Text(employee.roleLabel, style: const TextStyle(color: Color(0xFF42566E), fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(children: [OutlinedButton.icon(onPressed: () => onResetPassword(employee), icon: const Icon(Icons.password_rounded, size: 18), label: const Text('Reset Password')), const SizedBox(width: 8), if (!isCurrentUser && employee.role != 'owner') TextButton(onPressed: () => onActiveChanged(employee), child: Text(employee.isActive ? 'Deactivate' : 'Reactivate'))]),
        ]),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.centerLeft, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: active ? const Color(0xFFE2F5ED) : const Color(0xFFFCE8EC), borderRadius: BorderRadius.circular(999)), child: Text(active ? 'Active' : 'Inactive', style: TextStyle(color: active ? const Color(0xFF117655) : const Color(0xFFB4233A), fontSize: 12, fontWeight: FontWeight.w800))));
}

class _CreateEmployeeRequest {
  const _CreateEmployeeRequest(this.fullName, this.username, this.role, this.password);
  final String fullName;
  final String username;
  final String role;
  final String password;
}

class _CreateEmployeeDialog extends StatefulWidget {
  const _CreateEmployeeDialog();
  @override
  State<_CreateEmployeeDialog> createState() => _CreateEmployeeDialogState();
}

class _CreateEmployeeDialogState extends State<_CreateEmployeeDialog> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  String _role = 'employee';
  bool _obscure = true;

  @override
  void dispose() { _name.dispose(); _username.dispose(); _password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create Employee Account'),
        content: SizedBox(width: 470, child: Form(key: _key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.badge_outlined)), validator: (value) => (value?.trim().length ?? 0) < 2 ? 'Enter the employee full name.' : null),
          const SizedBox(height: 15),
          TextFormField(controller: _username, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Username', hintText: 'e.g. ali.khan', prefixIcon: Icon(Icons.alternate_email_rounded), helperText: 'Lowercase letters, numbers, dots, dashes or underscores.'), validator: (value) => RegExp(r'^[a-z0-9._-]{3,32}$').hasMatch(value?.trim().toLowerCase() ?? '') ? null : 'Enter a valid username.'),
          const SizedBox(height: 15),
          DropdownButtonFormField<String>(initialValue: _role, decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(Icons.admin_panel_settings_outlined)), items: const [DropdownMenuItem(value: 'employee', child: Text('Employee')), DropdownMenuItem(value: 'coordinator', child: Text('Coordinator'))], onChanged: (value) => setState(() => _role = value ?? 'employee')),
          const SizedBox(height: 15),
          TextFormField(controller: _password, obscureText: _obscure, decoration: InputDecoration(labelText: 'Temporary Password', prefixIcon: const Icon(Icons.lock_outline_rounded), helperText: 'Minimum 8 characters.', suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))), validator: (value) => (value?.length ?? 0) < 8 ? 'Use at least 8 characters.' : null),
        ])))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton.icon(onPressed: () { if (!(_key.currentState?.validate() ?? false)) return; Navigator.pop(context, _CreateEmployeeRequest(_name.text.trim(), _username.text.trim().toLowerCase(), _role, _password.text)); }, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Create Account'))],
      );
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.employeeName});
  final String employeeName;
  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _key = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _obscure = true;
  @override
  void dispose() { _password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('Reset Password'), content: SizedBox(width: 420, child: Form(key: _key, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Set a new temporary password for ${widget.employeeName}.'), const SizedBox(height: 16), TextFormField(controller: _password, autofocus: true, obscureText: _obscure, decoration: InputDecoration(labelText: 'New Password', helperText: 'Minimum 8 characters.', suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))), validator: (value) => (value?.length ?? 0) < 8 ? 'Use at least 8 characters.' : null)]))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () { if (_key.currentState?.validate() ?? false) Navigator.pop(context, _password.text); }, child: const Text('Reset Password'))]);
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();
  @override
  Widget build(BuildContext context) => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock_person_rounded, size: 48, color: Color(0xFF94A3B8)), SizedBox(height: 14), Text('Owner access required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), SizedBox(height: 6), Text('Only the Owner can manage employee accounts.') ]));
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(24), decoration: _cardDecoration(), child: Column(children: [const Icon(Icons.error_outline_rounded, color: Color(0xFFB4233A), size: 34), const SizedBox(height: 10), Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try Again'))]));
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(38), decoration: _cardDecoration(), child: const Column(children: [Icon(Icons.group_off_outlined, size: 42, color: Color(0xFF94A3B8)), SizedBox(height: 12), Text('No employee accounts found.', style: TextStyle(fontWeight: FontWeight.w700))]));
}
